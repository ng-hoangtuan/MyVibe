import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Yêu cầu phía Android cho màn hình hiện đè lên màn hình khóa và bật sáng
/// màn hình, giống cách app đồng hồ báo thức làm.
class LockScreenService {
  static final LockScreenService instance = LockScreenService._internal();
  LockScreenService._internal();

  static const MethodChannel _channel = MethodChannel('myvibe/lockscreen');

  /// Bật chế độ hiện đè lên màn hình khóa.
  /// Trả về true nếu máy đang khóa lúc này - khi đó lúc tắt nhắc ta cần
  /// đưa app về background để người dùng thấy lại màn hình khóa.
  Future<bool> show() async {
    final result = await _invoke('showOverLockScreen');
    return result ?? false;
  }

  /// Tắt chế độ hiện đè lên màn hình khóa.
  Future<void> release() async {
    await _invoke('releaseLockScreen');
  }

  /// Đưa app về background: người dùng quay lại màn hình khóa / màn hình chờ
  /// thay vì thấy giao diện app.
  Future<void> moveToBackground() async {
    await _invoke('moveToBackground');
  }

  Future<bool?> _invoke(String method) async {
    // Chỉ Android mới đăng ký kênh này
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _channel.invokeMethod<bool>(method);
    } catch (e) {
      debugPrint('LockScreenService.$method lỗi: $e');
      return null;
    }
  }
}
