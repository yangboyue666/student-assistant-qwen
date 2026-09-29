import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../shared/widgets/glass_app_bar.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/section_indicator.dart';
import '../../core/llm/model_manager.dart';
import '../../core/llm/nobodywho_llm_service.dart';

/// 本地 AI 模型管理页
///
/// - 查看千问模型状态
/// - 从多个镜像源下载（自动故障切换）
/// - 下载完成后后台自动加载并热接入对话框
class ModelManagerScreen extends ConsumerStatefulWidget {
  const ModelManagerScreen({super.key});

  @override
  ConsumerState<ModelManagerScreen> createState() => _ModelManagerScreenState();
}

class _ModelManagerScreenState extends ConsumerState<ModelManagerScreen> {
  ModelStatus _status = ModelStatus.notDownloaded;
  double _progress = 0.0;
  String? _error;
  String? _sourceName;

  @override
  void initState() {
    super.initState();
    final m = ModelManager.instance;
    _status = m.status;
    _progress = m.progress;
    _error = m.error;
    _sourceName = m.activeSourceName;
    m.refresh();

    m.statusStream.listen((s) {
      if (mounted) {
        setState(() {
          _status = s;
          _error = m.error;
        });
        // 下载完成（ready）后自动后台加载，实现"无感升级"
        if (s == ModelStatus.ready) {
          _autoLoad();
        }
      }
    });
    m.progressStream.listen((p) {
      if (mounted) setState(() => _progress = p);
    });
    m.activeSourceStream.listen((n) {
      if (mounted) setState(() => _sourceName = n);
    });
  }

  Future<void> _download() async {
    setState(() => _error = null);
    await ModelManager.instance.download();
  }

  /// 下载完成后自动加载模型（不阻塞 UI，失败静默，用户聊天时会再次尝试）
  Future<void> _autoLoad() async {
    try {
      await NobodyWhoLlmService.instance.ensureLoaded();
    } catch (_) {
      // 后台预加载失败不打断用户；真正发消息时还会重试 / 回退
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: '本地 AI 模型'),
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(gradient: appBackgroundGradient)),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionIndicator(
                    label: '千问 Qwen3-0.6B',
                    colors: [AppColors.accent1, AppColors.accent2],
                  ),
                  const SizedBox(height: 16),
                  _buildInfoCard(),
                  const SizedBox(height: 16),
                  _buildStatusCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      borderRadius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _InfoRow(
            icon: Icons.offline_bolt_rounded,
            text: '完全离线运行，对话数据不会上传',
          ),
          SizedBox(height: 12),
          _InfoRow(
            icon: Icons.hub_rounded,
            text: '约 400MB，多镜像源自动切换下载',
          ),
          SizedBox(height: 12),
          _InfoRow(
            icon: Icons.auto_awesome_rounded,
            text: '下载完成后自动加载，对话框直接变智能',
          ),
          SizedBox(height: 12),
          _InfoRow(
            icon: Icons.schedule_rounded,
            text: '不下载也能正常使用日程、作业等基础 AI',
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    switch (_status) {
      case ModelStatus.running:
        return _card(
          child: Column(
            children: [
              Row(
                children: const [
                  Icon(Icons.check_circle_rounded,
                      color: AppColors.success, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '千问模型已启用',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '现在返回对话框，直接和千问聊天即可。',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        );

      case ModelStatus.ready:
        return _card(
          child: _busyRow('模型已下载，正在后台加载...', '即将自动接入对话框'),
        );

      case ModelStatus.loading:
        return _card(
          child: _busyRow('正在加载千问模型...', '首次加载可能需要几十秒'),
        );

      case ModelStatus.downloading:
        final pct = (_progress * 100).toStringAsFixed(0);
        return _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.accent1),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '正在下载... $pct%',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 15),
                  ),
                ],
              ),
              if (_sourceName != null) ...[
                const SizedBox(height: 6),
                Text('当前源：$_sourceName',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ],
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.white.withOpacity(0.1),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.accent1),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '请保持此页面在前台，下载完成会自动加载',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        );

      case ModelStatus.error:
        return _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.danger, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('下载 / 加载失败',
                        style: TextStyle(
                            color: AppColors.danger,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _download,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent1.withOpacity(0.85),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重新下载'),
                ),
              ),
            ],
          ),
        );

      case ModelStatus.notDownloaded:
        return _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.download_rounded,
                      color: AppColors.accent1, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('下载千问大模型',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Qwen3-0.6B · 约 400MB · 多镜像源',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _download,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent1.withOpacity(0.85),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('开始下载'),
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _busyRow(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.accent1),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 15)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(subtitle,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      borderRadius: 24,
      backgroundOpacity: 0.12,
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.accent1, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
          ),
        ),
      ],
    );
  }
}
