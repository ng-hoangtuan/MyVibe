import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/task_habit_model.dart';

/// Số phút báo trước khi tới giờ làm việc (giống đồng hồ hẹn giờ).
const int kReminderLeadMinutes = 15;

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  NotificationService._internal();

  static const String _channelId = 'task_habit_channel_id';
  static const String _channelName = 'Nhắc nhở công việc';
  static const String _channelDesc =
      'Kênh thông báo nhắc nhở lịch trình hàng ngày';

  bool _ready = false;
  bool _timezoneReady = false;
  bool _canUseExactAlarm = true;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init() async {
    if (_ready) return;
    try {
      _initTimezone();

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);

      await flutterLocalNotificationsPlugin.initialize(initializationSettings);

      // Tạo sẵn channel để thông báo hiển thị được trên Android 8+
      await _android?.createNotificationChannel(
        AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.max,
        ),
      );

      // Android 13+ bắt buộc xin quyền POST_NOTIFICATIONS mới hiện được thông báo
      await _android?.requestNotificationsPermission();

      // Android 12+ cần quyền hẹn báo thức chính xác để báo đúng phút
      final bool canExact =
          await _android?.canScheduleExactNotifications() ?? true;
      if (!canExact) {
        final bool granted =
            await _android?.requestExactAlarmsPermission() ?? false;
        _canUseExactAlarm = granted;
      } else {
        _canUseExactAlarm = true;
      }

      _ready = true;
    } catch (e, s) {
      debugPrint('NotificationService.init lỗi: $e\n$s');
    }
  }

  // ===========================================================================
  // TIMEZONE
  // ===========================================================================

  void _initTimezone() {
    if (_timezoneReady) return;
    try {
      tz_data.initializeTimeZones();

      final Duration deviceOffset = DateTime.now().timeZoneOffset;

      // Ưu tiên các múi giờ phổ biến trước cho nhanh và đúng DST
      const List<String> preferred = [
        'Asia/Ho_Chi_Minh',
        'Asia/Bangkok',
        'Asia/Singapore',
        'Asia/Tokyo',
        'Asia/Seoul',
        'Asia/Shanghai',
        'Asia/Kolkata',
        'Europe/London',
        'Europe/Paris',
        'America/New_York',
        'America/Chicago',
        'America/Los_Angeles',
        'Australia/Sydney',
        'UTC',
      ];

      tz.Location? found;
      for (final String name in preferred) {
        final tz.Location? loc = _tryLocation(name);
        if (loc != null && _offsetOf(loc) == deviceOffset) {
          found = loc;
          break;
        }
      }

      found ??= _scanForOffset(deviceOffset);
      tz.setLocalLocation(found ?? _tryLocation('UTC') ?? tz.UTC);
      _timezoneReady = true;
    } catch (e) {
      debugPrint('Không khởi tạo được timezone: $e');
    }
  }

  tz.Location? _tryLocation(String name) {
    try {
      return tz.getLocation(name);
    } catch (_) {
      return null;
    }
  }

  Duration? _offsetOf(tz.Location location) {
    try {
      return tz.TZDateTime.now(location).timeZoneOffset;
    } catch (_) {
      return null;
    }
  }

  tz.Location? _scanForOffset(Duration offset) {
    try {
      for (final tz.Location loc in tz.timeZoneDatabase.locations.values) {
        if (_offsetOf(loc) == offset) return loc;
      }
    } catch (_) {}
    return null;
  }

  // ===========================================================================
  // ID ỔN ĐỊNH
  // ===========================================================================

  /// Hash tự viết để ID không đổi sau khi khởi động lại app
  /// (String.hashCode không đảm bảo giống nhau giữa các lần chạy).
  int _stableHash(String input) {
    int hash = 7;
    for (final int unit in input.codeUnits) {
      hash = (hash * 31 + unit) & 0x3FFFFFF;
    }
    return hash;
  }

  /// slot 0 = báo trước 15 phút, slot 1 = báo đúng giờ
  int _notificationId(String rawId, int slot) => _stableHash(rawId) * 4 + slot;

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.max,
          priority: Priority.high,
        ),
      );

  // ===========================================================================
  // ĐỒNG BỘ TOÀN BỘ LỊCH NHẮC
  // ===========================================================================

  /// Huỷ hết lịch cũ rồi đặt lại theo dữ liệu hiện tại.
  /// Gọi mỗi khi người dùng tạo mới / sửa / xoá / hoàn thành công việc.
  Future<void> syncAll(List<Task> tasks, List<Habit> habits) async {
    if (!_ready) await init();
    if (!_ready) return;

    try {
      await flutterLocalNotificationsPlugin.cancelAll();

      for (final Task task in tasks) {
        await _scheduleForTask(task);
      }
      for (final Habit habit in habits) {
        await _scheduleForHabit(habit);
      }
    } catch (e, s) {
      debugPrint('syncAll lỗi: $e\n$s');
    }
  }

  Future<void> _scheduleForTask(Task task) async {
    if (task.isCompleted) return;
    final TimeOfDayValue? time = _parseTime(task.reminderTime);
    if (time == null) return;

    final DateTime target = DateTime(
      task.dueDate.year,
      task.dueDate.month,
      task.dueDate.day,
      time.hour,
      time.minute,
    );

    // Báo trước 15 phút - giống đồng hồ hẹn giờ
    await _scheduleOneShot(
      id: _notificationId(task.id, 0),
      when: target.subtract(const Duration(minutes: kReminderLeadMinutes)),
      title: '⏰ Còn $kReminderLeadMinutes phút nữa',
      body: '${task.title} sẽ bắt đầu lúc ${_fmt(time)}. Chuẩn bị nhé!',
      payload: 'task:${task.id}',
    );

    // Báo đúng giờ bắt đầu
    await _scheduleOneShot(
      id: _notificationId(task.id, 1),
      when: target,
      title: '🔔 Đã tới giờ làm việc',
      body: '${task.title} bắt đầu ngay bây giờ (${_fmt(time)}).',
      payload: 'task:${task.id}',
    );
  }

  Future<void> _scheduleForHabit(Habit habit) async {
    final TimeOfDayValue? time = _parseTime(habit.reminderTime);
    if (time == null) return;

    // Thói quen lặp lại mỗi ngày đúng giờ đó
    await _scheduleDaily(
      id: _notificationId('habit_${habit.id}', 0),
      time: _shiftBack(time, kReminderLeadMinutes),
      title: '⏰ Còn $kReminderLeadMinutes phút nữa',
      body: '${habit.title} sẽ bắt đầu lúc ${_fmt(time)}.',
      payload: 'habit:${habit.id}',
    );

    await _scheduleDaily(
      id: _notificationId('habit_${habit.id}', 1),
      time: time,
      title: '🔥 Tới giờ giữ chuỗi thói quen',
      body: '${habit.title} - chuỗi hiện tại ${habit.streak} ngày.',
      payload: 'habit:${habit.id}',
    );
  }

  Future<void> _scheduleOneShot({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    String? payload,
  }) async {
    // Bỏ qua mốc đã trôi qua
    if (!when.isAfter(DateTime.now())) return;

    await _zonedSchedule(
      id: id,
      scheduled: tz.TZDateTime.from(when, tz.local),
      title: title,
      body: body,
      payload: payload,
    );
  }

  Future<void> _scheduleDaily({
    required int id,
    required TimeOfDayValue time,
    required String title,
    required String body,
    String? payload,
  }) async {
    await _zonedSchedule(
      id: id,
      scheduled: _nextInstanceOf(time),
      title: title,
      body: body,
      payload: payload,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> _zonedSchedule({
    required int id,
    required tz.TZDateTime scheduled,
    required String title,
    required String body,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        _details,
        androidScheduleMode: _canUseExactAlarm
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
        matchDateTimeComponents: matchDateTimeComponents,
      );
    } catch (e) {
      // Thiếu quyền báo thức chính xác -> hạ cấp sang chế độ không chính xác
      debugPrint('Hẹn thông báo chính xác thất bại ($e), thử lại inexact');
      _canUseExactAlarm = false;
      try {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          scheduled,
          _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
          matchDateTimeComponents: matchDateTimeComponents,
        );
      } catch (e2) {
        debugPrint('Không hẹn được thông báo id=$id: $e2');
      }
    }
  }

  tz.TZDateTime _nextInstanceOf(TimeOfDayValue time) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  TimeOfDayValue _shiftBack(TimeOfDayValue time, int minutes) {
    int total = time.hour * 60 + time.minute - minutes;
    if (total < 0) total += 24 * 60;
    return TimeOfDayValue(total ~/ 60, total % 60);
  }

  TimeOfDayValue? _parseTime(String? raw) {
    if (raw == null) return null;
    final List<String> parts = raw.split(':');
    if (parts.length != 2) return null;
    final int? h = int.tryParse(parts[0].trim());
    final int? m = int.tryParse(parts[1].trim());
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDayValue(h, m);
  }

  String _fmt(TimeOfDayValue t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  // ===========================================================================
  // THÔNG BÁO TỨC THỜI (dùng để test nút "Thử thông báo")
  // ===========================================================================

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_ready) await init();
    try {
      await flutterLocalNotificationsPlugin.show(id, title, body, _details);
    } catch (e) {
      debugPrint('Không hiện được thông báo: $e');
    }
  }

  /// Danh sách thông báo đang chờ - hữu ích khi cần kiểm tra lịch đã đặt.
  Future<List<PendingNotificationRequest>> pending() async {
    try {
      return await flutterLocalNotificationsPlugin.pendingNotificationRequests();
    } catch (e) {
      debugPrint('Không đọc được danh sách thông báo chờ: $e');
      return <PendingNotificationRequest>[];
    }
  }
}

/// Giờ - phút đơn giản, không phụ thuộc vào Flutter material TimeOfDay
/// để service có thể dùng độc lập.
class TimeOfDayValue {
  final int hour;
  final int minute;
  const TimeOfDayValue(this.hour, this.minute);
}
