import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_habit_app/models/task_habit_model.dart';
import 'package:task_habit_app/utils/image_utils.dart';

void main() {
  group('Task & Habit Custom Background Tests', () {
    test(
      'Task supports customBackgroundImage serialization and deserialization',
      () {
        final task = Task(
          id: 't_custom_1',
          title: 'Chơi game với GIF động',
          dueDate: DateTime(2026, 10, 31),
          themeType: 'game',
          customBackgroundImage: 'https://example.com/dragon.gif',
        );

        final map = task.toMap();
        expect(map['customBackgroundImage'], 'https://example.com/dragon.gif');

        final fromMapTask = Task.fromMap(map);
        expect(fromMapTask.id, 't_custom_1');
        expect(fromMapTask.title, 'Chơi game với GIF động');
        expect(fromMapTask.themeType, 'game');
        expect(
          fromMapTask.customBackgroundImage,
          'https://example.com/dragon.gif',
        );
      },
    );

    test(
      'Task backwards compatibility when customBackgroundImage is missing',
      () {
        final legacyMap = {
          'id': 't_legacy_1',
          'title': 'Nhiệm vụ cũ không có custom background',
          'isCompleted': false,
          'dueDate': DateTime(2026, 10, 31).toIso8601String(),
          'themeType': 'sport',
        };

        final legacyTask = Task.fromMap(legacyMap);
        expect(legacyTask.id, 't_legacy_1');
        expect(legacyTask.customBackgroundImage, isNull);
      },
    );

    test(
      'Habit supports customBackgroundImage serialization and deserialization',
      () {
        final habit = Habit(
          id: 'h_custom_1',
          title: 'Tập gym mỗi ngày',
          themeType: 'sport',
          customBackgroundImage: 'https://example.com/gym.gif',
        );

        final map = habit.toMap();
        expect(map['customBackgroundImage'], 'https://example.com/gym.gif');

        final fromMapHabit = Habit.fromMap(map);
        expect(fromMapHabit.id, 'h_custom_1');
        expect(
          fromMapHabit.customBackgroundImage,
          'https://example.com/gym.gif',
        );
      },
    );

    test(
      'Habit backwards compatibility when customBackgroundImage is missing',
      () {
        final legacyMap = {
          'id': 'h_legacy_1',
          'title': 'Thói quen cũ',
          'isCompletedToday': false,
          'streak': 5,
          'themeType': 'default',
        };

        final legacyHabit = Habit.fromMap(legacyMap);
        expect(legacyHabit.id, 'h_legacy_1');
        expect(legacyHabit.streak, 5);
        expect(legacyHabit.customBackgroundImage, isNull);
      },
    );

    test('BackgroundItem supports serialization and deserialization', () {
      final bgItem = BackgroundItem(
        id: 'bg_101',
        title: 'Rồng thần bóng đêm',
        category: 'Game',
        urlOrPath: 'https://example.com/dragon_bg.gif',
      );

      final map = bgItem.toMap();
      expect(map['id'], 'bg_101');
      expect(map['title'], 'Rồng thần bóng đêm');
      expect(map['category'], 'Game');
      expect(map['urlOrPath'], 'https://example.com/dragon_bg.gif');

      final fromMap = BackgroundItem.fromMap(map);
      expect(fromMap.id, 'bg_101');
      expect(fromMap.title, 'Rồng thần bóng đêm');
      expect(fromMap.category, 'Game');
      expect(fromMap.urlOrPath, 'https://example.com/dragon_bg.gif');
    });

    test('getCustomImageProvider creates appropriate ImageProvider', () {
      final networkProvider = getCustomImageProvider(
        'https://example.com/image.jpg',
      );
      expect(networkProvider, isA<NetworkImage>());

      final memoryProvider = getCustomImageProvider(
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      );
      expect(memoryProvider, isA<MemoryImage>());
    });
  });
}
