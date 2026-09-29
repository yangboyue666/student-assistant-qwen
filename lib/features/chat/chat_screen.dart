import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/colors.dart';
import '../../shared/widgets/glass_app_bar.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/section_indicator.dart';
import '../../shared/widgets/animated_indicators.dart';
import '../../core/llm/llm_service.dart';
import '../../core/llm/model_manager.dart';
import '../model/model_manager_screen.dart';
import 'chat_controller.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, this.embedded = false});

  /// true 表示嵌入在主界面中央，不显示自己的 AppBar
  final bool embedded;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatMessagesProvider.notifier).ensureSession();
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _inputCtrl.clear();
    try {
      await ref.read(chatMessagesProvider.notifier).send(text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatMessagesProvider);
    if (messages.isNotEmpty) _scrollToBottom();

    final modelBanner = _ModelStatusChip();

    if (widget.embedded) {
      return Column(
        children: [
          modelBanner,
          Expanded(child: _buildMessages(messages)),
          _buildInput(),
        ],
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: 'AI 助手'),
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(gradient: appBackgroundGradient)),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: const SectionIndicator(
                    label: '与 AI 对话',
                    colors: [AppColors.accent1, AppColors.accent2],
                  ),
                ),
                modelBanner,
                Expanded(child: _buildMessages(messages)),
                _buildInput(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages(List<UIMessage> messages) {
    if (messages.isEmpty) {
      return SingleChildScrollView(
        controller: _scrollCtrl,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const PulsingDot(size: 12, color: AppColors.accent1),
            const SizedBox(height: 10),
            Text(
              '我是你的本地 AI 助手',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: widget.embedded ? 15 : 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '完全离线运行，不会上传你的数据。\n试试说："明天下午3点开会"',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: widget.embedded ? 12 : 13,
              ),
            ),
            const SizedBox(height: 14),
            _QuickPrompts(embedded: widget.embedded),
            const SizedBox(height: 8),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: messages.length,
      itemBuilder: (ctx, i) {
        final m = messages[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _MessageBubble(message: m)
              .animate()
              .fadeIn(duration: 300.ms, delay: (i * 20).ms)
              .slideY(begin: 0.04, duration: 300.ms, curve: Curves.easeOutCubic),
        );
      },
    );
  }

  Widget _buildInput() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
        borderRadius: 26,
        blurSigma: 18,
        backgroundOpacity: 0.14,
        child: SafeArea(
          top: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                onPressed: _sending ? null : () => _showActions(context),
                icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.accent1),
                iconSize: 26,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    height: 1.4,
                  ),
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration.collapsed(
                    hintText: '说点什么吧...',
                    hintStyle: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 44,
                height: 44,
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.accent1, AppColors.accent2],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: _sending
                    ? const Center(child: PulsingDot(size: 10, color: Colors.white))
                    : IconButton(
                        onPressed: _send,
                        icon: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                        padding: EdgeInsets.zero,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GlassCard(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(20),
        borderRadius: 28,
        backgroundOpacity: 0.16,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionIndicator(
              label: '快捷操作',
              colors: [AppColors.accent1, AppColors.accent3],
            ),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.event_available_rounded, color: AppColors.accent2),
              title: const Text('添加日程'),
              subtitle: const Text('自然语言解析为日程并提醒'),
              onTap: () {
                Navigator.pop(ctx);
                _inputCtrl.text = '明天下午3点开会';
                setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.assignment_rounded, color: AppColors.accent3),
              title: const Text('添加作业'),
              subtitle: const Text('解析课程、标题、截止日期'),
              onTap: () {
                Navigator.pop(ctx);
                _inputCtrl.text = '后天交《高等数学》第3章习题';
                setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_view_week_rounded, color: AppColors.accent4),
              title: const Text('添加课程'),
              subtitle: const Text('解析星期、节次、教室'),
              onTap: () {
                Navigator.pop(ctx);
                _inputCtrl.text = '周一第3节有《英语》课，教室A201';
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 模型状态小芯片（一行，紧凑；点击进入模型管理页）
///
/// 不再占用大面积空间遮挡对话历史。
class _ModelStatusChip extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ModelStatusChip> createState() => _ModelStatusChipState();
}

class _ModelStatusChipState extends ConsumerState<_ModelStatusChip> {
  ModelStatus _status = ModelStatus.notDownloaded;

  @override
  void initState() {
    super.initState();
    _status = ModelManager.instance.status;
    ModelManager.instance.refresh();
    ModelManager.instance.statusStream.listen((s) {
      if (mounted) setState(() => _status = s);
    });
  }

  void _openManager() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ModelManagerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final String label;
    late final Color color;

    switch (_status) {
      case ModelStatus.running:
        icon = Icons.check_circle_rounded;
        label = '千问已启用';
        color = AppColors.success;
        break;
      case ModelStatus.ready:
      case ModelStatus.loading:
        icon = Icons.hourglass_top_rounded;
        label = '模型加载中';
        color = AppColors.warning;
        break;
      case ModelStatus.downloading:
        icon = Icons.downloading_rounded;
        label = '模型下载中';
        color = AppColors.info;
        break;
      case ModelStatus.error:
        icon = Icons.error_outline_rounded;
        label = '模型异常 · 点击处理';
        color = AppColors.danger;
        break;
      case ModelStatus.notDownloaded:
        icon = Icons.auto_awesome_rounded;
        label = '升级为千问大模型';
        color = AppColors.accent1;
        break;
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
        child: GestureDetector(
          onTap: _openManager,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.35), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right_rounded, size: 14, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickPrompts extends StatelessWidget {
  const _QuickPrompts({this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final prompts = [
      ('明天下午3点开会', Icons.event_available_rounded, AppColors.accent2),
      ('后天交数学作业', Icons.assignment_rounded, AppColors.accent3),
      ('怎么学英语更高效？', Icons.school_rounded, AppColors.accent4),
      ('1+1等于几', Icons.calculate_rounded, AppColors.accent1),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: prompts
          .map((p) => Chip(
                label: Text(
                  p.$1,
                  style: TextStyle(fontSize: embedded ? 12 : 13),
                ),
                avatar: Icon(p.$2, size: embedded ? 14 : 16, color: p.$3),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ))
          .toList(),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final UIMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.role == 'user') {
      return Align(
        alignment: Alignment.centerRight,
        child: GlassCard(
          margin: const EdgeInsets.only(left: 60),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          borderRadius: 20,
          backgroundOpacity: 0.30,
          gradient: LinearGradient(
            colors: [
              AppColors.accent2.withOpacity(0.55),
              AppColors.accent3.withOpacity(0.55),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          child: Text(
            message.content,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ),
      );
    }
    if (message.role == 'tool') {
      // 工具结果展示
      return Align(
        alignment: Alignment.centerLeft,
        child: GlassCard(
          margin: const EdgeInsets.only(right: 60),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          borderRadius: 16,
          backgroundOpacity: 0.06,
          borderOpacity: 0.25,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline_rounded, size: 16, color: AppColors.success),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  message.content,
                  style: const TextStyle(
                    color: AppColors.success,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    // assistant
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.accent1, AppColors.accent2],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent1.withOpacity(0.4),
                  blurRadius: 8,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome_rounded, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: GlassCard(
              margin: const EdgeInsets.only(right: 40),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              borderRadius: 20,
              backgroundOpacity: 0.12,
              child: message.isStreaming && message.content.isEmpty
                  ? const WaveIndicator(height: 20, barCount: 4, barWidth: 3, color: AppColors.accent1)
                  : Text(
                      message.content,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        height: 1.55,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
