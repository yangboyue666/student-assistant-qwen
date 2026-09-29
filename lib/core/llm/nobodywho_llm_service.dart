import 'dart:async';

import 'package:nobodywho/nobodywho.dart' as nobodywho;

import '../../features/schedule/schedule_repository.dart';
import '../../features/schedule/schedule_models.dart' as sch;
import '../../features/assignments/assignments_repository.dart';
import '../../features/assignments/assignments_models.dart' as asg;
import '../../features/courses/courses_repository.dart';
import '../../features/courses/courses_models.dart' as crs;
import '../utils/nl_datetime_parser.dart';
import 'llm_service.dart';
import 'model_manager.dart';

/// 基于 nobodywho（llama.cpp）的真实端侧 LLM 服务
///
/// - 加载 Qwen3-0.6B GGUF 模型
/// - 全局单例，避免重复加载模型
/// - GPU 加载失败自动回退 CPU
/// - 带加载 / 推理超时和错误兜底
class NobodyWhoLlmService implements LlmService {
  NobodyWhoLlmService._();
  static final NobodyWhoLlmService instance = NobodyWhoLlmService._();

  nobodywho.Chat? _chat;
  bool _initialized = false;
  Future<void>? _loading; // 合并并发加载

  @override
  Future<bool> isReady() async {
    if (!await ModelManager.instance.isModelDownloaded()) return false;
    return _initialized;
  }

  @override
  String describe() => 'Qwen3-0.6B · 本地推理（nobodywho / llama.cpp）';

  /// 初始化并加载模型（并发安全，多次调用只加载一次）
  Future<void> ensureLoaded() {
    return _loading ??= _doLoad();
  }

  Future<void> _doLoad() async {
    if (_chat != null) return;
    ModelManager.instance.markLoading();

    final path = await ModelManager.instance.modelPath;
    final tools = _buildTools();

    Object? lastError;
    // 依次尝试：GPU → CPU，避免部分机型 Vulkan 不兼容导致卡死
    for (final useGpu in [true, false]) {
      try {
        _chat = await nobodywho.Chat.fromPath(
          modelPath: path,
          systemPrompt: _systemPrompt,
          tools: tools,
          contextSize: 4096,
          useGpu: useGpu,
        ).timeout(
          const Duration(seconds: 90),
          onTimeout: () =>
              throw TimeoutException('模型加载超时（${useGpu ? 'GPU' : 'CPU'}）'),
        );

        _initialized = true;
        ModelManager.instance.markRunning();
        return;
      } catch (e) {
        lastError = e;
        _chat = null;
        // GPU 失败则继续尝试 CPU；CPU 也失败则抛出
        if (!useGpu) break;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }

    _initialized = false;
    _loading = null; // 允许之后重试
    ModelManager.instance.markError('模型加载失败：$lastError');
    throw Exception('模型加载失败：$lastError');
  }

  List<nobodywho.Tool> _buildTools() {
    final createScheduleTool = nobodywho.Tool(
      name: 'create_schedule',
      description:
          '创建一条日程提醒。当用户表达"明天下午3点开会"等安排时调用。'
          'datetime 必须是 ISO8601 格式字符串，如 2026-09-30T15:00:00。',
      function: ({
        required String title,
        required String datetime,
        int? remind_before,
        String? note,
      }) async {
        try {
          final dt = DateTime.tryParse(datetime) ??
              NLDateTimeParser.parse(datetime) ??
              DateTime.now();
          final s = sch.Schedule.create(
            id: '',
            title: title,
            datetime: dt,
            remindBefore: remind_before ?? 600,
            note: note ?? '',
          );
          final created = await ScheduleRepository.instance.create(s);
          return '已创建日程「${created.title}」，时间：${created.datetime.month}月${created.datetime.day}日 ${created.shortTime}';
        } catch (e) {
          return '创建日程失败：$e';
        }
      },
      parameterDescriptions: {
        'title': '日程标题，简短描述',
        'datetime': 'ISO8601 格式的日期时间',
        'remind_before': '提前多少秒提醒，默认 600（10分钟）',
        'note': '备注，可选',
      },
    );

    final createAssignmentTool = nobodywho.Tool(
      name: 'create_assignment',
      description:
          '创建一条作业。status 可选 not_started / in_progress / completed，'
          'progress 为 0-100 的整数。due_date 为 ISO8601 格式。',
      function: ({
        required String course,
        required String title,
        required String due_date,
        String? status,
        int? progress,
      }) async {
        try {
          final due = DateTime.tryParse(due_date) ??
              NLDateTimeParser.parse(due_date) ??
              DateTime.now().add(const Duration(days: 3));
          final a = asg.Assignment.create(
            id: '',
            course: course,
            title: title,
            dueDate: due,
            status: asg.AssignmentStatus.fromCode(status ?? 'not_started'),
            progress: progress ?? 0,
            notes: '',
          );
          final created = await AssignmentRepository.instance.create(a);
          return '已创建作业「${created.title}」（${created.course}），截止：${created.dueDate.month}/${created.dueDate.day}';
        } catch (e) {
          return '创建作业失败：$e';
        }
      },
      parameterDescriptions: {
        'course': '课程名称',
        'title': '作业标题',
        'due_date': 'ISO8601 截止时间',
        'status': '状态：not_started / in_progress / completed',
        'progress': '进度 0-100',
      },
    );

    final addCourseTool = nobodywho.Tool(
      name: 'add_course',
      description: '添加一条课程到课程表。weekday: 1=周一..7=周日，period: 第几节。',
      function: ({
        required String name,
        required int weekday,
        required int period,
        String? location,
        String? teacher,
      }) async {
        try {
          final c = crs.Course.create(
            id: '',
            name: name,
            weekday: weekday,
            period: period,
            location: location ?? '',
            teacher: teacher ?? '',
          );
          final created = await CourseRepository.instance.create(c);
          return '已添加课程「${created.name}」，周${['一', '二', '三', '四', '五', '六', '日'][created.weekday - 1]}第${created.period}节';
        } catch (e) {
          return '添加课程失败：$e';
        }
      },
      parameterDescriptions: {
        'name': '课程名称',
        'weekday': '星期几，1=周一..7=周日',
        'period': '第几节课',
        'location': '教室地点',
        'teacher': '授课教师',
      },
    );

    final listSchedulesTool = nobodywho.Tool(
      name: 'list_schedules',
      description: '查询日程列表。range: today / this_week / all',
      function: ({String? range}) async {
        try {
          final List<sch.Schedule> all;
          if (range == 'today') {
            all = await ScheduleRepository.instance.byDay(DateTime.now());
          } else if (range == 'this_week') {
            all = await ScheduleRepository.instance.thisWeek();
          } else {
            all = await ScheduleRepository.instance.all();
          }
          if (all.isEmpty) return '暂无日程。';
          return all
              .map((s) =>
                  '· ${s.datetime.month}/${s.datetime.day} ${s.shortTime} ${s.title}${s.isDone ? '（已完成）' : ''}')
              .join('\n');
        } catch (e) {
          return '查询失败：$e';
        }
      },
      parameterDescriptions: {
        'range': '查询范围：today / this_week / all',
      },
    );

    final listAssignmentsTool = nobodywho.Tool(
      name: 'list_assignments',
      description: '查询作业列表。status: not_started / in_progress / completed / all',
      function: ({String? status}) async {
        try {
          final all = await AssignmentRepository.instance.all();
          final targetStatus = status == null || status == 'all'
              ? null
              : asg.AssignmentStatus.fromCode(status);
          final filtered = targetStatus == null
              ? all
              : all.where((a) => a.status == targetStatus).toList();
          if (filtered.isEmpty) return '暂无作业。';
          return filtered
              .map((a) =>
                  '· [${a.course}] ${a.title} 截止${a.dueDate.month}/${a.dueDate.day} 进度${a.progress}%')
              .join('\n');
        } catch (e) {
          return '查询失败：$e';
        }
      },
      parameterDescriptions: {
        'status': '作业状态筛选',
      },
    );

    return [
      createScheduleTool,
      createAssignmentTool,
      addCourseTool,
      listSchedulesTool,
      listAssignmentsTool,
    ];
  }

  static const String _systemPrompt = '''你是一个运行在用户手机上的学生智能助手，使用本地 AI 模型（Qwen3-0.6B）推理，完全离线运行。

你的能力：
1. 日程管理：用户用自然语言描述时间安排时，调用 create_schedule 工具创建日程。
2. 作业管理：用户描述作业时，调用 create_assignment 工具创建作业。
3. 课程表管理：用户描述课程信息时，调用 add_course 工具。
4. 学习咨询：学习方法、知识点、心理调节，直接回复。
5. 日常聊天：和用户正常对话，回答问题。

重要规则：
- 只有当用户明确要求创建日程、作业、课程时，才调用对应工具。
- 普通聊天、问答（如"1+1等于几"、"你好"）不要调用工具，直接回答。
- 调用工具时，确保参数正确（时间用 ISO8601 格式）。
- 回复保持简洁、友好，使用中文。''';

  @override
  Future<String> complete(
    List<LlmMessage> messages, {
    List<LlmTool> tools = const [],
  }) async {
    await ensureLoaded();
    final lastUser = _lastUserText(messages);
    if (lastUser == null) return '';
    final response = _chat!.ask(lastUser);
    return await response.completed();
  }

  @override
  Stream<String> stream(
    List<LlmMessage> messages, {
    List<LlmTool> tools = const [],
  }) async* {
    await ensureLoaded();
    final lastUser = _lastUserText(messages);
    if (lastUser == null) return;
    final response = _chat!.ask(lastUser);

    // 推理整体超时保护：若长时间无 token 输出则终止，避免无限"思考"
    yield* response.timeout(
      const Duration(seconds: 120),
      onTimeout: (EventSink<String> sink) {
        sink.addError(TimeoutException('AI 响应超时'));
        sink.close();
      },
    );
  }

  String? _lastUserText(List<LlmMessage> messages) {
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == 'user') return messages[i].content;
    }
    return null;
  }

  /// 释放模型资源
  Future<void> dispose() async {
    _chat = null;
    _initialized = false;
    _loading = null;
  }
}
