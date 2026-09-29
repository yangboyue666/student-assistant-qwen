import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 模型下载与管理状态
enum ModelStatus {
  /// 模型不存在，需要下载
  notDownloaded,

  /// 下载中
  downloading,

  /// 已下载，待加载
  ready,

  /// 加载中
  loading,

  /// 运行中（已加载到内存）
  running,

  /// 出错
  error,
}

/// 一个可选的下载源
class ModelSource {
  const ModelSource({required this.name, required this.url});
  final String name;
  final String url;
}

/// 端侧 LLM 模型管理器
///
/// 负责：
/// - 检查本地模型是否存在
/// - 从多个镜像源下载 Qwen3-0.6B GGUF 模型（自动故障切换）
/// - 上报下载进度
/// - 维护可被 UI 订阅的全局状态
class ModelManager {
  ModelManager._();
  static final ModelManager instance = ModelManager._();

  /// 下载源（按优先级排列，失败自动切换下一个）
  static const List<ModelSource> sources = [
    ModelSource(
      name: 'hf-mirror（国内镜像）',
      url:
          'https://hf-mirror.com/NobodyWho/Qwen_Qwen3-0.6B-GGUF/resolve/main/Qwen_Qwen3-0.6B-Q4_K_M.gguf',
    ),
    ModelSource(
      name: 'ModelScope（国内镜像）',
      url:
          'https://modelscope.cn/models/AI-ModelScope/Qwen3-0.6B-GGUF/resolve/master/Qwen3-0.6B-Q4_K_M.gguf',
    ),
    ModelSource(
      name: 'Hugging Face（官方源）',
      url:
          'https://huggingface.co/NobodyWho/Qwen_Qwen3-0.6B-GGUF/resolve/main/Qwen_Qwen3-0.6B-Q4_K_M.gguf',
    ),
  ];

  /// 模型文件名
  static const String modelFileName = 'Qwen3-0.6B-Q4_K_M.gguf';

  /// 临时下载文件名
  static const String _tmpFileName = '$modelFileName.part';

  /// 预期文件大小（约 405 MB，用于无 content-length 时的进度估算）
  static const int expectedFileSize = 405 * 1024 * 1024;

  /// 最小有效文件大小（小于该值视为损坏）
  static const int minValidSize = 300 * 1024 * 1024;

  ModelStatus _status = ModelStatus.notDownloaded;
  double _progress = 0.0; // 0.0 - 1.0
  String? _error;
  String? _activeSourceName;

  final StreamController<ModelStatus> _statusCtrl =
      StreamController<ModelStatus>.broadcast();
  final StreamController<double> _progressCtrl =
      StreamController<double>.broadcast();
  final StreamController<String?> _activeSourceCtrl =
      StreamController<String?>.broadcast();

  ModelStatus get status => _status;
  double get progress => _progress;
  String? get error => _error;
  String? get activeSourceName => _activeSourceName;

  Stream<ModelStatus> get statusStream => _statusCtrl.stream;
  Stream<double> get progressStream => _progressCtrl.stream;
  Stream<String?> get activeSourceStream => _activeSourceCtrl.stream;

  /// 获取模型本地路径
  Future<String> get modelPath async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$modelFileName';
  }

  Future<String> get _tmpPath async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$_tmpFileName';
  }

  /// 检查模型是否已下载（且文件有效）
  Future<bool> isModelDownloaded() async {
    final path = await modelPath;
    final file = File(path);
    if (!await file.exists()) return false;
    final len = await file.length();
    return len > minValidSize;
  }

  /// 刷新状态（不打断正在进行的下载 / 加载 / 运行）
  Future<void> refresh() async {
    if (_status == ModelStatus.downloading ||
        _status == ModelStatus.loading ||
        _status == ModelStatus.running) {
      return;
    }
    if (await isModelDownloaded()) {
      _setStatus(ModelStatus.ready);
    } else {
      _setStatus(ModelStatus.notDownloaded);
    }
  }

  /// 开始下载模型（依次尝试所有源，直到成功）
  Future<void> download() async {
    if (_status == ModelStatus.downloading) return;
    _setStatus(ModelStatus.downloading);
    _error = null;
    _progress = 0.0;
    _progressCtrl.add(0.0);

    final tmp = File(await _tmpPath);
    final errors = <String>[];

    for (final source in sources) {
      try {
        _activeSourceName = source.name;
        _activeSourceCtrl.add(source.name);
        if (await tmp.exists()) await tmp.delete();

        await _downloadOne(source.url, tmp);

        // 校验
        final len = await tmp.length();
        if (len < minValidSize) {
          throw Exception('文件不完整（${len ~/ (1024 * 1024)} MB）');
        }

        // 重命名为正式文件
        final dest = File(await modelPath);
        if (await dest.exists()) await dest.delete();
        await tmp.rename(dest.path);

        _progress = 1.0;
        _progressCtrl.add(1.0);
        _setStatus(ModelStatus.ready);
        return;
      } catch (e) {
        errors.add('${source.name}：$e');
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
        _progress = 0.0;
        _progressCtrl.add(0.0);
        // 继续尝试下一个源
      }
    }

    _error = '所有下载源均失败：\n${errors.join('\n')}';
    _setStatus(ModelStatus.error);
  }

  /// 从单个源下载到 [dest]
  Future<void> _downloadOne(String url, File dest) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw const HttpException('连接超时'),
          );

      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      final totalBytes =
          response.contentLength > 0 ? response.contentLength : expectedFileSize;

      final sink = dest.openWrite();
      int downloaded = 0;
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 30),
          onTimeout: (s) => s,
        )) {
          sink.add(chunk);
          downloaded += chunk.length;
          final p = (downloaded / totalBytes).clamp(0.0, 1.0);
          _progress = p;
          _progressCtrl.add(p);
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close(force: true);
    }
  }

  /// 标记为加载中
  void markLoading() => _setStatus(ModelStatus.loading);

  /// 标记为运行中
  void markRunning() => _setStatus(ModelStatus.running);

  /// 标记为就绪
  void markReady() => _setStatus(ModelStatus.ready);

  /// 标记出错
  void markError(String message) {
    _error = message;
    _setStatus(ModelStatus.error);
  }

  void _setStatus(ModelStatus s) {
    _status = s;
    _statusCtrl.add(s);
  }

  void dispose() {
    _statusCtrl.close();
    _progressCtrl.close();
    _activeSourceCtrl.close();
  }
}
