import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/task_habit_model.dart';

/// Đẩy dữ liệu "công việc hôm nay" ra widget ngoài màn hình chính.
///
/// Dữ liệu được ghi qua SharedPreferences nên phía Android đọc trong file
/// `FlutterSharedPreferences` với tiền tố `flutter.` (xem TaskWidgetProvider.kt).
class WidgetService {
  static final WidgetService instance = WidgetService._internal();
  WidgetService._internal();

  static const String _providerName = 'TaskWidgetProvider';
  static const String _qualifiedProviderName =
      'com.example.task_habit_app.TaskWidgetProvider';

  // Các key phải khớp đúng với TaskWidgetProvider.kt
  static const String keyHeadline = 'daily_task_headline';
  static const String keyTitle = 'daily_task_title';
  static const String keyNextTime = 'daily_task_next_time';
  static const String keyList = 'daily_task_list';
  static const String keyUpdatedAt = 'daily_task_updated_at';

  /// Tính toán lại nội dung widget và yêu cầu Android vẽ lại.
  Future<void> sync(List<Task> tasks, List<Habit> habits) async {
    try {
      final DateTime now = DateTime.now();

      final List<Task> todayTasks = tasks
          .where((Task t) => _isSameDay(t.dueDate, now))
          .toList();
      final List<Task> pendingTasks = todayTasks
          .where((Task t) => !t.isCompleted)
          .toList();
      final List<Habit> pendingHabits = habits
          .where((Habit h) => !h.isCompletedToday)
          .toList();

      // Sắp xếp theo giờ nhắc, việc chưa đặt giờ xuống cuối
      pendingTasks.sort(
        (Task a, Task b) =>
            _minutesOf(a.reminderTime).compareTo(_minutesOf(b.reminderTime)),
      );

      final int totalPending = pendingTasks.length + pendingHabits.length;
      final int doneToday = todayTasks.where((Task t) => t.isCompleted).length;

      final String headline;
      final String title;
      final String nextTime;

      if (totalPending == 0) {
        headline = todayTasks.isEmpty && habits.isEmpty
            ? 'Hôm nay chưa có công việc nào'
            : 'Hôm nay xong hết việc rồi 🎉';
        title = todayTasks.isEmpty && habits.isEmpty
            ? 'Chạm để thêm công việc mới cho hôm nay.'
            : 'Đã hoàn thành $doneToday việc. Nghỉ ngơi thôi!';
        nextTime = '';
      } else {
        headline = '$totalPending việc cần làm hôm nay';

        // Việc tiếp theo: ưu tiên task có giờ, nếu không thì lấy thói quen
        final String? nextTitle = pendingTasks.isNotEmpty
            ? pendingTasks.first.title
            : (pendingHabits.isNotEmpty ? pendingHabits.first.title : null);
        final String? nextRaw = pendingTasks.isNotEmpty
            ? pendingTasks.first.reminderTime
            : (pendingHabits.isNotEmpty
                  ? pendingHabits.first.reminderTime
                  : null);

        title = nextTitle ?? 'Chạm để xem chi tiết';
        nextTime = nextRaw ?? '';
      }

      // Tối đa 4 dòng chi tiết cho widget cỡ lớn
      final List<String> lines = <String>[
        ...pendingTasks
            .take(3)
            .map(
              (Task t) => t.reminderTime != null
                  ? '• ${t.reminderTime}  ${t.title}'
                  : '• ${t.title}',
            ),
        ...pendingHabits
            .take(2)
            .map(
              (Habit h) => h.reminderTime != null
                  ? '🔥 ${h.reminderTime}  ${h.title}'
                  : '🔥 ${h.title}',
            ),
      ].take(4).toList();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keyHeadline, headline);
      await prefs.setString(keyTitle, title);
      await prefs.setString(keyNextTime, nextTime);
      await prefs.setString(
        keyList,
        lines.isEmpty ? 'Không còn việc nào đang chờ.' : lines.join('\n'),
      );
      await prefs.setString(
        keyUpdatedAt,
        '${_two(now.hour)}:${_two(now.minute)}',
      );

      await _requestRedraw();
    } catch (e, s) {
      debugPrint('WidgetService.sync lỗi: $e\n$s');
    }
  }

  Future<void> _requestRedraw() async {
    if (kIsWeb) return;
    try {
      await HomeWidget.updateWidget(
        name: _providerName,
        androidName: _providerName,
        qualifiedAndroidName: _qualifiedProviderName,
      );
    } catch (e) {
      debugPrint('Không cập nhật được widget: $e');
    }
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Đổi "HH:mm" thành số phút để sắp xếp; không có giờ -> đẩy xuống cuối.
  int _minutesOf(String? raw) {
    if (raw == null) return 24 * 60 + 1;
    final List<String> parts = raw.split(':');
    if (parts.length != 2) return 24 * 60 + 1;
    final int? h = int.tryParse(parts[0].trim());
    final int? m = int.tryParse(parts[1].trim());
    if (h == null || m == null) return 24 * 60 + 1;
    return h * 60 + m;
  }

  String _two(int v) => v.toString().padLeft(2, '0');
}
