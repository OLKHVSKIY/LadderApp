import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/drift.dart' as dr;
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../services/biometric_service.dart';


import '../theme/theme_controller.dart';
import '../theme/app_colors.dart';
import '../l10n/locale_controller.dart';
import '../l10n/app_translations.dart';
import '../widgets/main_header.dart';
import '../widgets/swipeable_page_route.dart';
import '../widgets/sidebar.dart';
import 'tasks_page.dart';
import 'login_page.dart';
import 'subscription_page.dart';
import 'privacy_page.dart';
import '../data/database_instance.dart';
import '../data/user_session.dart';
import '../data/app_database.dart';
import '../data/repositories/auth_repository.dart';
import '../widgets/custom_snackbar.dart';
import '../widgets/name_setup_dialog.dart';
import '../services/google_calendar_service.dart';
import '../services/apple_calendar_service.dart';

class SettingsPage extends StatefulWidget {
  final Widget Function() buildReturnPage;

  const SettingsPage({
    super.key,
    Widget Function()? buildReturnPage,
  }) : buildReturnPage = buildReturnPage ?? _defaultReturn;

  static Widget _defaultReturn() => const TasksPage();

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with SingleTickerProviderStateMixin {
  bool _isSidebarOpen = false;
  late AnimationController _starsController;
  final TextEditingController _emailController = TextEditingController();
  String? _avatarPath;
  String? _userName;
  DateTime? _userCreatedAt;
  bool _isAvatarHovered = false;
  bool _importingCalendar = false;
  bool _importingAppleCalendar = false;
  int _googleNewEvents = 0; // не импортированных событий Google (для бейджа)
  int _appleNewEvents = 0; // не импортированных событий Apple (для бейджа)
  bool _notificationsEnabled = true;
  bool _emailNotificationsEnabled = true;
  bool _faceIdEnabled = false; // блокировка приложения по Face ID / Touch ID
  OverlayEntry? _selectMenuOverlay;
  final GlobalKey _themeAnchorKey = GlobalKey();
  final GlobalKey _languageAnchorKey = GlobalKey();

  void _removeSelectMenu() {
    _selectMenuOverlay?.remove();
    _selectMenuOverlay = null;
  }

  // Открывает стеклянное выпадающее меню (liquid glass), привязанное к контролу выбора.
  void _showSelectMenu({
    required GlobalKey anchorKey,
    required String title,
    required List<String> options,
    required String currentValue,
    required ValueChanged<String> onChanged,
  }) {
    _removeSelectMenu();
    final overlay = Overlay.of(context);
    final renderBox = anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final anchorPosition = renderBox.localToGlobal(Offset.zero);
    final anchorSize = renderBox.size;
    const menuWidth = 200.0;
    final screenWidth = MediaQuery.of(context).size.width;
    // Правый край меню совмещаем с правым краем контрола, не вылезая за экран.
    double left = anchorPosition.dx + anchorSize.width - menuWidth;
    if (left < 12) left = 12;
    if (left + menuWidth > screenWidth - 12) left = screenWidth - 12 - menuWidth;
    final top = anchorPosition.dy + anchorSize.height + 6;

    _selectMenuOverlay = OverlayEntry(
      builder: (context) => _GlassSelectMenu(
        left: left,
        top: top,
        width: menuWidth,
        title: title,
        options: options,
        currentValue: currentValue,
        onSelected: (v) {
          _removeSelectMenu();
          onChanged(v);
        },
        onClose: _removeSelectMenu,
      ),
    );
    overlay.insert(_selectMenuOverlay!);
  }

  void _toggleSidebar() {
    // Скрываем клавиатуру при открытии/закрытии сайдбара
    FocusScope.of(context).unfocus();
    setState(() {
      _isSidebarOpen = !_isSidebarOpen;
    });
  }

  void _goBack() {
    // Используем pop() вместо pushReplacement для правильной работы свайпа
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, animation, _) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
            child: widget.buildReturnPage(),
          ),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _starsController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
    _loadUserProfile();
    _loadFaceIdSetting();
    // Считаем не импортированные события календарей для индикаторов.
    _refreshCalendarBadges();
  }

  Future<void> _loadFaceIdSetting() async {
    final enabled = await BiometricService.instance.isEnabled();
    if (!mounted) return;
    setState(() => _faceIdEnabled = enabled);
  }

  @override
  void dispose() {
    // Снимаем оверлей напрямую — setState в dispose недопустим.
    _selectMenuOverlay?.remove();
    _selectMenuOverlay = null;
    _starsController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;
    final users =
        await (appDatabase.select(appDatabase.users)..where((u) => u.id.equals(userId))).get();
    if (users.isNotEmpty) {
      final user = users.first;
      _userName = user.name;
      _userCreatedAt = user.createdAt;
      _emailController.text = user.email;
      
      // Проверяем, что файл аватара существует
      // ВАЖНО: На iOS путь к Documents может изменяться, поэтому всегда извлекаем имя файла
      // и пересоздаем полный путь используя актуальный путь к Documents
      String? validAvatarPath = user.avatarUrl;
      if (validAvatarPath != null && validAvatarPath.isNotEmpty) {
        // Извлекаем имя файла из пути (работает и с полными путями, и с именами файлов)
        final fileName = path.basename(validAvatarPath);
        
        // Всегда пересоздаем полный путь используя актуальный путь к Documents
        final appDir = await getApplicationDocumentsDirectory();
        final avatarDir = Directory(path.join(appDir.path, 'avatars'));
        final fullPath = path.join(avatarDir.path, fileName);
        
        debugPrint('Проверяем аватар по пути: $fullPath (из БД было: $validAvatarPath)');
        
        final avatarFile = File(fullPath);
        if (await avatarFile.exists()) {
          validAvatarPath = fullPath;
          // Если в БД был сохранен полный путь, обновляем на имя файла для будущего
          if (path.isAbsolute(user.avatarUrl!) && user.avatarUrl!.contains('Documents')) {
            await (appDatabase.update(appDatabase.users)..where((u) => u.id.equals(userId))).write(
              UsersCompanion(
                avatarUrl: dr.Value(fileName), // Сохраняем только имя файла
                updatedAt: dr.Value(DateTime.now()),
              ),
            );
            debugPrint('Обновлен путь в БД: сохранено только имя файла $fileName');
          }
        } else {
          debugPrint('Файл аватара не существует: $fullPath, очищаем путь в БД');
          // Очищаем несуществующий путь из БД
          await (appDatabase.update(appDatabase.users)..where((u) => u.id.equals(userId))).write(
            UsersCompanion(
              avatarUrl: dr.Value(null),
              updatedAt: dr.Value(DateTime.now()),
            ),
          );
          validAvatarPath = null;
        }
      }
      
      setState(() {
        _avatarPath = validAvatarPath;
      });
    } else {
      _emailController.text = UserSession.currentEmail ?? '';
    }
  }

  Future<void> _editName() async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;
    final name = await showNameDialog(
      context,
      initialName: _userName,
      dismissible: true,
    );
    if (!mounted || name == null || name.isEmpty) return;
    await (appDatabase.update(appDatabase.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        name: dr.Value(name),
        updatedAt: dr.Value(DateTime.now()),
      ),
    );
    UserSession.currentName = name;
    if (!mounted) return;
    setState(() => _userName = name);
  }

  Future<void> _pickAndCropImage() async {
    try {
      String? filePath;
      
      // ВСЕГДА используем file_picker для веба и десктопных платформ (macOS, Windows, Linux)
      // ТОЛЬКО для настоящих Android/iOS устройств используем image_picker
      bool useImagePicker = false;
      
      if (!kIsWeb) {
        try {
          // ВАЖНО: Проверяем macOS ПЕРВЫМ, так как на macOS Platform.isIOS может возвращать true!
          final isMacOS = Platform.isMacOS;
          final isWindows = Platform.isWindows;
          final isLinux = Platform.isLinux;
          final isAndroid = Platform.isAndroid;
          final isIOS = Platform.isIOS;
          
          // КРИТИЧНО: На macOS Platform.isMacOS может быть false, а Platform.isIOS - true!
          // Поэтому используем image_picker ТОЛЬКО для Android
          // Для всех остальных (macOS, Windows, Linux, iOS) используем file_picker
          useImagePicker = isAndroid && !isMacOS && !isWindows && !isLinux;
          
          debugPrint('Платформа: isMacOS=$isMacOS, isWindows=$isWindows, isLinux=$isLinux, isIOS=$isIOS, isAndroid=$isAndroid, useImagePicker=$useImagePicker');
        } catch (e) {
          debugPrint('Ошибка определения платформы: $e, используем file_picker');
          useImagePicker = false;
        }
      }
      
      if (useImagePicker) {
        // ТОЛЬКО для настоящих iOS/Android устройств используем image_picker
        debugPrint('Используем image_picker для мобильного устройства');
        try {
          final imagePicker = ImagePicker();
          final pickedFile = await imagePicker.pickImage(
            source: ImageSource.gallery,
          );
          if (pickedFile != null) {
            filePath = pickedFile.path;
          }
        } catch (e) {
          debugPrint('Ошибка image_picker: $e');
          if (mounted) {
            CustomSnackBar.show(context, tr('Не удалось открыть галерею'));
          }
          return;
        }
      } else {
        // Для веба, macOS, Windows, Linux используем file_picker
        debugPrint('Используем file_picker');
        
        // Пробуем использовать file_picker с обработкой ошибок
        FilePickerResult? result;
        try {
          result = await FilePicker.platform.pickFiles(
            type: FileType.image,
            allowMultiple: false,
          );
        } catch (e) {
          debugPrint('Ошибка file_picker при вызове: $e');
          
          // Если file_picker не работает, пробуем альтернативный способ
          if (mounted) {
            final useAlternative = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(tr('Не удалось открыть файловый диалог')),
                content: Text(tr('Пожалуйста, перезапустите приложение полностью (не hot reload).')),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(tr('Отмена')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(tr('Попробовать еще раз')),
                  ),
                ],
              ),
            );
            
            if (useAlternative == true) {
              // Повторная попытка
              try {
                result = await FilePicker.platform.pickFiles(
                  type: FileType.image,
                  allowMultiple: false,
                );
              } catch (e2) {
                debugPrint('Ошибка file_picker при повторной попытке: $e2');
                if (mounted) {
                  CustomSnackBar.show(context, tr('Перезапустите приложение полностью'));
                }
                return;
              }
            } else {
              return;
            }
          } else {
            return;
          }
        }
        
        if (result != null && result.files.isNotEmpty) {
          try {
            if (kIsWeb) {
              // Для веба используем bytes
              final bytes = result.files.single.bytes;
              if (bytes != null) {
                final tempDir = await getTemporaryDirectory();
                final tempFile = File(path.join(tempDir.path, 'temp_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg'));
                await tempFile.writeAsBytes(bytes);
                filePath = tempFile.path;
              }
            } else {
              // Для десктопных платформ используем path
              filePath = result.files.single.path;
              if (filePath == null || filePath.isEmpty) {
                debugPrint('Путь к файлу пустой, пробуем имя файла');
                filePath = result.files.single.name;
              }
            }
          } catch (e) {
            debugPrint('Ошибка при обработке выбранного файла: $e');
            if (mounted) {
              CustomSnackBar.show(context, tr('Ошибка обработки файла'));
            }
            return;
          }
        }
      }

      if (filePath == null || filePath.isEmpty) {
        // Пользователь отменил выбор файла - это нормально, просто выходим
        debugPrint('Файл не выбран, выход');
        return;
      }
      
      debugPrint('Выбран файл: $filePath');
      
      // Проверяем, что файл существует
      final sourceFile = File(filePath);
      if (!await sourceFile.exists()) {
        debugPrint('Файл не существует: $filePath');
        if (mounted) {
          CustomSnackBar.show(context, tr('Файл не найден'));
        }
        return;
      }
      
      debugPrint('Файл существует, размер: ${await sourceFile.length()} байт');
      
      // На iOS файлы из picked_images могут быть недоступны для ImageCropper
      // Копируем файл во временную директорию для обрезки
      final tempDir = await getTemporaryDirectory();
      final tempFileName = 'temp_avatar_${DateTime.now().millisecondsSinceEpoch}${path.extension(filePath)}';
      final tempFile = File(path.join(tempDir.path, tempFileName));
      
      try {
        await sourceFile.copy(tempFile.path);
        debugPrint('Файл скопирован во временную директорию: ${tempFile.path}');
      } catch (e) {
        debugPrint('Ошибка копирования файла: $e');
        if (mounted) {
          CustomSnackBar.show(context, tr('Ошибка обработки файла'));
        }
        return;
      }

      // Обрезаем изображение
      CroppedFile? croppedFile;
      try {
        debugPrint('Начинаем обрезку изображения...');
        croppedFile = await ImageCropper().cropImage(
          sourcePath: tempFile.path,
          aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: tr('Обрезка аватара'),
              toolbarColor: Colors.black,
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: true,
            ),
            IOSUiSettings(
              title: tr('Обрезка аватара'),
              aspectRatioLockEnabled: true,
              resetAspectRatioEnabled: false,
            ),
          ],
        );
        debugPrint('Обрезка завершена: ${croppedFile?.path}');
        
        // Удаляем временный файл после обрезки
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
            debugPrint('Временный файл удален');
          }
        } catch (e) {
          debugPrint('Ошибка удаления временного файла: $e');
        }
      } catch (e) {
        debugPrint('Ошибка при обрезке изображения: $e');
        // Удаляем временный файл при ошибке
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {}
        if (mounted) {
          CustomSnackBar.show(context, tr('Ошибка обрезки изображения'));
        }
        return;
      }

      if (croppedFile == null) {
        debugPrint('Обрезка отменена пользователем');
        return;
      }

      // Сохраняем обрезанное изображение в директорию приложения
      String? finalPath;
      
      if (kIsWeb) {
        // Для веба копируем из временного файла
        final appDir = await getApplicationDocumentsDirectory();
        final userId = UserSession.currentUserId;
        final avatarDir = Directory(path.join(appDir.path, 'avatars'));
        if (!await avatarDir.exists()) {
          await avatarDir.create(recursive: true);
        }
        
        final fileName = 'avatar_$userId.jpg';
        final savedFile = File(path.join(avatarDir.path, fileName));
        final croppedBytes = await croppedFile.readAsBytes();
        await savedFile.writeAsBytes(croppedBytes);
        finalPath = savedFile.path;
      } else {
        // Для десктопных и мобильных платформ
        final appDir = await getApplicationDocumentsDirectory();
        final userId = UserSession.currentUserId;
        final avatarDir = Directory(path.join(appDir.path, 'avatars'));
        if (!await avatarDir.exists()) {
          await avatarDir.create(recursive: true);
        }
        
        final fileName = 'avatar_$userId.jpg';
        final savedFile = File(path.join(avatarDir.path, fileName));
        
        // Читаем байты из обрезанного файла и записываем в новый файл
        try {
          debugPrint('Читаем байты из обрезанного файла: ${croppedFile.path}');
          final croppedBytes = await croppedFile.readAsBytes();
          debugPrint('Прочитано ${croppedBytes.length} байт');
          
          debugPrint('Записываем в файл: ${savedFile.path}');
          await savedFile.writeAsBytes(croppedBytes, flush: true);
          debugPrint('Файл записан');
          
          // Даем системе время на запись файла на диск
          await Future.delayed(const Duration(milliseconds: 100));
          
          // Проверяем, что файл действительно сохранен, используя абсолютный путь
          final absolutePath = savedFile.absolute.path;
          final checkFile = File(absolutePath);
          
          if (await checkFile.exists()) {
            final savedSize = await checkFile.length();
            debugPrint('Файл существует по абсолютному пути: $absolutePath, размер: $savedSize байт');
            // Используем абсолютный путь для сохранения
            finalPath = absolutePath;
          } else {
            debugPrint('ОШИБКА: Файл не существует после записи!');
            debugPrint('Проверяемый путь: $absolutePath');
            debugPrint('Проверяем исходный путь: ${savedFile.path}');
            // Пробуем проверить исходный путь
            if (await savedFile.exists()) {
              debugPrint('Файл существует по исходному пути: ${savedFile.path}');
              finalPath = savedFile.path;
            } else {
              debugPrint('ОШИБКА: Файл не существует ни по одному пути!');
              if (mounted) {
                CustomSnackBar.show(context, tr('Ошибка сохранения аватара'));
              }
              return;
            }
          }
        } catch (e) {
          debugPrint('Ошибка при сохранении через writeAsBytes: $e');
          if (mounted) {
            CustomSnackBar.show(context, tr('Ошибка сохранения аватара: {0}', [e]));
          }
          return;
        }
      }

      // Удаляем старый аватар, если он есть
      if (_avatarPath != null && _avatarPath!.isNotEmpty) {
        try {
          final oldFile = File(_avatarPath!);
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
        } catch (e) {
          debugPrint('Ошибка удаления старого аватара: $e');
        }
      }

      if (finalPath.isNotEmpty) {
        debugPrint('Сохраняем аватар по пути: $finalPath');
        
        // Обновляем состояние сразу, так как файл уже сохранен и проверен выше
        setState(() {
          _avatarPath = finalPath;
        });
        
        debugPrint('Аватар установлен в состояние: $_avatarPath');
        
        // ВАЖНО: Сохраняем только имя файла в БД (не полный путь)
        // Это позволит пересоздавать путь при каждом запуске приложения
        final userId = UserSession.currentUserId;
        if (userId != null) {
          try {
            // Сохраняем только имя файла, чтобы путь можно было пересоздать при следующем запуске
            final fileName = path.basename(finalPath);
            await (appDatabase.update(appDatabase.users)..where((u) => u.id.equals(userId))).write(
              UsersCompanion(
                avatarUrl: dr.Value(fileName), // Сохраняем только имя файла
                updatedAt: dr.Value(DateTime.now()),
              ),
            );
            debugPrint('Имя файла аватара сохранено в БД: $fileName (полный путь: $finalPath)');
          } catch (e) {
            debugPrint('Ошибка сохранения имени файла аватара в БД: $e');
            if (mounted) {
              CustomSnackBar.show(context, tr('Аватар обновлен, но не сохранен в профиле'));
            }
            return;
          }
        }
        
        if (mounted) {
          CustomSnackBar.show(context, tr('Аватар обновлен'));
        }
      } else {
        debugPrint('ОШИБКА: finalPath равен null или пустой!');
        if (mounted) {
          CustomSnackBar.show(context, tr('Не удалось сохранить аватар'));
        }
      }
    } catch (e) {
      debugPrint('Ошибка выбора/обрезки изображения: $e');
      if (mounted) {
        CustomSnackBar.show(context, tr('Не удалось обновить аватар'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
            // Контент уходит под прозрачный хедер.
            Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top - 10,
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  15,
                  60 + 20,
                  15,
                  40,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                          _buildProfile(),
                          const SizedBox(height: 32),
                          _buildSubscription(),
                          const SizedBox(height: 32),
                          _buildAppearance(),
                          const SizedBox(height: 32),
                          _buildIntegrations(),
                          const SizedBox(height: 32),
                          _buildNotifications(),
                          const SizedBox(height: 32),
                          _buildSecurity(),
                          const SizedBox(height: 32),
                          _buildSupport(),
                          const SizedBox(height: 32),
                          _buildAbout(),
                          if (_userCreatedAt != null) ...[
                            const SizedBox(height: 24),
                            Center(
                              child: Text(
                                _memberSince(),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.of(context).textTertiary,
                                ),
                              ),
                            ),
                          ],
                  ],
                ),
              ),
            ),
            // Сплошной хедер с лёгкой тенью снизу.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.of(context).background,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top - 10,
                  ),
                  child: Stack(
                    children: [
                      MainHeader(
                        title: tr('Настройки'),
                        onMenuTap: _toggleSidebar,
                        onSearchTap: null,
                        onSettingsTap: null,
                        hideSearchAndSettings: true,
                        showBackButton: true,
                        onBack: _goBack,
                        onGreetingToggle: null,
                        backgroundColor: Colors.transparent,
                      ),
                      // Кнопка выхода справа в хедере.
                      Positioned(
                        right: 14,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: GestureDetector(
                            onTap: _logout,
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              width: 44,
                              height: 44,
                              color: Colors.transparent,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.logout,
                                size: 24,
                                color: AppColors.of(context).isDark
                                    ? Colors.white
                                    : Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Sidebar(
              isOpen: _isSidebarOpen,
              onClose: _toggleSidebar,
              onTasksTap: () {
                _goBack();
              },
              onSettingsTap: () {
                // Уже на настройках — просто закрываем сайдбар
                _toggleSidebar();
              },
            ),
          ],
        ),
      );
  }

  Widget _buildProfile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(''),
        Container(
          decoration: BoxDecoration(
            // Блок профиля остаётся белым (не сероватым).
            color: AppColors.of(context).surface,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: AppColors.of(context).border),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.only(left: 25, right: 25, top: 10, bottom: 20),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 20, bottom: 15),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Аватарка с возможностью изменения
                          GestureDetector(
                            onTapDown: (_) {
                              setState(() {
                                _isAvatarHovered = true;
                              });
                            },
                            onTapUp: (_) {
                              setState(() {
                                _isAvatarHovered = false;
                              });
                              _pickAndCropImage();
                            },
                            onTapCancel: () {
                              setState(() {
                                _isAvatarHovered = false;
                              });
                            },
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Builder(
                                  builder: (context) {
                                    final hasAvatar = _avatarPath != null && 
                                        _avatarPath!.isNotEmpty &&
                                        File(_avatarPath!).existsSync();
                                    
                                    return Container(
                                      width: 140,
                                      height: 140,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.of(context).surfaceVariant,
                                        image: hasAvatar
                                            ? DecorationImage(
                                                image: FileImage(File(_avatarPath!)),
                                                fit: BoxFit.cover,
                                              )
                                            : null,
                                      ),
                                      alignment: Alignment.center,
                                      child: !hasAvatar
                                          ? const Text(
                                              '👤',
                                              style: TextStyle(fontSize: 42),
                                            )
                                          : null,
                                    );
                                  },
                                ),
                                // Затемнение и иконка при нажатии
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 140,
                                  height: 140,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black.withValues(alpha: _isAvatarHovered ? 0.4 : 0.0),
                                  ),
                                  child: _isAvatarHovered
                                      ? const Icon(
                                          Icons.camera_alt,
                                          color: Colors.white,
                                          size: 32,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          // Имя пользователя + иконка смены имени
                          GestureDetector(
                            onTap: _editName,
                            behavior: HitTestBehavior.opaque,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Невидимый отступ слева, равный карандашу+зазору
                                // справа — чтобы имя было по центру относительно
                                // аватарки, а не съезжало влево из-за карандаша.
                                const SizedBox(width: 28),
                                Text(
                                  _userName ?? tr('Пользователь'),
                                  style: TextStyle(
                                    fontSize: 25,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.of(context).textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  CupertinoIcons.pencil,
                                  size: 20,
                                  color: AppColors.of(context).textSecondary,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.of(context).divider),
              _buildReadOnlyItem(
                title: 'Email',
                subtitle: tr('Для уведомлений и\nприглашений'),
                value: _emailController.text,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubscription() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(tr('ПОДПИСКА')),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    tr('Текущий тариф'),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.of(context).textSecondary),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.of(context).surfaceVariant,
                      foregroundColor: AppColors.of(context).textSecondary,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    onPressed: () {},
                    child: Text(
                      tr('Бесплатный'),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildSubscriptionBanner(),
          ],
        ),
      ],
    );
  }

  Widget _buildSubscriptionBanner() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(20, 13, 20, 13),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // звезды как в сайдбаре (мерцают)
          ..._buildTwinklingStars(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Ladder',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            child: Text(
                              'Basic',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr('Оформи Pro, чтобы получить больше'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    SwipeablePageRoute(
                      builder: (_) => const SubscriptionPage(),
                    ),
                  );
                },
                child: Text(
                  tr('Обновить'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTwinklingStars() {
    final positions = [
      const Offset(20, 10),
      const Offset(80, 25),
      const Offset(140, 15),
      const Offset(200, 30),
      const Offset(260, 18),
      const Offset(320, 28),
      const Offset(50, 55),
      const Offset(110, 65),
      const Offset(170, 50),
      const Offset(230, 70),
      const Offset(290, 60),
      const Offset(30, 90),
      const Offset(90, 100),
      const Offset(150, 85),
      const Offset(210, 105),
      const Offset(270, 95),
      const Offset(320, 110),
    ];
    return positions
        .asMap()
        .entries
        .map((entry) => Positioned(
              left: entry.value.dx,
              top: entry.value.dy,
              child: AnimatedBuilder(
                animation: _starsController,
                builder: (context, child) {
                  final base = _starsController.value.clamp(0.0, 1.0);
                  final phase = ((base + entry.key * 0.07) % 1.0).clamp(0.0, 1.0);
                  final sine = math.sin(phase * 2 * math.pi);
                  final opacity = (0.3 + 0.7 * (0.5 + 0.5 * sine)).clamp(0.0, 1.0);
                  final scale = 0.8 + 0.4 * (0.5 + 0.5 * sine);
                  return Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 3,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: opacity),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ))
        .toList();
  }

  Widget _buildAppearance() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(tr('Внешний вид')),
        Container(
          decoration: BoxDecoration(
            color: _blockColor,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: AppColors.of(context).border),
          ),
          child: Column(
            children: [
              _buildSelectItem(
                anchorKey: _themeAnchorKey,
                title: tr('Тема'),
                subtitle: tr('Светлая или темная'),
                options: [tr('Светлая'), tr('Темная')],
                currentValue:
                    ThemeController.isDark ? tr('Темная') : tr('Светлая'),
                onChanged: (v) {
                  setState(() {});
                  ThemeController.setDark(v == tr('Темная'));
                },
              ),
              Divider(height: 1, color: AppColors.of(context).divider),
              _buildSelectItem(
                anchorKey: _languageAnchorKey,
                title: tr('Язык'),
                subtitle: tr('Язык интерфейса'),
                // Подписи языков не переводим — каждый язык на своём языке.
                options: LocaleController.supported.values.toList(),
                currentValue: LocaleController.label,
                onChanged: (v) {
                  // Находим код языка по выбранной подписи и применяем.
                  final code = LocaleController.supported.entries
                      .firstWhere((e) => e.value == v)
                      .key;
                  LocaleController.setLanguage(code);
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotifications() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(tr('Уведомления')),
        Container(
          decoration: BoxDecoration(
            color: _blockColor,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: AppColors.of(context).border),
          ),
          child: Column(
            children: [
              _buildToggleItem(
                title: tr('Уведомления'),
                subtitle: tr('Получать уведомления о задачах'),
                value: _notificationsEnabled,
                onChanged: (v) {
                  HapticFeedback.lightImpact();
                  setState(() => _notificationsEnabled = v);
                },
              ),
              Divider(height: 1, color: AppColors.of(context).divider),
              _buildToggleItem(
                title: tr('Email уведомления'),
                subtitle: tr('Получать уведомления на email'),
                value: _emailNotificationsEnabled,
                onChanged: (v) {
                  HapticFeedback.lightImpact();
                  setState(() => _emailNotificationsEnabled = v);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIntegrations() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(tr('Интеграции')),
        Container(
          decoration: BoxDecoration(
            color: _blockColor,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: AppColors.of(context).border),
          ),
          child: Column(
            children: [
              _buildIntegrationItem(
                icon: CupertinoIcons.calendar,
                title: tr('Google Календарь'),
                subtitle: tr('Импортировать события в задачи'),
                loading: _importingCalendar,
                badge: _googleNewEvents,
                onTap: _importGoogleCalendar,
              ),
              Divider(height: 1, color: AppColors.of(context).divider),
              _buildIntegrationItem(
                icon: CupertinoIcons.calendar_today,
                title: tr('Apple Календарь'),
                subtitle: tr('Импортировать события в задачи'),
                loading: _importingAppleCalendar,
                badge: _appleNewEvents,
                onTap: _importAppleCalendar,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIntegrationItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool loading,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: loading ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.of(context).surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 22, color: AppColors.of(context).textSecondary),
                ),
                // Индикатор: есть новые, ещё не импортированные события.
                if (badge > 0)
                  Positioned(
                    top: -3,
                    right: -3,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B30),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: AppColors.of(context).surface, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.of(context).textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: AppColors.of(context).textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CupertinoActivityIndicator(),
                  )
                : Icon(
                    CupertinoIcons.chevron_forward,
                    size: 18,
                    color: AppColors.of(context).textTertiary,
                  ),
          ],
        ),
      ),
    );
  }

  Future<void> _importAppleCalendar() async {
    // Защита от повторных нажатий: пока идёт импорт, новый запуск игнорируем,
    // иначе параллельные импорты читают БД до записи и плодят дубликаты.
    if (_importingAppleCalendar) return;
    setState(() => _importingAppleCalendar = true);
    try {
      final result = await AppleCalendarService().importEvents();
      if (!mounted) return;
      if (result.imported > 0) {
        CustomSnackBar.show(context, tr('Импортировано задач: {0}', [result.imported]));
      } else if (result.skipped > 0) {
        // Все найденные события уже были импортированы ранее — показываем
        // явный алерт, чтобы пользователь не жал импорт повторно.
        await _showCalendarAlert(tr('Все события уже импортированы'));
      } else {
        CustomSnackBar.show(context, tr('Новых событий нет'));
      }
      _refreshCalendarBadges();
    } on CalendarPermissionDenied {
      if (mounted) {
        CustomSnackBar.show(context, tr('Нет доступа к календарю. Разрешите в Настройках iOS'));
      }
    } catch (e) {
      debugPrint('Ошибка импорта Apple Календаря: $e');
      if (mounted) {
        CustomSnackBar.show(context, tr('Не удалось импортировать календарь'));
      }
    } finally {
      if (mounted) setState(() => _importingAppleCalendar = false);
    }
  }

  // Алерт-диалог о результате импорта календаря.
  Future<void> _showCalendarAlert(String title, [String? message]) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: (message == null || message.isEmpty)
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(message),
              ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr('OK')),
          ),
        ],
      ),
    );
  }

  Future<void> _importGoogleCalendar() async {
    // Защита от повторных нажатий: пока идёт импорт, новый запуск игнорируем,
    // иначе параллельные импорты читают БД до записи и плодят дубликаты.
    if (_importingCalendar) return;
    setState(() => _importingCalendar = true);
    try {
      final result = await GoogleCalendarService().importEvents();
      if (!mounted) return;
      if (result.imported > 0) {
        CustomSnackBar.show(context, tr('Импортировано задач: {0}', [result.imported]));
      } else if (result.skipped > 0) {
        await _showCalendarAlert(tr('Все события уже импортированы'));
      } else {
        CustomSnackBar.show(context, tr('Новых событий нет'));
      }
      _refreshCalendarBadges();
    } on GoogleSignInCancelled {
      // Пользователь сам отменил вход — молча выходим.
    } on GoogleNotConfigured {
      if (mounted) {
        CustomSnackBar.show(context, tr('Google Календарь ещё не настроен'));
      }
    } catch (e) {
      debugPrint('Ошибка импорта календаря: $e');
      if (mounted) {
        CustomSnackBar.show(context, tr('Не удалось импортировать календарь'));
      }
    } finally {
      if (mounted) setState(() => _importingCalendar = false);
    }
  }

  // Пересчитывает количество ещё не импортированных событий для бейджей.
  Future<void> _refreshCalendarBadges() async {
    try {
      final apple = await AppleCalendarService().countNewEvents();
      if (mounted) setState(() => _appleNewEvents = apple);
    } catch (_) {/* индикатор не критичен */}
    try {
      final google = await GoogleCalendarService().countNewEvents();
      if (mounted) setState(() => _googleNewEvents = google);
    } catch (_) {/* индикатор не критичен */}
  }

  // ───────── Безопасность и данные ─────────
  Widget _buildSecurity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(tr('Безопасность и данные')),
        Container(
          decoration: BoxDecoration(
            color: _blockColor,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: AppColors.of(context).border),
          ),
          child: Column(
            children: [
              _buildToggleItem(
                title: tr('Face ID / Touch ID'),
                subtitle: tr('Блокировать приложение'),
                value: _faceIdEnabled,
                onChanged: _toggleFaceId,
              ),
              Divider(height: 1, color: AppColors.of(context).divider),
              _buildActionItem(
                title: tr('Экспорт данных'),
                subtitle: tr('Скачать копию ваших данных'),
                icon: CupertinoIcons.square_arrow_up,
                onTap: _exportData,
              ),
              Divider(height: 1, color: AppColors.of(context).divider),
              _buildActionItem(
                title: tr('Очистить кэш'),
                subtitle: tr('Освободить место на устройстве'),
                icon: CupertinoIcons.trash,
                onTap: _clearCache,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ───────── Поддержка и информация ─────────
  Widget _buildSupport() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(tr('Поддержка')),
        Container(
          decoration: BoxDecoration(
            color: _blockColor,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: AppColors.of(context).border),
          ),
          child: Column(
            children: [
              _buildActionItem(
                title: tr('Написать отзыв'),
                subtitle: tr('Оцените приложение в App Store'),
                icon: CupertinoIcons.star,
                onTap: _writeReview,
              ),
              Divider(height: 1, color: AppColors.of(context).divider),
              _buildActionItem(
                title: tr('Поделиться приложением'),
                subtitle: tr('Расскажите друзьям'),
                icon: CupertinoIcons.share,
                onTap: _shareApp,
              ),
              Divider(height: 1, color: AppColors.of(context).divider),
              _buildActionItem(
                title: tr('Восстановить покупку'),
                subtitle: tr('Вернуть оформленную подписку'),
                icon: CupertinoIcons.arrow_clockwise,
                onTap: _restorePurchase,
              ),
              Divider(height: 1, color: AppColors.of(context).divider),
              _buildActionItem(
                title: tr('Конфиденциальность'),
                subtitle: tr('Политика конфиденциальности'),
                icon: CupertinoIcons.lock_shield,
                onTap: _openPrivacy,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Кликабельный пункт настроек: заголовок + подзаголовок + иконка справа.
  Widget _buildActionItem({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.of(context).textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: AppColors.of(context).textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(icon, size: 20, color: AppColors.of(context).textTertiary),
          ],
        ),
      ),
    );
  }

  // ───────── Логика пунктов ─────────

  // Идентификатор приложения в App Store (заполнить после публикации).
  static const String _appStoreId = '0000000000';

  Future<void> _toggleFaceId(bool value) async {
    if (value) {
      // Включаем — сначала убедимся, что биометрия доступна и проходит проверку.
      final available = await BiometricService.instance.isAvailable();
      if (!available) {
        if (mounted) {
          CustomSnackBar.show(context, tr('Биометрия недоступна на устройстве'));
        }
        return;
      }
      final ok = await BiometricService.instance
          .authenticate(tr('Подтвердите, чтобы включить блокировку'));
      if (!ok) {
        if (mounted) {
          CustomSnackBar.show(context, tr('Не удалось включить блокировку'));
        }
        return;
      }
    }
    await BiometricService.instance.setEnabled(value);
    HapticFeedback.selectionClick();
    if (mounted) setState(() => _faceIdEnabled = value);
  }

  Future<void> _exportData() async {
    try {
      HapticFeedback.lightImpact();
      final userId = UserSession.currentUserId;
      final buffer = StringBuffer();
      buffer.writeln('{');
      buffer.writeln('  "app": "ladder",');
      buffer.writeln('  "exportedAt": "${DateTime.now().toIso8601String()}",');
      buffer.writeln('  "userId": ${userId ?? 'null'},');

      final tasks = await (appDatabase.select(appDatabase.tasks)
            ..where((t) => t.isDeleted.equals(false)))
          .get();
      final notes = await (appDatabase.select(appDatabase.notes)
            ..where((n) => n.isDeleted.equals(false)))
          .get();
      final habits = await (appDatabase.select(appDatabase.habits)
            ..where((h) => h.isDeleted.equals(false)))
          .get();
      final events = await (appDatabase.select(appDatabase.events)
            ..where((e) => e.isDeleted.equals(false)))
          .get();

      String esc(String? s) => (s ?? '').replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n');

      buffer.writeln('  "tasks": [');
      for (var i = 0; i < tasks.length; i++) {
        final t = tasks[i];
        buffer.write('    {"title": "${esc(t.title)}", "date": "${t.date.toIso8601String()}", "completed": ${t.isCompleted}}');
        buffer.writeln(i < tasks.length - 1 ? ',' : '');
      }
      buffer.writeln('  ],');
      buffer.writeln('  "notes": [');
      for (var i = 0; i < notes.length; i++) {
        final n = notes[i];
        buffer.write('    {"content": "${esc(n.content)}"}');
        buffer.writeln(i < notes.length - 1 ? ',' : '');
      }
      buffer.writeln('  ],');
      buffer.writeln('  "habits": [');
      for (var i = 0; i < habits.length; i++) {
        final h = habits[i];
        buffer.write('    {"title": "${esc(h.title)}"}');
        buffer.writeln(i < habits.length - 1 ? ',' : '');
      }
      buffer.writeln('  ],');
      buffer.writeln('  "events": [');
      for (var i = 0; i < events.length; i++) {
        final e = events[i];
        buffer.write('    {"title": "${esc(e.title)}", "date": "${e.date.toIso8601String()}"}');
        buffer.writeln(i < events.length - 1 ? ',' : '');
      }
      buffer.writeln('  ]');
      buffer.writeln('}');

      final dir = await getTemporaryDirectory();
      final file = File(path.join(dir.path, 'ladder_export_${DateTime.now().millisecondsSinceEpoch}.json'));
      await file.writeAsString(buffer.toString());
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: tr('Экспорт данных')),
      );
    } catch (e) {
      debugPrint('Ошибка экспорта данных: $e');
      if (mounted) CustomSnackBar.show(context, tr('Не удалось экспортировать данные'));
    }
  }

  Future<void> _clearCache() async {
    try {
      HapticFeedback.lightImpact();
      imageCache.clear();
      imageCache.clearLiveImages();
      final dir = await getTemporaryDirectory();
      if (dir.existsSync()) {
        for (final entity in dir.listSync()) {
          try {
            entity.deleteSync(recursive: true);
          } catch (_) {/* отдельные файлы могут быть заняты */}
        }
      }
      if (mounted) CustomSnackBar.show(context, tr('Кэш очищен'));
    } catch (e) {
      debugPrint('Ошибка очистки кэша: $e');
      if (mounted) CustomSnackBar.show(context, tr('Не удалось очистить кэш'));
    }
  }

  Future<void> _writeReview() async {
    HapticFeedback.lightImpact();
    final uri = Uri.parse('https://apps.apple.com/app/id$_appStoreId?action=write-review');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) CustomSnackBar.show(context, tr('Не удалось открыть App Store'));
    }
  }

  Future<void> _shareApp() async {
    HapticFeedback.lightImpact();
    final link = 'https://apps.apple.com/app/id$_appStoreId';
    await SharePlus.instance.share(
      ShareParams(text: tr('Попробуй планер ladder: {0}', [link])),
    );
  }

  Future<void> _restorePurchase() async {
    HapticFeedback.lightImpact();
    // Покупки в приложении ещё не подключены — заглушка до релиза.
    if (mounted) CustomSnackBar.show(context, tr('Покупок для восстановления не найдено'));
  }

  void _openPrivacy() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      SwipeablePageRoute(builder: (_) => const PrivacyPage()),
    );
  }

  Widget _buildAbout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(tr('О приложении')),
        Container(
          decoration: BoxDecoration(
            color: _blockColor,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: AppColors.of(context).border),
          ),
          child: Column(
            children: [
              _buildSimpleItem(
                title: tr('Версия'),
                subtitle: '1.0.1',
              ),
              Divider(height: 1, color: AppColors.of(context).divider),
              _buildIdItem(),
            ],
          ),
        ),
      ],
    );
  }

  // Уникальный ID пользователя: LDDR-XXXXXXX (7 цифр, отсчёт справа).
  String get _appId {
    final id = UserSession.currentUserId ?? 0;
    return 'LDDR-${id.toString().padLeft(7, '0')}';
  }

  // Кликабельный пункт с ID — тап копирует в буфер и показывает тост.
  Widget _buildIdItem() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: _appId));
        HapticFeedback.selectionClick();
        if (mounted) CustomSnackBar.show(context, tr('Скопировано'));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ID',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.of(context).textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _appId,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.of(context).textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.doc_on_doc,
              size: 18,
              color: AppColors.of(context).textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  // «Участник с июня 2027» — внизу настроек.
  String _memberSince() {
    final d = _userCreatedAt;
    if (d == null) return '';
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    return tr('Участник с {0}', ['${months[d.month - 1]} ${d.year}']);
  }


  // Цвет блоков-секций (Внешний вид/Интеграции/Уведомления/О приложении) —
  // в светлой теме слегка сероватый, в тёмной — обычный surface.
  Color get _blockColor => AppColors.of(context).isDark
      ? AppColors.of(context).surface
      : const Color(0xFFF7F8FA);

  Future<void> _logout() async {
    // Полный выход: чистим сохранённую сессию (иначе автологин вернёт).
    await AuthRepository(appDatabase).logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, animation, _) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: const LoginPage(),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.of(context).textTertiary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildReadOnlyItem({
    required String title,
    required String subtitle,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.of(context).textPrimary),
                ),
                const SizedBox(height: 4),
                subtitle.contains('\n')
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: subtitle.split('\n').map((line) {
                          return Text(
                            line,
                            style: TextStyle(fontSize: 12, color: AppColors.of(context).textTertiary),
                            softWrap: line == subtitle.split('\n').first ? false : true,
                          );
                        }).toList(),
                      )
                    : Text(
                        subtitle,
                        style: TextStyle(fontSize: 12, color: AppColors.of(context).textTertiary),
                      ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: Text(
              value,
              style: TextStyle(color: AppColors.of(context).textPrimary, fontSize: 16),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleItem({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.of(context).textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: AppColors.of(context).textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Нативный переключатель iOS 26 (liquid glass) из adaptive_platform_ui.
          AdaptiveSwitch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF34C759),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectItem({
    required GlobalKey anchorKey,
    required String title,
    required String subtitle,
    required List<String> options,
    required String currentValue,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.of(context).textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: AppColors.of(context).textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Значение с шевронами ↑↓ открывает стеклянное (liquid glass)
          // выпадающее меню со списком вариантов.
          GestureDetector(
            key: anchorKey,
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.lightImpact();
              _showSelectMenu(
                anchorKey: anchorKey,
                title: title,
                options: options,
                currentValue: currentValue,
                onChanged: onChanged,
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currentValue,
                    style: TextStyle(fontSize: 16, color: AppColors.of(context).textTertiary),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    CupertinoIcons.chevron_up_chevron_down,
                    size: 16,
                    color: AppColors.of(context).textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleItem({
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.of(context).textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: AppColors.of(context).textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Стеклянное (liquid glass) выпадающее меню выбора для настроек.
// Привязано к контролу значения, с галочкой у текущего варианта.
class _GlassSelectMenu extends StatefulWidget {
  final double left;
  final double top;
  final double width;
  final String title;
  final List<String> options;
  final String currentValue;
  final ValueChanged<String> onSelected;
  final VoidCallback onClose;

  const _GlassSelectMenu({
    required this.left,
    required this.top,
    required this.width,
    required this.title,
    required this.options,
    required this.currentValue,
    required this.onSelected,
    required this.onClose,
  });

  @override
  State<_GlassSelectMenu> createState() => _GlassSelectMenuState();
}

class _GlassSelectMenuState extends State<_GlassSelectMenu> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 200),
      vsync: this,
    );
    // Плавное появление одним куском: рост от верхнего правого угла + проявление.
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
        reverseCurve: Curves.easeIn,
      ),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _animationController.forward();
  }

  // Плавно сворачиваем меню обратно, затем выполняем действие (закрытие/выбор).
  void _close(VoidCallback then) {
    if (_closing) return;
    _closing = true;
    _animationController.reverse().whenComplete(then);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => _close(widget.onClose),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            Positioned(
              left: widget.left,
              top: widget.top,
              child: Material(
                color: Colors.transparent,
                // В светлой теме добавляем тень, чтобы меню отделялось от
                // белого фона; в тёмной тень не нужна.
                elevation: colors.isDark ? 0 : 10,
                shadowColor: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(18),
                child: GestureDetector(
                  onTap: () {},
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      alignment: Alignment.topRight,
                      // Стекло на BackdropFilter (стиль iOS 26): рисуется
                      // корректно с первого кадра, без чёрной вспышки
                      // ожидавшего инициализации liquid-glass шейдера.
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              // В светлой теме слегка приглушаем белизну и
                              // усиливаем границу с тенью, чтобы меню не
                              // сливалось с белым фоном настроек.
                              color: colors.isDark
                                  ? colors.surface.withValues(alpha: 0.72)
                                  : const Color(0xFFF6F7F8).withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: colors.isDark
                                    ? colors.border.withValues(alpha: 0.6)
                                    : const Color(0xFFD2D4D9),
                                width: colors.isDark ? 0.5 : 1,
                              ),
                            ),
                            child: SizedBox(
                          width: widget.width,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: widget.options.map((option) {
                              final isSelected = option == widget.currentValue;
                              return InkWell(
                                onTap: () => _close(() => widget.onSelected(option)),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          option,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                            color: colors.textPrimary,
                                          ),
                                        ),
                                      ),
                                      if (isSelected)
                                        Icon(
                                          CupertinoIcons.check_mark,
                                          size: 16,
                                          color: colors.textPrimary,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

