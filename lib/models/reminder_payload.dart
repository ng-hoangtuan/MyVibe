/// Thông tin đi kèm thông báo, dùng để mở lại đúng công việc khi tới giờ.
///
/// Chuỗi payload có dạng: `reminder|task|<id>|lead`
/// - phần 2: 'task' hoặc 'habit'
/// - phần 4: 'lead' (báo trước 15 phút) hoặc 'exact' (đúng giờ)
class ReminderPayload {
  final String kind;
  final String id;
  final bool isLead;

  const ReminderPayload({
    required this.kind,
    required this.id,
    required this.isLead,
  });

  bool get isTask => kind == 'task';
  bool get isHabit => kind == 'habit';

  String encode() => 'reminder|$kind|$id|${isLead ? 'lead' : 'exact'}';

  static ReminderPayload? parse(String? raw) {
    if (raw == null) return null;
    final parts = raw.split('|');
    if (parts.length != 4) return null;
    if (parts[0] != 'reminder') return null;
    if (parts[1] != 'task' && parts[1] != 'habit') return null;
    if (parts[2].isEmpty) return null;
    return ReminderPayload(
      kind: parts[1],
      id: parts[2],
      isLead: parts[3] == 'lead',
    );
  }
}
