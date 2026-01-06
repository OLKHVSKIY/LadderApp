import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'pages/tasks_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Загружаем переменные окружения
  await dotenv.load(fileName: '.env');
  
  // Блокируем горизонтальную ориентацию
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ladder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        textTheme: GoogleFonts.onestTextTheme(),
      ),
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
          child: child,
        );
      },
      home: const TasksPage(),
    );
  }
}
