class Tag {
  String id;
  String name;
  int colorValue;

  Tag({required this.id, required this.name, required this.colorValue});

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'colorValue': colorValue,
  };

  factory Tag.fromMap(Map<String, dynamic> map) => Tag(
    id: map['id'] ?? '',
    name: map['name'] ?? '',
    colorValue: map['colorValue'] ?? 0xFF6750A4,
  );
}

class BackgroundItem {
  final String id;
  final String title;
  final String urlOrPath;
  final String category;

  BackgroundItem({
    required this.id,
    required this.title,
    required this.urlOrPath,
    this.category = 'Tùy chọn',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'urlOrPath': urlOrPath,
    'category': category,
  };

  factory BackgroundItem.fromMap(Map<String, dynamic> map) => BackgroundItem(
    id: map['id'] ?? '',
    title: map['title'] ?? '',
    urlOrPath: map['urlOrPath'] ?? '',
    category: map['category'] ?? 'Tùy chọn',
  );
}

class Task {
  String id;
  String title;
  bool isCompleted;
  DateTime dueDate;
  String? reminderTime;
  List<Tag> tags;
  String status;
  String
  themeType; // Thêm phân loại chủ đề: 'game', 'sport', 'study', 'default'
  DateTime? eventTargetTime; // Thời gian đích để đếm ngược (nếu có)
  String? customBackgroundImage; // URL ảnh động / GIF nền tùy chỉnh

  Task({
    required this.id,
    required this.title,
    this.isCompleted = false,
    required this.dueDate,
    this.reminderTime,
    List<Tag>? tags,
    this.status = 'pending',
    this.themeType = 'default',
    this.eventTargetTime,
    this.customBackgroundImage,
  }) : tags = tags ?? [];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'isCompleted': isCompleted,
      'dueDate': dueDate.toIso8601String(),
      'reminderTime': reminderTime,
      'tags': tags.map((t) => t.toMap()).toList(),
      'status': status,
      'themeType': themeType,
      'eventTargetTime': eventTargetTime?.toIso8601String(),
      'customBackgroundImage': customBackgroundImage,
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      isCompleted: map['isCompleted'] ?? false,
      dueDate: map['dueDate'] != null
          ? DateTime.parse(map['dueDate'])
          : DateTime.now(),
      reminderTime: map['reminderTime'],
      tags: map['tags'] != null
          ? (map['tags'] as List).map((t) => Tag.fromMap(t)).toList()
          : [],
      status: map['status'] ?? 'pending',
      themeType: map['themeType'] ?? 'default',
      eventTargetTime: map['eventTargetTime'] != null
          ? DateTime.parse(map['eventTargetTime'])
          : null,
      customBackgroundImage: map['customBackgroundImage'],
    );
  }
}

class Habit {
  String id;
  String title;
  bool isCompletedToday;
  int streak;
  String? reminderTime;
  List<Tag> tags;
  String themeType;
  String? customBackgroundImage; // URL ảnh động / GIF nền tùy chỉnh

  Habit({
    required this.id,
    required this.title,
    this.isCompletedToday = false,
    this.streak = 0,
    this.reminderTime,
    List<Tag>? tags,
    this.themeType = 'default',
    this.customBackgroundImage,
  }) : tags = tags ?? [];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'isCompletedToday': isCompletedToday,
      'streak': streak,
      'reminderTime': reminderTime,
      'tags': tags.map((t) => t.toMap()).toList(),
      'themeType': themeType,
      'customBackgroundImage': customBackgroundImage,
    };
  }

  factory Habit.fromMap(Map<String, dynamic> map) {
    return Habit(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      isCompletedToday: map['isCompletedToday'] ?? false,
      streak: map['streak'] ?? 0,
      reminderTime: map['reminderTime'],
      tags: map['tags'] != null
          ? (map['tags'] as List).map((t) => Tag.fromMap(t)).toList()
          : [],
      themeType: map['themeType'] ?? 'default',
      customBackgroundImage: map['customBackgroundImage'],
    );
  }
}
