import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'dart:io';
import 'package:drift/drift.dart' as dr;
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart' show kIsWeb;

import '../widgets/main_header.dart';
import '../widgets/sidebar.dart';
import 'tasks_page.dart';
import 'login_page.dart';
import 'subscription_page.dart';
import '../data/database_instance.dart';
import '../data/user_session.dart';
import '../data/app_database.dart';
import '../widgets/custom_snackbar.dart';

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
  String _selectedTheme = 'Светлая';
  String _selectedLanguage = 'Русский';
  final TextEditingController _emailController = TextEditingController();
  bool _saving = false;
  String? _avatarPath;
  String? _userName;
  bool _isAvatarHovered = false;

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
          pageBuilder: (_, animation, __) => FadeTransition(
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
  }

  @override
  void dispose() {
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

  Future<void> _saveProfile() async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      CustomSnackBar.show(context, 'Введите email');
      return;
    }
    // Вибрация при сохранении (такая же как при отметках)
    HapticFeedback.heavyImpact();
    setState(() {
      _saving = true;
    });
    // Получаем текущего пользователя, чтобы сохранить существующий путь к аватару, если он не был изменен
    final currentUser = await (appDatabase.select(appDatabase.users)..where((u) => u.id.equals(userId))).getSingleOrNull();
    final avatarUrlToSave = _avatarPath ?? currentUser?.avatarUrl;
    
    await (appDatabase.update(appDatabase.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        email: dr.Value(email),
        avatarUrl: dr.Value(avatarUrlToSave),
        updatedAt: dr.Value(DateTime.now()),
      ),
    );
    UserSession.setUser(id: userId, email: email, name: _userName);
    setState(() {
      _saving = false;
    });
    if (mounted) {
      CustomSnackBar.show(context, 'Сохранено');
    }
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
            CustomSnackBar.show(context, 'Не удалось открыть галерею');
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
                title: const Text('Не удалось открыть файловый диалог'),
                content: const Text('Пожалуйста, перезапустите приложение полностью (не hot reload).'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Отмена'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Попробовать еще раз'),
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
                  CustomSnackBar.show(context, 'Перезапустите приложение полностью');
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
              CustomSnackBar.show(context, 'Ошибка обработки файла');
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
          CustomSnackBar.show(context, 'Файл не найден');
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
          CustomSnackBar.show(context, 'Ошибка обработки файла');
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
              toolbarTitle: 'Обрезка аватара',
              toolbarColor: Colors.black,
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: true,
            ),
            IOSUiSettings(
              title: 'Обрезка аватара',
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
          CustomSnackBar.show(context, 'Ошибка обрезки изображения');
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
                CustomSnackBar.show(context, 'Ошибка сохранения аватара');
              }
              return;
            }
          }
        } catch (e) {
          debugPrint('Ошибка при сохранении через writeAsBytes: $e');
          if (mounted) {
            CustomSnackBar.show(context, 'Ошибка сохранения аватара: $e');
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

      if (finalPath != null && finalPath.isNotEmpty) {
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
              CustomSnackBar.show(context, 'Аватар обновлен, но не сохранен в профиле');
            }
            return;
          }
        }
        
        if (mounted) {
          CustomSnackBar.show(context, 'Аватар обновлен');
        }
      } else {
        debugPrint('ОШИБКА: finalPath равен null или пустой!');
        if (mounted) {
          CustomSnackBar.show(context, 'Не удалось сохранить аватар');
        }
      }
    } catch (e) {
      debugPrint('Ошибка выбора/обрезки изображения: $e');
      if (mounted) {
        CustomSnackBar.show(context, 'Не удалось обновить аватар');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
            Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top - 10,
              ),
              child: Column(
                children: [
                  MainHeader(
                    title: 'Настройки',
                    onMenuTap: _toggleSidebar,
                    onSearchTap: null,
                    onSettingsTap: null,
                    hideSearchAndSettings: true,
                    showBackButton: true,
                    onBack: _goBack,
                    onGreetingToggle: null,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(15, 20, 15, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildProfile(),
                          const SizedBox(height: 32),
                          _buildSubscription(),
                          const SizedBox(height: 32),
                          _buildAppearance(),
                          const SizedBox(height: 32),
                          _buildNotifications(),
                          const SizedBox(height: 32),
                          _buildAbout(),
                          const SizedBox(height: 20),
                          _buildSaveButton(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Sidebar(
              isOpen: _isSidebarOpen,
              onClose: _toggleSidebar,
              onTasksTap: () {
                _goBack();
              },
              onChatTap: () {
                // Вернуться к задачам, откуда можно в чат
                _goBack();
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF5F5F5)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.only(left: 20, right: 20, top: 10, bottom: 20),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFF5F5F5)),
                  ),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 20, bottom: 20),
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
                                        color: const Color(0xFFF5F5F5),
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
                                    color: Colors.black.withOpacity(_isAvatarHovered ? 0.4 : 0.0),
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
                          // Имя пользователя (не редактируется)
                          Text(
                            _userName ?? 'Пользователь',
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _buildReadOnlyItem(
                title: 'Email',
                subtitle: 'Для уведомлений и\nприглашений',
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
        _buildSectionTitle('ПОДПИСКА'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Текущий тариф',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF333333)),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFFF5F5F5),
                      foregroundColor: const Color(0xFF333333),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    onPressed: () {},
                    child: const Text(
                      'Бесплатный',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
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
                            color: Colors.white.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.3)),
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
                    const Text(
                      'Оформи Pro, чтобы получить больше',
                      style: TextStyle(
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
                  backgroundColor: Colors.white.withOpacity(0.2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (_) => const SubscriptionPage(),
                    ),
                  );
                },
                child: const Text(
                  'Обновить',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                              color: Colors.white.withOpacity(opacity),
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
        _buildSectionTitle('Внешний вид'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF5F5F5)),
          ),
          child: Column(
            children: [
              _buildSelectItem(
                title: 'Тема',
                subtitle: 'Светлая или темная',
                options: const ['Светлая', 'Темная'],
                currentValue: _selectedTheme,
                onChanged: (v) => setState(() => _selectedTheme = v),
              ),
              const Divider(height: 1, color: Color(0xFFF5F5F5)),
              _buildSelectItem(
                title: 'Язык',
                subtitle: 'Язык интерфейса',
                options: const ['Русский', 'English', 'Español'],
                currentValue: _selectedLanguage,
                onChanged: (v) => setState(() => _selectedLanguage = v),
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
        _buildSectionTitle('Уведомления'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF5F5F5)),
          ),
          child: Column(
            children: [
              _buildToggleItem(
                title: 'Уведомления',
                subtitle: 'Получать уведомления о задачах',
              ),
              const Divider(height: 1, color: Color(0xFFF5F5F5)),
              _buildToggleItem(
                title: 'Email уведомления',
                subtitle: 'Получать уведомления на email',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAbout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('О приложении'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF5F5F5)),
          ),
          child: _buildSimpleItem(
            title: 'Версия',
            subtitle: '1.0.1',
          ),
        ),
      ],
    );
  }


  Widget _buildSaveButton() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
            onPressed: _saving ? null : _saveProfile,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Сохранить',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () {
            Navigator.of(context).pushReplacement(
              PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 220),
                pageBuilder: (_, animation, __) => FadeTransition(
                  opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
                  child: const LoginPage(),
                ),
              ),
            );
          },
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: const Color(0xFFFFEEEE),
              border: Border.all(color: const Color(0xFFD60000), width: 1.5),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.logout,
              size: 24,
              color: Color(0xFFD60000),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF999999),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFF5F5F5)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black),
                ),
                const SizedBox(height: 4),
                subtitle.contains('\n')
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: subtitle.split('\n').map((line) {
                          return Text(
                            line,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                            softWrap: line == subtitle.split('\n').first ? false : true,
                          );
                        }).toList(),
                      )
                    : Text(
                        subtitle,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                      ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: Text(
              value,
              style: const TextStyle(color: Colors.black, fontSize: 16),
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
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFF5F5F5)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _Toggle(),
        ],
      ),
    );
  }

  Widget _buildSelectItem({
    required String title,
    required String subtitle,
    required List<String> options,
    required String currentValue,
    required ValueChanged<String> onChanged,
  }) {
    final key = GlobalKey();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            key: key,
            onTap: () async {
              final RenderBox box = key.currentContext!.findRenderObject() as RenderBox;
              final Offset pos = box.localToGlobal(Offset.zero);
              final Size size = box.size;
              final selected = await showMenu<String>(
                context: context,
                position: RelativeRect.fromLTRB(
                  pos.dx,
                  pos.dy + size.height,
                  pos.dx + size.width,
                  pos.dy,
                ),
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 6,
                items: options
                    .map((o) => PopupMenuItem<String>(
                          value: o,
                          height: 40,
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                            child: SizedBox(
                              width: 100,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(left: 15),
                                    child: Text(
                                      o,
                                      style: const TextStyle(fontSize: 15, color: Colors.black),
                                    ),
                                  ),
                                  if (o != options.last)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 16),
                                      child: Center(
                                        child: Transform.translate(
                                          offset: const Offset(4, 0), // slight nudge to center visually
                                          child: const SizedBox(
                                            width: 90,
                                            child: Divider(
                                              height: 1,
                                              thickness: 1,
                                              color: Color(0xFFE5E5E5),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ))
                    .toList(),
              );
              if (selected != null) {
                onChanged(selected);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              constraints: const BoxConstraints(minHeight: 40),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E5E5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currentValue,
                    style: const TextStyle(fontSize: 16, color: Colors.black),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.black),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatefulWidget {
  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _active = !_active;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 50,
        height: 30,
        decoration: BoxDecoration(
          color: _active ? Colors.black : const Color(0xFFE5E5E5),
          borderRadius: BorderRadius.circular(15),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: _active ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(3),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


