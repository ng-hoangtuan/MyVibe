import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phát hiện app bước sang ngày mới (mở lại app, hoặc qua 00:00).
///
/// Service này KHÔNG tự ghi dữ liệu thói quen nữa. Trước đây nó vừa ghi
/// `saved_habits` xuống prefs trong khi màn hình chính cũng đang đọc/ghi cùng
/// key đó, nên hai bên ghi đè lẫn nhau và làm mất dữ liệu. Giờ nó chỉ báo
/// "đã sang ngày mới" và để màn hình chính - nơi duy nhất giữ danh sách - tự
/// cập nhật rồi lưu lại.
class DayTransitionService with WidgetsBindingObserver {
  static final DayTransitionService instance = DayTransitionService._internal();
  DayTransitionService._internal();

  static const String _lastActiveKey = 'last_active_date';

  /// Callback để màn hình chính reset thói quen + reload dữ liệu.
  Future<void> Function()? onNewDayDetected;

  bool _observerAdded = false;
  bool _running = false;

  Future<void> init({Future<void> Function()? onNewDay}) async {
    onNewDayDetected = onNewDay;
    if (!_observerAdded) {
      WidgetsBinding.instance.addObserver(this);
      _observerAdded = true;
    }
    await checkAndProcessNewDay();
  }

  void dispose() {
    if (_observerAdded) {
      WidgetsBinding.instance.removeObserver(this);
      _observerAdded = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Mỗi khi app được mở lại từ background
      checkAndProcessNewDay();
    }
  }

  Future<void> checkAndProcessNewDay() async {
    // Chặn chạy chồng nhau (lifecycle resume có thể bắn liên tiếp)
    if (_running) return;
    _running = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      final String? lastActiveDateStr = prefs.getString(_lastActiveKey);
      final String todayStr = _getDateString(DateTime.now());

      if (lastActiveDateStr == todayStr) return;

      // Ghi ngày mới NGAY để lần gọi tiếp theo không xử lý lại lần hai
      await prefs.setString(_lastActiveKey, todayStr);

      // Lần chạy đầu tiên của app thì không coi là "chuyển ngày"
      if (lastActiveDateStr == null) return;

      debugPrint('Chuyển ngày từ $lastActiveDateStr sang $todayStr');
      final Future<void> Function()? callback = onNewDayDetected;
      if (callback != null) await callback();
    } catch (e, s) {
      debugPrint('checkAndProcessNewDay lỗi: $e\n$s');
    } finally {
      _running = false;
    }
  }

  String _getDateString(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }
}
