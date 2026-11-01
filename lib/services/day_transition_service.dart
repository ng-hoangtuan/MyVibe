import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/task_habit_model.dart';

class DayTransitionService with WidgetsBindingObserver {
  static final DayTransitionService instance = DayTransitionService._internal();
  DayTransitionService._internal();

  // Callback để thông báo cho UI reload lại dữ liệu khi phát hiện sang ngày mới
  Function()? onNewDayDetected;

  void init({Function()? onNewDay}) {
    onNewDayDetected = onNewDay;
    WidgetsBinding.instance.addObserver(this);
    checkAndProcessNewDay();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Mỗi khi app được mở lại từ background
      checkAndProcessNewDay();
    }
  }

  Future<void> checkAndProcessNewDay() async {
    final prefs = await SharedPreferences.getInstance();

    final lastActiveDateStr = prefs.getString('last_active_date');
    final now = DateTime.now();
    final todayStr = _getDateString(now);

    if (lastActiveDateStr != null && lastActiveDateStr != todayStr) {
      // === PHÁT HIỆN ĐÃ SANG NGÀY MỚI ===
      final lastDate = DateTime.tryParse(lastActiveDateStr);
      final isConsecutiveDay =
          lastDate != null &&
          now
                  .difference(
                    DateTime(lastDate.year, lastDate.month, lastDate.day),
                  )
                  .inDays ==
              1;

      debugPrint('Chuyển ngày từ $lastActiveDateStr sang $todayStr');

      // 1. Cập nhật và Reset trạng thái thói quen
      await _processHabitsForNewDay(isConsecutiveDay);

      // 2. Gọi callback để cập nhật lại giao diện UI
      if (onNewDayDetected != null) {
        onNewDayDetected!();
      }
    }

    // Cập nhật lại ngày hoạt động gần nhất
    await prefs.setString('last_active_date', todayStr);
  }

  String _getDateString(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  Future<void> _processHabitsForNewDay(bool isConsecutiveDay) async {
    final prefs = await SharedPreferences.getInstance();
    final String? habitsString = prefs.getString('saved_habits');

    if (habitsString != null) {
      final List decoded = jsonDecode(habitsString);
      List<Habit> habits = decoded.map((item) => Habit.fromMap(item)).toList();

      for (var habit in habits) {
        if (!habit.isCompletedToday) {
          // Nếu ngày hôm trước chưa hoàn thành -> Reset streak về 0
          habit.streak = 0;
        }
        // Đặt lại trạng thái chưa hoàn thành cho ngày hôm nay
        habit.isCompletedToday = false;
      }

      // Lưu lại danh sách thói quen đã được reset vào SharedPreferences
      final habitsEncoded = jsonEncode(habits.map((h) => h.toMap()).toList());
      await prefs.setString('saved_habits', habitsEncoded);
      debugPrint('Đã tự động reset trạng thái thói quen cho ngày mới!');
    }
  }
}
