import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'pages/login_page.dart';
import 'pages/tasks_page.dart';
import 'data/database_instance.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/reminder_repository.dart';
import 'data/user_session.dart';
import 'services/deep_link_handler.dart';
import 'services/notification_service.dart';
import 'theme/theme_controller.dart';
import 'l10n/locale_controller.dart';
import 'utils/app_paths.dart';
import 'widgets/swipeable_page_route.dart';
import 'widgets/app_lock_gate.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Кэшируем путь к Documents-директории (для резолва картинок событий).
  await AppPaths.init();

  // Загружаем переменные окружения
  await dotenv.load(fileName: '.env');

  // Загружаем сохранённый режим темы (светлая/тёмная)
  await ThemeController.load();

  // Загружаем сохранённый язык интерфейса
  await LocaleController.load();

  // Инициализируем обработчик deep links
  DeepLinkHandler.initialize();

  // Локальные уведомления о начале заметок + запрос разрешения.
  await NotificationService.instance.init();
  await NotificationService.instance.requestPermissions();

  // Блокируем горизонтальную ориентацию
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Автологин: если есть сохранённая сессия — пускаем сразу в приложение.
  final isLoggedIn = await AuthRepository(appDatabase).restoreSession();

  // Пересобираем локальные уведомления из актуальных напоминаний: чистим
  // «осиротевшие»/устаревшие (поставленные прежней версией) и планируем заново.
  if (isLoggedIn) {
    final userId = UserSession.currentUserId;
    if (userId != null) {
      try {
        final reminders = await ReminderRepository(appDatabase).loadAll(userId);
        await NotificationService.instance.resyncReminders(reminders);
      } catch (e) {
        debugPrint('Не удалось пересобрать напоминания: $e');
      }
    }
  }

  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;

  const MyApp({super.key, this.isLoggedIn = false});

  ThemeData _buildTheme(Brightness brightness) {
    final base = ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: brightness,
      ),
      useMaterial3: true,
      textTheme: GoogleFonts.onestTextTheme(
        brightness == Brightness.dark
            ? ThemeData.dark().textTheme
            : ThemeData.light().textTheme,
      ),
    );
    final isDark = brightness == Brightness.dark;
    return base.copyWith(
      scaffoldBackgroundColor: isDark ? const Color(0xFF000000) : Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) {
        // Вложенный билдер на язык: смена локали перестраивает всё дерево,
        // и все виджеты заново вызывают tr() с новым языком.
        return ValueListenableBuilder<Locale>(
          valueListenable: LocaleController.locale,
          builder: (context, locale, _) {
            return MaterialApp(
              title: 'Ladder',
              debugShowCheckedModeBanner: false,
              locale: locale,
              navigatorKey: SwipeNav.instance.navigatorKey,
              navigatorObservers: [SwipeNavObserver()],
              theme: _buildTheme(Brightness.light),
              darkTheme: _buildTheme(Brightness.dark),
              themeMode: mode,
              builder: (context, child) {
                return GestureDetector(
                  onTap: () {
                    // Закрываем клавиатуру при тапе вне поля ввода
                    FocusScopeNode currentFocus = FocusScope.of(context);
                    if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
                      currentFocus.focusedChild?.unfocus();
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  // Свайп от правого края открывает заново закрытую страницу.
                  // AppLockGate перекрывает всё содержимое экраном блокировки
                  // (Face ID / Touch ID), когда это требуется.
                  child: AppLockGate(
                    child: SwipeForwardArea(child: child ?? const SizedBox()),
                  ),
                );
              },
              home: isLoggedIn
                  ? const TasksPage(animateNavIn: true)
                  : const LoginPage(),
            );
          },
        );
      },
    );
  }
}
