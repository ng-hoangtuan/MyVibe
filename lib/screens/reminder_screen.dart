import 'dart:async';

import 'package:flutter/material.dart';

import '../models/task_habit_model.dart';
import '../services/lock_screen_service.dart';
import '../utils/image_utils.dart';

/// Bộ màu / nhãn theo chủ đề card, dùng riêng cho màn hình nhắc toàn khung
/// (phiên bản tối hơn so với card ở màn hình chính cho dễ đọc ban đêm).
class _ReminderStyle {
  final List<Color> colors;
  final Color accent;
  final String badge;

  const _ReminderStyle(this.colors, this.accent, this.badge);

  static _ReminderStyle of(String themeType, {required bool hasCustomBg}) {
    if (hasCustomBg) {
      return const _ReminderStyle(
        [Color(0xFF1E1E2C), Color(0xFF2C1B4D)],
        Colors.amberAccent,
        '✨ TÙY CHỈNH',
      );
    }
    switch (themeType) {
      case 'game':
        return const _ReminderStyle(
          [Color(0xFF2C1B4D), Color(0xFF512DA8), Color(0xFFB71C1C)],
          Colors.amberAccent,
          '🐉 CALL OF DRAGONS',
        );
      case 'sport':
        return const _ReminderStyle(
          [Color(0xFF004D40), Color(0xFF00796B), Color(0xFF388E3C)],
          Colors.lightGreenAccent,
          '⚽ THỂ THAO',
        );
      default:
        return const _ReminderStyle(
          [Color(0xFF1E1E2C), Color(0xFF3B2E5A)],
          Color(0xFFB39DDB),
          '📌 NHIỆM VỤ',
        );
    }
  }
}

/// Màn hình nhắc toàn khung, hiện đè lên màn hình khóa khi tới giờ làm việc.
class ReminderScreen extends StatefulWidget {
  const ReminderScreen({
    super.key,
    required this.title,
    required this.themeType,
    required this.isLead,
    required this.leadMinutes,
    required this.onComplete,
    this.customBg,
    this.reminderTime,
    this.tags = const <Tag>[],
    this.subtitleInfo,
    this.completeLabel = 'Hoàn thành',
  });

  final String title;
  final String themeType;
  final String? customBg;
  final String? reminderTime;
  final List<Tag> tags;
  final String? subtitleInfo;

  /// true = thông báo báo trước N phút, false = đã tới giờ
  final bool isLead;
  final int leadMinutes;

  final String completeLabel;
  final VoidCallback onComplete;

  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  /// Màn hình này đang hiện đè lên màn hình khóa hay không.
  /// Nếu có, lúc tắt nhắc phải đưa app về background để người dùng quay lại
  /// màn hình khóa, chứ không để lộ giao diện app.
  bool _overLockScreen = false;

  /// Chặn bấm/back nhiều lần cùng lúc
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();

    // Cho phép hiện đè lên màn hình khóa + bật sáng màn hình
    LockScreenService.instance.show().then((wasLocked) {
      if (mounted) _overLockScreen = wasLocked;
    });

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _pulse.dispose();
    LockScreenService.instance.release();
    super.dispose();
  }

  bool get _hasCustomBg =>
      widget.customBg != null && widget.customBg!.trim().isNotEmpty;

  /// Đóng màn hình nhắc. Nếu đang hiện trên màn hình khóa thì đưa app về
  /// background trước, để người dùng thấy lại màn hình khóa.
  ///
  /// Dùng pop() chứ không phải maybePop(): PopScope bên dưới đặt canPop:false
  /// nên maybePop sẽ gọi lại chính hàm này thành vòng lặp.
  Future<void> _dismiss() async {
    if (_dismissing) return;
    _dismissing = true;

    if (_overLockScreen) {
      // Gọi trước khi pop để không bị nháy giao diện app một nhịp
      await LockScreenService.instance.moveToBackground();
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final style = _ReminderStyle.of(
      widget.themeType,
      hasCustomBg: _hasCustomBg,
    );

    return PopScope(
      // Back cũng phải đi qua _dismiss để quay về màn hình khóa,
      // không pop thẳng ra giao diện app.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _dismiss();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF12121A),
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildBackground(style),
            // Lớp phủ mờ để chữ luôn đọc được trên mọi ảnh nền
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.35),
                    Colors.black.withValues(alpha: 0.80),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatusChip(style),
                    const SizedBox(height: 18),
                    _buildClock(),
                    const Spacer(),
                    _buildHighlightedTask(style),
                    const Spacer(),
                    _buildActions(style),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground(_ReminderStyle style) {
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: style.colors,
        ),
      ),
    );

    if (!_hasCustomBg) return fallback;

    return Image(
      image: getCustomImageProvider(widget.customBg!.trim()),
      fit: BoxFit.cover,
      // Ảnh mạng chưa tải xong / lỗi -> vẫn có nền gradient đẹp
      errorBuilder: (context, error, stackTrace) => fallback,
      frameBuilder: (context, child, frame, wasSyncLoaded) {
        if (wasSyncLoaded || frame != null) return child;
        return fallback;
      },
    );
  }

  Widget _buildStatusChip(_ReminderStyle style) {
    final label = widget.isLead
        ? '⏰ CÒN ${widget.leadMinutes} PHÚT NỮA'
        : '🔔 ĐÃ TỚI GIỜ LÀM VIỆC';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: style.accent.withValues(alpha: 0.7)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: style.accent,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildClock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_two(_now.hour)}:${_two(_now.minute)}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 64,
            fontWeight: FontWeight.w300,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _viDate(_now),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  /// Khối làm nổi bật công việc: viền sáng nhấp nháy theo nhịp + chữ lớn.
  Widget _buildHighlightedTask(_ReminderStyle style) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_pulse.value);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: style.accent.withValues(alpha: 0.45 + 0.45 * t),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: style.accent.withValues(alpha: 0.18 + 0.22 * t),
                blurRadius: 18 + 14 * t,
                spreadRadius: 1,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            style.badge,
            style: TextStyle(
              color: style.accent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.reminderTime != null)
                _pill(
                  icon: Icons.alarm,
                  text: widget.reminderTime!,
                  accent: style.accent,
                ),
              if (widget.subtitleInfo != null &&
                  widget.subtitleInfo!.trim().isNotEmpty)
                _pill(text: widget.subtitleInfo!, accent: style.accent),
              ...widget.tags.map(
                (tag) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Color(tag.colorValue).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    tag.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill({IconData? icon, required String text, required Color accent}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: accent),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(_ReminderStyle style) {
    // Báo trước 15 phút chỉ là nhắc cho biết -> chỉ cần tắt đi.
    // Việc xác nhận hoàn thành để dành cho lúc đã tới giờ.
    if (widget.isLead) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: style.accent,
            foregroundColor: Colors.black87,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: _dismiss,
          child: const Text(
            'Tắt nhắc nhở',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.45)),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: _dismiss,
            child: const Text(
              'Để sau',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: style.accent,
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: () {
              widget.onComplete();
              _dismiss();
            },
            child: Text(
              widget.completeLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  /// Tự format ngày tiếng Việt để không phải khởi tạo locale data của intl.
  String _viDate(DateTime d) {
    const weekdays = [
      'Thứ Hai',
      'Thứ Ba',
      'Thứ Tư',
      'Thứ Năm',
      'Thứ Sáu',
      'Thứ Bảy',
      'Chủ Nhật',
    ];
    final name = weekdays[(d.weekday - 1) % 7];
    return '$name, ${_two(d.day)}/${_two(d.month)}/${d.year}';
  }
}
