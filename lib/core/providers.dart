import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'llm/llm_service.dart';
import 'llm/pattern_llm_service.dart';
import 'llm/nobodywho_llm_service.dart';
import 'llm/model_manager.dart';

/// 当前使用的 LLM 服务
///
/// - 若模型已下载：使用 NobodyWhoLlmService（真实千问模型）
/// - 若模型未下载：使用 PatternBasedLlmService（离线模式匹配 + 工具调用）
final llmServiceProvider = Provider<LlmService>((ref) {
  return NobodyWhoLlmService.instance;
});

/// 模式匹配后备服务（模型未下载时使用）
final patternLlmServiceProvider = Provider<LlmService>((ref) {
  return PatternBasedLlmService();
});

/// 模型管理器
final modelManagerProvider = Provider<ModelManager>((ref) {
  return ModelManager.instance;
});

/// 模型是否已下载
final modelDownloadedProvider = FutureProvider<bool>((ref) async {
  return ModelManager.instance.isModelDownloaded();
});
