import 'dart:async';

import 'package:flutter/material.dart';

/// Thông báo nhỏ hiện giữa màn hình rồi tự mờ dần, thay cho SnackBar ở đáy.
///
/// Dùng Overlay nên hiện được cả khi context gọi nó đã bị huỷ (ví dụ vừa đóng
/// dialog). Truyền vào OverlayState lấy từ context của State, đừng lấy từ
/// context bên trong dialog.
class AppToast {
  static void showIn(
    OverlayState? overlay, {
    required String message,
    bool success = true,
  }) {
    if (overlay == null) return;

    late OverlayEntry entry;
    bool removed = false;

    entry = OverlayEntry(
      builder: (_) => _ToastView(
        message: message,
        success: success,
        onFinished: () {
          if (removed) return;
          removed = true;
          entry.remove();
        },
      ),
    );

    overlay.insert(entry);
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    required this.message,
    required this.success,
    required this.onFinished,
  });

  final String message;
  final bool success;
  final VoidCallback onFinished;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> {
  static const Duration _fadeIn = Duration(milliseconds: 220);
  static const Duration _hold = Duration(milliseconds: 1400);
  static const Duration _fadeOut = Duration(milliseconds: 450);

  bool _visible = false;
  Timer? _hideTimer;
  Timer? _removeTimer;

  @override
  void initState() {
    super.initState();

    // Bật hiện ở frame sau, để AnimatedOpacity có trạng thái đầu là 0 -> mới
    // chạy được hiệu ứng hiện ra.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });

    _hideTimer = Timer(_fadeIn + _hold, () {
      if (mounted) setState(() => _visible = false);
    });
    _removeTimer = Timer(_fadeIn + _hold + _fadeOut, widget.onFinished);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _removeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = widget.success
        ? const Color(0xFF2E7D32)
        : const Color(0xFFC62828);
    final Duration duration = _visible ? _fadeIn : _fadeOut;

    return IgnorePointer(
      child: Center(
        child: AnimatedOpacity(
          opacity: _visible ? 1.0 : 0.0,
          duration: duration,
          curve: _visible ? Curves.easeOut : Curves.easeIn,
          child: AnimatedScale(
            scale: _visible ? 1.0 : 0.9,
            duration: duration,
            curve: _visible ? Curves.easeOutBack : Curves.easeIn,
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 300),
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2C).withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.32),
                      blurRadius: 26,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.success
                            ? Icons.check_rounded
                            : Icons.close_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
