import 'package:flutter/material.dart';

import '../features/schedule/schedule_screen.dart';
import '../features/assignments/assignments_screen.dart';
import '../features/courses/courses_screen.dart';
import '../features/moods/mood_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/model/model_manager_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const hub = '/';
  static const schedule = '/schedule';
  static const assignments = '/assignments';
  static const courses = '/courses';
  static const mood = '/mood';
  static const chat = '/chat';
  static const modelManager = '/model-manager';

  static Map<String, WidgetBuilder> routes() => {
        hub: (_) => const _Placeholder(),
        schedule: (_) => const ScheduleScreen(),
        assignments: (_) => const AssignmentsScreen(),
        courses: (_) => const CoursesScreen(),
        mood: (_) => const MoodScreen(),
        chat: (_) => const ChatScreen(),
        modelManager: (_) => const ModelManagerScreen(),
      };

  static void push(BuildContext context, String route) {
    if (route == schedule) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScheduleScreen()));
    } else if (route == assignments) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AssignmentsScreen()));
    } else if (route == courses) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CoursesScreen()));
    } else if (route == mood) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MoodScreen()));
    } else if (route == chat) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChatScreen()));
    }
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
