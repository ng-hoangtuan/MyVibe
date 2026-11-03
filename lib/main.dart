import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/reminder_payload.dart';
import 'models/task_habit_model.dart';
import 'screens/reminder_screen.dart';
import 'services/day_transition_service.dart';
import 'services/notification_service.dart';
import 'services/widget_service.dart';
import 'utils/image_utils.dart';
import 'widgets/app_toast.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // DayTransitionService được khởi tạo trong HomeScreen.initState để nó có
  // callback reload UI. Gọi ở cả hai nơi như trước sẽ chạy hai lần song song
  // và làm hỏng dữ liệu thói quen.
  await NotificationService.instance.init();
  runApp(const TaskHabitApp());
}

/// Dùng để mở màn hình nhắc toàn khung từ ngoài cây widget (khi thông báo nổ).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class TaskHabitApp extends StatelessWidget {
  const TaskHabitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Task & Habit Tracker',
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(title: 'Hôm Nay Của Tôi'),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.title});

  final String title;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _selectedDate = DateTime.now();
  List<Task> _tasks = [];
  List<Habit> _habits = [];

  // Tab: 0 = Cần làm, 1 = Đã hoàn thành.
  // Dùng ValueNotifier thay vì biến State + setState: onPageChanged nổ đúng
  // lúc kéo tới giữa, nếu setState thì cả cây widget (gồm CẢ HAI tab với toàn
  // bộ thẻ) bị dựng lại ngay giữa cú kéo -> khựng lại. Giờ chỉ thanh tab được
  // dựng lại.
  final ValueNotifier<int> _tabIndex = ValueNotifier<int>(0);
  final PageController _pageController = PageController();
  Tag? _selectedFilterTag;

  List<Tag> _availableTags = [
    Tag(id: 't1', name: 'Gaming (Dragons)', colorValue: 0xFFFF5722),
    Tag(id: 't2', name: 'Thể thao', colorValue: 0xFF4CAF50),
    Tag(id: 't3', name: 'Công việc', colorValue: 0xFF2196F3),
    Tag(id: 't4', name: 'Học tập', colorValue: 0xFFFF9800),
  ];

  // Kho thư viện hình nền động & tĩnh có sẵn
  List<BackgroundItem> _bgLibrary = [];

  final List<BackgroundItem> _defaultBgLibrary = [
    BackgroundItem(
      id: 'bg1',
      title: 'Rồng Thần Chiến Binh',
      category: 'Game',
      urlOrPath:
          'https://images.unsplash.com/photo-1579783900882-c0d3dad7b119?w=800',
    ),
    BackgroundItem(
      id: 'bg2',
      title: 'Thành Phố Cyberpunk',
      category: 'Game',
      urlOrPath:
          'https://images.unsplash.com/photo-1542751371-adc38448a05e?w=800',
    ),
    BackgroundItem(
      id: 'bg3',
      title: 'Sân Cỏ Sôi Động',
      category: 'Thể thao',
      urlOrPath:
          'https://images.unsplash.com/photo-1508098682722-e99c43a406b2?w=800',
    ),
    BackgroundItem(
      id: 'bg4',
      title: 'Nhịp Điệu Thể Thao',
      category: 'Thể thao',
      urlOrPath:
          'https://images.unsplash.com/photo-1517466787929-bc90951d0974?w=800',
    ),
    BackgroundItem(
      id: 'bg5',
      title: 'Đêm Sao Tĩnh Lặng',
      category: 'Học tập',
      urlOrPath:
          'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=800',
    ),
    BackgroundItem(
      id: 'bg6',
      title: 'Cực Quang Huyền Diệu',
      category: 'Chill',
      urlOrPath:
          'https://images.unsplash.com/photo-1531366936337-7c912a4589a7?w=800',
    ),
  ];

  bool _isLoading = true;

  /// Chỉ cho phép ghi xuống bộ nhớ SAU khi đã đọc xong dữ liệu cũ.
  /// Nếu không, một lần lưu xảy ra trong lúc đang đọc sẽ ghi đè dữ liệu thật
  /// bằng danh sách mặc định -> người dùng thấy "không lưu được / mất dữ liệu".
  bool _hasLoaded = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadDataFromPrefs();
    // Khởi tạo sau khi đã load để callback chuyển ngày làm việc trên dữ liệu thật
    await DayTransitionService.instance.init(onNewDay: _handleNewDay);

    // Gắn callback trước khi xử lý thông báo đã mở app
    NotificationService.instance.onReminderOpened = _openReminderScreen;
    await NotificationService.instance.handleLaunchFromNotification();

    await _syncExternal();
  }

  Task? _findTaskById(String id) {
    for (final task in _tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  Habit? _findHabitById(String id) {
    for (final habit in _habits) {
      if (habit.id == id) return habit;
    }
    return null;
  }

  /// Mở màn hình nhắc toàn khung với ảnh nền của chính card đó.
  void _openReminderScreen(ReminderPayload payload) {
    if (!mounted) return;

    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;

    final ReminderScreen? screen;
    if (payload.isTask) {
      final task = _findTaskById(payload.id);
      screen = task == null
          ? null
          : ReminderScreen(
              title: task.title,
              themeType: task.themeType,
              customBg: task.customBackgroundImage,
              reminderTime: task.reminderTime,
              tags: task.tags,
              subtitleInfo:
                  'Hạn: ${DateFormat('dd/MM/yyyy').format(task.dueDate)}',
              isLead: payload.isLead,
              leadMinutes: kReminderLeadMinutes,
              onComplete: () {
                setState(() => task.isCompleted = true);
                _persistAndSync(showFeedback: false);
              },
            );
    } else {
      final habit = _findHabitById(payload.id);
      screen = habit == null
          ? null
          : ReminderScreen(
              title: habit.title,
              themeType: habit.themeType,
              customBg: habit.customBackgroundImage,
              reminderTime: habit.reminderTime,
              tags: habit.tags,
              subtitleInfo: 'Chuỗi: ${habit.streak} ngày',
              isLead: payload.isLead,
              leadMinutes: kReminderLeadMinutes,
              completeLabel: 'Đã làm hôm nay',
              onComplete: () {
                setState(() {
                  if (!habit.isCompletedToday) {
                    habit.isCompletedToday = true;
                    habit.streak++;
                  }
                });
                _persistAndSync(showFeedback: false);
              },
            );
    }

    // Công việc đã bị xoá trước khi thông báo nổ
    if (screen == null) return;

    final ReminderScreen reminder = screen;
    navigator.push(MaterialPageRoute<void>(builder: (_) => reminder));
  }

  @override
  void dispose() {
    _tabIndex.dispose();
    _pageController.dispose();
    DayTransitionService.instance.dispose();
    super.dispose();
  }

  /// Bấm vào thanh tab: chạy animation sang trang đó.
  /// _tabIndex được cập nhật trong onPageChanged của PageView.
  void _goToTab(int index) {
    if (_tabIndex.value == index) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  /// Sang ngày mới: reset trạng thái thói quen trên danh sách đang giữ trong
  /// bộ nhớ rồi lưu lại một lần duy nhất.
  Future<void> _handleNewDay() async {
    if (!mounted) return;
    setState(() {
      for (final habit in _habits) {
        if (!habit.isCompletedToday) {
          // Hôm trước không hoàn thành -> mất chuỗi
          habit.streak = 0;
        }
        habit.isCompletedToday = false;
      }
    });
    await _persistAndSync(showFeedback: false);
  }

  Future<void> _loadDataFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      _tasks = _decodeList<Task>(
        prefs.getString('saved_tasks'),
        (map) => Task.fromMap(map),
        fallback: () => [
          Task(
            id: '1',
            title: 'Săn Behemoth & Mở cổng 4',
            dueDate: DateTime.now(),
            reminderTime: '20:00',
            tags: [_availableTags[0]],
            themeType: 'game',
          ),
        ],
      );

      _habits = _decodeList<Habit>(
        prefs.getString('saved_habits'),
        (map) => Habit.fromMap(map),
        fallback: () => [
          Habit(
            id: 'h1',
            title: 'Đánh cầu lông 30 phút',
            streak: 3,
            reminderTime: '17:30',
            tags: [_availableTags[1]],
            themeType: 'sport',
          ),
        ],
      );

      final loadedTags = _decodeList<Tag>(
        prefs.getString('saved_tags'),
        (map) => Tag.fromMap(map),
        fallback: () => _availableTags,
      );
      // Không bao giờ để danh sách nhãn rỗng, UI đang dùng _availableTags[0]
      if (loadedTags.isNotEmpty) _availableTags = loadedTags;

      _bgLibrary = _decodeList<BackgroundItem>(
        prefs.getString('saved_bg_library'),
        (map) => BackgroundItem.fromMap(map),
        fallback: () => List.from(_defaultBgLibrary),
      );
    } catch (e, s) {
      debugPrint('Không đọc được dữ liệu đã lưu: $e\n$s');
    } finally {
      // Luôn mở khoá để app không bị treo ở vòng xoay loading
      _hasLoaded = true;
      if (mounted) {
        setState(() => _isLoading = false);
      } else {
        _isLoading = false;
      }
    }
  }

  /// Giải mã danh sách JSON, bỏ qua từng bản ghi lỗi thay vì làm hỏng cả danh sách.
  List<T> _decodeList<T>(
    String? raw,
    T Function(Map<String, dynamic>) fromMap, {
    required List<T> Function() fallback,
  }) {
    if (raw == null || raw.trim().isEmpty) return fallback();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return fallback();
      final result = <T>[];
      for (final item in decoded) {
        try {
          if (item is Map) {
            result.add(fromMap(Map<String, dynamic>.from(item)));
          }
        } catch (e) {
          debugPrint('Bỏ qua 1 bản ghi lỗi khi đọc dữ liệu: $e');
        }
      }
      return result;
    } catch (e) {
      debugPrint('JSON đã lưu bị lỗi, dùng dữ liệu mặc định: $e');
      return fallback();
    }
  }

  Future<bool> _saveDataToPrefs() async {
    // Chưa load xong thì không ghi, tránh ghi đè mất dữ liệu cũ
    if (!_hasLoaded) {
      debugPrint('Bỏ qua lần lưu này vì chưa đọc xong dữ liệu cũ.');
      return false;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'saved_tasks',
        jsonEncode(_tasks.map((t) => t.toMap()).toList()),
      );
      await prefs.setString(
        'saved_habits',
        jsonEncode(_habits.map((h) => h.toMap()).toList()),
      );
      await prefs.setString(
        'saved_tags',
        jsonEncode(_availableTags.map((t) => t.toMap()).toList()),
      );
      await prefs.setString(
        'saved_bg_library',
        jsonEncode(_bgLibrary.map((b) => b.toMap()).toList()),
      );
      return true;
    } catch (e, s) {
      debugPrint('LƯU DỮ LIỆU THẤT BẠI: $e\n$s');
      return false;
    }
  }

  /// Lưu xuống bộ nhớ, rồi đồng bộ widget ngoài màn hình chính và đặt lại
  /// toàn bộ lịch thông báo nhắc nhở.
  Future<void> _persistAndSync({bool showFeedback = true}) async {
    final bool ok = await _saveDataToPrefs();
    if (!ok) {
      if (mounted && showFeedback) {
        AppToast.showIn(
          Overlay.maybeOf(context),
          message: 'Lưu dữ liệu thất bại, vui lòng thử lại.',
          success: false,
        );
      }
      return;
    }
    await _syncExternal();
  }

  /// Đẩy dữ liệu ra widget + đặt lại lịch nhắc nhở.
  Future<void> _syncExternal() async {
    await WidgetService.instance.sync(_tasks, _habits);
    await NotificationService.instance.syncAll(_tasks, _habits);
  }

  /// Tải ảnh cục bộ từ thiết bị qua image_picker (hỗ trợ cả Web & Mobile)
  Future<void> _pickImageFromDevice(Function(String) onImagePicked) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        if (kIsWeb) {
          final bytes = await pickedFile.readAsBytes();
          final base64String = 'data:image/png;base64,${base64Encode(bytes)}';
          onImagePicked(base64String);
        } else {
          // image_picker trả về file nằm trong thư mục cache, Android có thể
          // dọn bất cứ lúc nào -> phải copy sang thư mục riêng của app,
          // nếu không ảnh nền sẽ biến mất sau khi khởi động lại.
          final savedPath = await _copyImageToAppStorage(pickedFile);
          onImagePicked(savedPath ?? pickedFile.path);
        }
      }
    } catch (e) {
      debugPrint('Lỗi chọn ảnh từ thiết bị: $e');
      if (mounted) {
        AppToast.showIn(
          Overlay.maybeOf(context),
          message: 'Không lấy được ảnh từ thiết bị.',
          success: false,
        );
      }
    }
  }

  /// Copy ảnh vừa chọn vào thư mục dữ liệu của app để giữ được lâu dài.
  Future<String?> _copyImageToAppStorage(XFile picked) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final bgDir = Directory('${docsDir.path}/card_backgrounds');
      if (!await bgDir.exists()) {
        await bgDir.create(recursive: true);
      }
      final name = picked.name;
      final ext = name.contains('.') ? name.split('.').last : 'jpg';
      final dest =
          '${bgDir.path}/bg_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await File(picked.path).copy(dest);
      return dest;
    } catch (e) {
      debugPrint('Không copy được ảnh vào bộ nhớ app: $e');
      return null;
    }
  }

  /// Hộp thoại tạo nhãn dán tùy chỉnh
  void _showCreateTagDialog(Function(Tag) onTagCreated) {
    String tagName = '';
    int selectedColor = 0xFF9C27B0;
    final List<int> colorOptions = [
      0xFFE91E63,
      0xFF9C27B0,
      0xFF3F51B5,
      0xFF2196F3,
      0xFF4CAF50,
      0xFFFF9800,
      0xFF009688,
      0xFF795548,
    ];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateColor) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                'Tạo nhãn dán mới',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    autofocus: true,
                    onChanged: (val) => tagName = val,
                    decoration: InputDecoration(
                      hintText: 'Tên nhãn (VD: Dự án, Sức khỏe...)',
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: colorOptions.map((color) {
                      return GestureDetector(
                        onTap: () => setStateColor(() => selectedColor = color),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Color(color),
                            shape: BoxShape.circle,
                            border: selectedColor == color
                                ? Border.all(color: Colors.black, width: 2.5)
                                : null,
                          ),
                          child: selectedColor == color
                              ? const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (tagName.trim().isNotEmpty) {
                      final newTag = Tag(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        name: tagName.trim(),
                        colorValue: selectedColor,
                      );
                      setState(() => _availableTags.add(newTag));
                      _persistAndSync();
                      onTagCreated(newTag);
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Thêm'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Modal chọn hình nền từ kho thư viện Background Library
  void _showBackgroundLibrarySheet(Function(String) onSelect) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            return DraggableScrollableSheet(
              initialChildSize: 0.72,
              minChildSize: 0.45,
              maxChildSize: 0.92,
              expand: false,
              builder: (context, scrollController) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Kho Thư Viện Background',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Chọn hình nền cho Card của bạn',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              textStyle: const TextStyle(fontSize: 11),
                            ),
                            icon: const Icon(
                              Icons.add_photo_alternate,
                              size: 15,
                            ),
                            label: const Text('Thêm vào kho'),
                            onPressed: () {
                              _showAddBackgroundToLibraryDialog(() {
                                setStateSheet(() {});
                                setState(() {});
                              });
                            },
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Expanded(
                        child: GridView.builder(
                          controller: scrollController,
                          itemCount: _bgLibrary.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 1.35,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                          itemBuilder: (context, index) {
                            final bgItem = _bgLibrary[index];
                            final isCustom = !_defaultBgLibrary.any(
                              (item) => item.id == bgItem.id,
                            );

                            return InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                onSelect(bgItem.urlOrPath);
                                Navigator.pop(sheetContext);
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Container(
                                      color: const Color(0xFF1E1E2C),
                                      child: Image(
                                        image: getCustomImageProvider(
                                          bgItem.urlOrPath,
                                        ),
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                const Center(
                                                  child: Icon(
                                                    Icons.broken_image,
                                                    color: Colors.white54,
                                                  ),
                                                ),
                                      ),
                                    ),
                                    Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.transparent,
                                            Colors.black.withValues(
                                              alpha: 0.75,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 6,
                                      left: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.6,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          bgItem.category,
                                          style: const TextStyle(
                                            color: Colors.amberAccent,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (isCustom)
                                      Positioned(
                                        top: 2,
                                        right: 2,
                                        child: IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.redAccent,
                                            size: 18,
                                          ),
                                          onPressed: () {
                                            setStateSheet(() {
                                              _bgLibrary.removeAt(index);
                                            });
                                            setState(() {});
                                            _persistAndSync();
                                          },
                                        ),
                                      ),
                                    Positioned(
                                      bottom: 8,
                                      left: 8,
                                      right: 8,
                                      child: Text(
                                        bgItem.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// Hộp thoại thêm hình nền mới vào kho thư viện từ thiết bị
  void _showAddBackgroundToLibraryDialog(VoidCallback onAdded) {
    String name = '';
    String category = 'Tùy chọn';
    String pickedImagePath = '';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                'Thêm hình nền vào kho',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      autofocus: true,
                      onChanged: (val) => name = val,
                      decoration: InputDecoration(
                        labelText: 'Tên hình nền',
                        hintText: 'VD: Rồng lửa, Đêm sao...',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (pickedImagePath.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 110,
                          width: double.infinity,
                          color: const Color(0xFF1E1E2C),
                          child: Image(
                            image: getCustomImageProvider(pickedImagePath),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Center(
                                  child: Icon(
                                    Icons.broken_image,
                                    color: Colors.white54,
                                  ),
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.deepPurple,
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(
                        pickedImagePath.isEmpty
                            ? Icons.add_photo_alternate
                            : Icons.cached,
                        size: 20,
                      ),
                      label: Text(
                        pickedImagePath.isEmpty
                            ? 'Chọn ảnh từ thiết bị'
                            : 'Chọn ảnh khác từ máy',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        _pickImageFromDevice((pickedPath) {
                          setStateDialog(() {
                            pickedImagePath = pickedPath;
                          });
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (name.trim().isNotEmpty &&
                        pickedImagePath.trim().isNotEmpty) {
                      final newItem = BackgroundItem(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        title: name.trim(),
                        urlOrPath: pickedImagePath.trim(),
                        category: category,
                      );
                      _bgLibrary.add(newItem);
                      _persistAndSync();
                      onAdded();
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: const Text('Lưu vào kho'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Hộp thoại Thêm mới / Chỉnh sửa Task hoặc Habit
  void _showItemDialog({Task? taskToEdit, Habit? habitToEdit}) {
    final bool isEditing = taskToEdit != null || habitToEdit != null;
    String title = taskToEdit?.title ?? habitToEdit?.title ?? '';
    bool isHabit = habitToEdit != null;
    DateTime tempDate = taskToEdit?.dueDate ?? _selectedDate;
    String themeType =
        taskToEdit?.themeType ?? habitToEdit?.themeType ?? 'default';
    String customBg =
        taskToEdit?.customBackgroundImage ??
        habitToEdit?.customBackgroundImage ??
        '';

    TimeOfDay? tempTime;
    String? initialTimeStr =
        taskToEdit?.reminderTime ?? habitToEdit?.reminderTime;
    if (initialTimeStr != null) {
      final parts = initialTimeStr.split(':');
      if (parts.length == 2) {
        tempTime = TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      }
    }

    Tag? selectedTag = (taskToEdit?.tags.isNotEmpty == true)
        ? taskToEdit!.tags.first
        : ((habitToEdit?.tags.isNotEmpty == true)
              ? habitToEdit!.tags.first
              : (_availableTags.isNotEmpty ? _availableTags.first : null));

    final titleController = TextEditingController(text: title);
    // Lấy Overlay từ context của State. Bên trong dialog, biến `context` bị
    // StatefulBuilder che mất và sẽ không dùng được nữa sau khi dialog đóng.
    final overlay = Overlay.maybeOf(context);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Text(
                isEditing ? 'Chỉnh Sửa Hoạt Động' : 'Thêm Hoạt Động',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleController,
                      onChanged: (val) => title = val,
                      decoration: InputDecoration(
                        hintText: 'Tên nhiệm vụ (VD: Săn rồng, Đá bóng...)',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // --- CHỌN CHỦ ĐỀ HỆ THỐNG ---
                    const Text(
                      'Chủ Đề Hệ Thống:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: themeType,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'default',
                          child: Text(
                            '📌 Mặc định',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'game',
                          child: Text(
                            '🐉 Game (Call of Dragons / Behemoth)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'sport',
                          child: Text(
                            '⚽ Thể thao (Cầu lông, Bóng đá)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      onChanged: (val) =>
                          setStateDialog(() => themeType = val ?? 'default'),
                    ),
                    const SizedBox(height: 16),

                    // --- CHỌN NHÃN DÁN (TAGS) & TẠO NHÃN MỚI ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Nhãn Dán (Tag):',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.add_circle_outline, size: 15),
                          label: const Text(
                            'Tạo nhãn',
                            style: TextStyle(fontSize: 12),
                          ),
                          onPressed: () {
                            _showCreateTagDialog((newTag) {
                              setStateDialog(() {
                                selectedTag = newTag;
                              });
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _availableTags.map((tag) {
                        final isSelected = selectedTag?.id == tag.id;
                        return ChoiceChip(
                          label: Text(
                            tag.name,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.black87,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 12,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: Color(tag.colorValue),
                          backgroundColor: Color(tag.colorValue)
                              .withValues(alpha: 0.15),
                          checkmarkColor: Colors.white,
                          onSelected: (selected) {
                            setStateDialog(() {
                              selectedTag = selected ? tag : null;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // --- CHỌN ẢNH NỀN TÙY CHỈNH (CHỈ LẤY TỪ MÁY / THƯ VIỆN, BỎ URL TEXTFIELD) ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Hình Nền Card (Background):',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (customBg.trim().isNotEmpty)
                          TextButton(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: Colors.redAccent,
                            ),
                            onPressed: () {
                              setStateDialog(() {
                                customBg = '';
                              });
                            },
                            child: const Text(
                              'Xóa nền',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Preview ảnh nền nhỏ
                    if (customBg.trim().isNotEmpty) ...[
                      Container(
                        height: 64,
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: const Color(0xFF1E1E2C),
                          image: DecorationImage(
                            image: getCustomImageProvider(customBg),
                            fit: BoxFit.cover,
                            colorFilter: ColorFilter.mode(
                              Colors.black.withValues(alpha: 0.55),
                              BlendMode.darken,
                            ),
                            // ignore: unnecessary_underscores
                            onError: (_, __) {},
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'Xem trước: Lớp phủ mờ bảo toàn chữ ✨',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],

                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple.shade50,
                              foregroundColor: Colors.deepPurple,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 4,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: Colors.deepPurple.shade200,
                                ),
                              ),
                            ),
                            icon: const Icon(
                              Icons.add_photo_alternate,
                              size: 16,
                            ),
                            label: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Lấy ảnh từ máy',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            onPressed: () {
                              _pickImageFromDevice((pickedPath) {
                                setStateDialog(() {
                                  customBg = pickedPath;
                                });
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 4,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(
                              Icons.photo_library_outlined,
                              size: 16,
                            ),
                            label: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Kho thư viện',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            onPressed: () {
                              _showBackgroundLibrarySheet((selectedUrl) {
                                setStateDialog(() {
                                  customBg = selectedUrl;
                                });
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (!isEditing) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isHabit ? '🔥 Thói quen' : '📋 Công việc',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Switch.adaptive(
                            value: isHabit,
                            activeThumbColor: Colors.deepOrange,
                            onChanged: (val) =>
                                setStateDialog(() => isHabit = val),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    // --- CHỌN NGÀY VÀ HẸN GIỜ THỰC HIỆN CÔNG VIỆC ---
                    const Text(
                      'Thời Gian Thực Hiện:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // CHỌN NGÀY THỰC HIỆN
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final pickedDate = await showDatePicker(
                                context: context,
                                initialDate: tempDate,
                                firstDate: DateTime(2025),
                                lastDate: DateTime(2030),
                              );
                              if (pickedDate != null) {
                                setStateDialog(() => tempDate = pickedDate);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.calendar_today,
                                    size: 15,
                                    color: Colors.deepPurple,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text(
                                          'Ngày thực hiện',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: Colors.grey,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            DateFormat('dd/MM/yyyy')
                                                .format(tempDate),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // HẸN GIỜ NHẮC NHỞ
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final pickedTime = await showTimePicker(
                                context: context,
                                initialTime: tempTime ?? TimeOfDay.now(),
                              );
                              if (pickedTime != null) {
                                setStateDialog(() => tempTime = pickedTime);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.alarm,
                                    size: 15,
                                    color: Colors.deepOrange,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text(
                                          'Giờ nhắc nhở',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: Colors.grey,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            tempTime == null
                                                ? 'Chưa đặt'
                                                : tempTime!.format(context),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final currentTitle = titleController.text.trim().isNotEmpty
                        ? titleController.text.trim()
                        : title.trim();
                    if (currentTitle.isNotEmpty) {
                      final timeStr = tempTime != null
                          ? '${tempTime!.hour.toString().padLeft(2, '0')}:${tempTime!.minute.toString().padLeft(2, '0')}'
                          : null;
                      final List<Tag> tagList = selectedTag != null
                          ? [selectedTag!]
                          : <Tag>[];
                      final finalCustomBg = customBg.trim().isNotEmpty
                          ? customBg.trim()
                          : null;

                      setState(() {
                        if (isEditing) {
                          if (taskToEdit != null) {
                            taskToEdit.title = currentTitle;
                            taskToEdit.dueDate = tempDate;
                            taskToEdit.reminderTime = timeStr;
                            taskToEdit.tags = tagList;
                            taskToEdit.themeType = themeType;
                            taskToEdit.customBackgroundImage = finalCustomBg;
                          } else if (habitToEdit != null) {
                            habitToEdit.title = currentTitle;
                            habitToEdit.reminderTime = timeStr;
                            habitToEdit.tags = tagList;
                            habitToEdit.themeType = themeType;
                            habitToEdit.customBackgroundImage = finalCustomBg;
                          }
                        } else {
                          if (isHabit) {
                            _habits.add(
                              Habit(
                                id: DateTime.now().millisecondsSinceEpoch
                                    .toString(),
                                title: currentTitle,
                                reminderTime: timeStr,
                                tags: tagList,
                                themeType: themeType,
                                customBackgroundImage: finalCustomBg,
                              ),
                            );
                          } else {
                            _tasks.add(
                              Task(
                                id: DateTime.now().millisecondsSinceEpoch
                                    .toString(),
                                title: currentTitle,
                                dueDate: tempDate,
                                reminderTime: timeStr,
                                tags: tagList,
                                themeType: themeType,
                                customBackgroundImage: finalCustomBg,
                              ),
                            );
                            // Tự động chuyển ngày hiển thị sang ngày vừa đặt để người dùng thấy ngay
                            _selectedDate = tempDate;
                          }
                        }
                      });
                      Navigator.pop(dialogContext);

                      final bool saved = await _saveDataToPrefs();
                      AppToast.showIn(
                        overlay,
                        message: saved
                            ? (isEditing
                                  ? 'Đã lưu thay đổi'
                                  : 'Đã tạo công việc mới')
                            : 'Lưu dữ liệu thất bại, vui lòng thử lại.',
                        success: saved,
                      );
                      if (saved) await _syncExternal();
                    }
                  },
                  child: Text(isEditing ? 'Lưu' : 'Tạo mới'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Card hiển thị linh hoạt: Ưu tiên Custom Bg -> Theme Type -> Mặc định
  /// Menu Sửa / Xoá cho một thẻ.
  ///
  /// Trước đây xoá bằng cách kéo thẻ sang trái (Dismissible), nhưng giờ cử chỉ
  /// kéo ngang đã dành cho việc chuyển tab, nên chuyển sang menu này.
  void _showItemActions({
    required String title,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(
                  Icons.edit_outlined,
                  color: Colors.deepPurple,
                ),
                title: const Text('Sửa hoạt động'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onEdit();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Xoá',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onDelete();
                  AppToast.showIn(
                    Overlay.maybeOf(context),
                    message: 'Đã xoá "$title"',
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget buildThemedCard({
    required String title,
    required String themeType,
    String? customBg,
    required bool isCompleted,
    required VoidCallback onTap,
    required VoidCallback onUndo,
    required VoidCallback onEdit,
    required String? reminderTime,
    required List<Tag> tags,
    required String subtitleInfo,
    // Tab "Đã hoàn thành" mới có nút khôi phục. Truyền vào thay vì đọc
    // _tabIndex, vì cả 2 tab được dựng cùng lúc trong PageView.
    required bool showUndo,
    required VoidCallback onDelete,
  }) {
    final bool hasCustomBg = customBg != null && customBg.trim().isNotEmpty;
    final bool isThemed = themeType != 'default';
    final bool isDarkCard = hasCustomBg || isThemed;

    Gradient cardGradient;
    Color accentColor;
    String badgeTitle;

    if (themeType == 'game') {
      cardGradient = const LinearGradient(
        colors: [Color(0xFF2C1B4D), Color(0xFF512DA8), Color(0xFFB71C1C)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
      accentColor = Colors.amberAccent;
      badgeTitle = '🐉 CALL OF DRAGONS';
    } else if (themeType == 'sport') {
      cardGradient = const LinearGradient(
        colors: [Color(0xFF004D40), Color(0xFF00796B), Color(0xFF388E3C)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
      accentColor = Colors.lightGreenAccent;
      badgeTitle = '⚽ THỂ THAO';
    } else {
      cardGradient = LinearGradient(
        colors: [
          Colors.deepPurple.shade50,
          Colors.deepPurple.shade100.withValues(alpha: 0.5),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
      accentColor = hasCustomBg ? Colors.amberAccent : Colors.deepPurple;
      badgeTitle = hasCustomBg ? '✨ TÙY CHỈNH' : '📌 NHIỆM VỤ';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: hasCustomBg
            ? const Color(0xFF1E1E2C)
            : (isThemed
                  ? null
                  : (isCompleted
                        ? Colors.deepPurple.withValues(alpha: 0.08)
                        : Colors.white)),
        gradient: hasCustomBg ? null : (isThemed ? cardGradient : null),
        image: hasCustomBg
            ? DecorationImage(
                image: getCustomImageProvider(customBg.trim()),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.55),
                  BlendMode.darken,
                ),
                // ignore: unnecessary_underscores
                onError: (_, __) {},
              )
            : null,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCompleted
              ? (isDarkCard
                    ? Colors.amberAccent.withValues(alpha: 0.6)
                    : Colors.deepPurple.shade300)
              : (hasCustomBg
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.transparent),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: () => _showItemActions(
              title: title,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDarkCard
                          ? Colors.black.withValues(alpha: 0.35)
                          : (isCompleted
                                ? Colors.deepPurple
                                : Colors.deepPurple.shade50),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      isCompleted
                          ? Icons.undo
                          : (themeType == 'game'
                                ? Icons.local_fire_department
                                : (themeType == 'sport'
                                      ? Icons.sports_soccer
                                      : (hasCustomBg
                                            ? Icons.auto_awesome
                                            : Icons.task_alt))),
                      color: isDarkCard
                          ? accentColor
                          : (isCompleted ? Colors.white : Colors.deepPurple),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isThemed || hasCustomBg) ...[
                          Text(
                            badgeTitle,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: accentColor,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            // BỎ GẠCH NGANG TÊN THEO YÊU CẦU
                            decoration: TextDecoration.none,
                            color: isDarkCard
                                ? Colors.white
                                : (isCompleted
                                      ? Colors.deepPurple
                                      : Colors.black87),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (reminderTime != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isDarkCard
                                      ? Colors.black.withValues(alpha: 0.4)
                                      : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.alarm,
                                      size: 11,
                                      color: isDarkCard
                                          ? accentColor
                                          : Colors.grey.shade700,
                                    ),
                                    Text(
                                      ' $reminderTime',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isDarkCard
                                            ? accentColor
                                            : Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Text(
                              subtitleInfo,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDarkCard
                                    ? Colors.white70
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (showUndo)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.undo,
                        color: isDarkCard ? Colors.white : Colors.deepPurple,
                        size: 20,
                      ),
                      tooltip: 'Khôi phục lại',
                      onPressed: onUndo,
                    ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.more_vert,
                      color: isDarkCard ? Colors.white70 : Colors.grey.shade600,
                      size: 20,
                    ),
                    tooltip: 'Sửa hoặc xoá',
                    onPressed: () => _showItemActions(
                      title: title,
                      onEdit: onEdit,
                      onDelete: onDelete,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Text(
          widget.title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        actions: [
          // Nút chọn lịch LUÔN hiển thị ở cả 2 tab theo yêu cầu
          IconButton(
            icon: const Icon(Icons.calendar_month, color: Colors.deepPurple),
            tooltip: 'Chọn ngày lịch',
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2025),
                lastDate: DateTime(2030),
              );
              if (picked != null) setState(() => _selectedDate = picked);
            },
          ),
        ],
      ),
      // Header cố định ở trên, hai tab kéo qua kéo lại ở dưới
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              children: [
                _buildDateBanner(),
                const SizedBox(height: 16),
                // Chỉ phần này dựng lại khi kéo, danh sách thẻ không bị đụng
                _buildTabBar(),
                const SizedBox(height: 16),
                _buildTagFilter(),
              ],
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pageController,
              // KHÔNG setState ở đây - xem ghi chú ở _tabIndex
              onPageChanged: (index) => _tabIndex.value = index,
              children: [_buildTabContent(0), _buildTabContent(1)],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showItemDialog(),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text(
          'Thêm mới',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // ===========================================================================
  // CÁC PHẦN CỦA HEADER CỐ ĐỊNH
  // ===========================================================================

  /// Banner ngày tháng, luôn hiển thị ở cả 2 tab.
  Widget _buildDateBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.deepPurple.shade50,
            Colors.deepPurple.shade100.withValues(alpha: 0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.today, color: Colors.deepPurple, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Ngày: ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            onPressed: () => setState(() => _selectedDate = DateTime.now()),
            child: const Text(
              'Hôm nay',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// Thanh chuyển tab. Bấm thì chạy animation sang trang tương ứng, còn kéo
  /// ngang trên nội dung thì PageView tự đổi và onPageChanged cập nhật lại đây.
  /// Vị trí trang hiện tại dưới dạng số thực: 0.0 = Cần làm, 1.0 = Đã hoàn
  /// thành, ở giữa là đang kéo dở.
  double get _pagePosition {
    if (_pageController.hasClients && _pageController.position.haveDimensions) {
      final double? page = _pageController.page;
      if (page != null) return page.clamp(0.0, 1.0);
    }
    return _tabIndex.value.toDouble();
  }

  /// Thanh chuyển tab.
  ///
  /// Chỉ có MỘT ô trắng, trượt liên tục theo đúng vị trí trang. Trước đây mỗi
  /// tab là một AnimatedContainer tự đổi màu, nên lúc chuyển có 220ms cả hai
  /// cùng sáng, và ô trắng thì nhảy chứ không chạy theo ngón tay.
  Widget _buildTabBar() {
    return AnimatedBuilder(
      animation: Listenable.merge([_pageController, _tabIndex]),
      builder: (context, _) {
        final double pos = _pagePosition;
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(16),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double tabWidth = constraints.maxWidth / 2;
              return Stack(
                children: [
                  // Ô trắng trượt theo ngón tay
                  Positioned(
                    left: tabWidth * pos,
                    top: 0,
                    bottom: 0,
                    width: tabWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      _buildTabButton(0, 'Cần làm', 1.0 - pos),
                      _buildTabButton(1, 'Đã hoàn thành', pos),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// [activeness] 0 = không được chọn, 1 = đang được chọn; ở giữa thì màu chữ
  /// chuyển dần theo để khớp với ô trắng đang trượt.
  Widget _buildTabButton(int index, String label, double activeness) {
    final double t = activeness.clamp(0.0, 1.0);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _goToTab(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color.lerp(Colors.grey.shade600, Colors.deepPurple, t),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Thanh lọc theo nhãn dán (Tag filter)
  Widget _buildTagFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          FilterChip(
            label: const Text('Tất cả'),
            selected: _selectedFilterTag == null,
            onSelected: (bool selected) =>
                setState(() => _selectedFilterTag = null),
          ),
          const SizedBox(width: 8),
          ..._availableTags.map((tag) {
            final isSelected = _selectedFilterTag?.id == tag.id;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(tag.name),
                selected: isSelected,
                selectedColor: Color(tag.colorValue).withValues(alpha: 0.3),
                checkmarkColor: Color(tag.colorValue),
                onSelected: (bool selected) =>
                    setState(() => _selectedFilterTag = selected ? tag : null),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ===========================================================================
  // NỘI DUNG CỦA MỖI TAB
  // ===========================================================================

  Widget _buildTabContent(int tabIndex) {
    final bool completedTab = tabIndex == 1;

    final filteredTasks = _tasks.where((task) {
      final matchTag =
          _selectedFilterTag == null ||
          task.tags.any((t) => t.id == _selectedFilterTag!.id);
      final matchDate =
          task.dueDate.year == _selectedDate.year &&
          task.dueDate.month == _selectedDate.month &&
          task.dueDate.day == _selectedDate.day;
      return matchDate &&
          matchTag &&
          (completedTab ? task.isCompleted : !task.isCompleted);
    }).toList();

    if (completedTab) {
      filteredTasks.sort((a, b) => b.dueDate.compareTo(a.dueDate));
    }

    final filteredHabits = _habits.where((habit) {
      final matchTag =
          _selectedFilterTag == null ||
          habit.tags.any((t) => t.id == _selectedFilterTag!.id);
      return matchTag &&
          (completedTab ? habit.isCompletedToday : !habit.isCompletedToday);
    }).toList();

    return ListView(
      // Chừa chỗ dưới cùng để nút "Thêm mới" không che thẻ cuối
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
      children: [
        // --- THÓI QUEN ---
        const Text(
          '🔥 Thói Quen Hàng Ngày',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.deepOrange,
          ),
        ),
        const SizedBox(height: 10),
        if (filteredHabits.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              completedTab
                  ? 'Chưa có thói quen nào hoàn thành.'
                  : 'Không có thói quen nào cần làm.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          )
        else
          ...filteredHabits.map(
            (habit) => buildThemedCard(
              title: habit.title,
              themeType: habit.themeType,
              customBg: habit.customBackgroundImage,
              isCompleted: habit.isCompletedToday,
              reminderTime: habit.reminderTime,
              tags: habit.tags,
              subtitleInfo: 'Chuỗi: ${habit.streak} ngày',
              onTap: () {
                setState(() {
                  habit.isCompletedToday = !habit.isCompletedToday;
                  if (habit.isCompletedToday) {
                    habit.streak++;
                  } else {
                    habit.streak = habit.streak > 0 ? habit.streak - 1 : 0;
                  }
                });
                _persistAndSync();
              },
              onUndo: () {
                setState(() {
                  habit.isCompletedToday = false;
                  habit.streak = habit.streak > 0 ? habit.streak - 1 : 0;
                });
                _persistAndSync();
              },
              onEdit: () => _showItemDialog(habitToEdit: habit),
              showUndo: completedTab,
              onDelete: () {
                setState(() => _habits.remove(habit));
                _persistAndSync();
              },
            ),
          ),

        const SizedBox(height: 16),

        // --- CÔNG VIỆC ---
        Text(
          completedTab
              ? '✅ Công Việc Đã Hoàn Thành (${filteredTasks.length})'
              : '📋 Công Việc Cần Làm (${filteredTasks.length})',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
          ),
        ),
        const SizedBox(height: 10),
        if (filteredTasks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                completedTab
                    ? 'Chưa có công việc nào hoàn thành trong ngày này.'
                    : 'Không có công việc nào cần làm trong ngày này.',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          )
        else
          ...filteredTasks.map(
            (task) => buildThemedCard(
              title: task.title,
              themeType: task.themeType,
              customBg: task.customBackgroundImage,
              isCompleted: task.isCompleted,
              reminderTime: task.reminderTime,
              tags: task.tags,
              subtitleInfo: completedTab
                  ? '📅 ${DateFormat('dd/MM/yyyy').format(task.dueDate)}'
                  : 'Hạn: ${DateFormat('dd/MM/yyyy').format(task.dueDate)}',
              onTap: () {
                setState(() => task.isCompleted = !task.isCompleted);
                _persistAndSync();
              },
              onUndo: () {
                setState(() => task.isCompleted = false);
                _persistAndSync();
              },
              onEdit: () => _showItemDialog(taskToEdit: task),
              showUndo: completedTab,
              onDelete: () {
                setState(() => _tasks.remove(task));
                _persistAndSync();
              },
            ),
          ),
      ],
    );
  }
}
