import 'package:flutter/services.dart';

/// Обработчик deep links для открытия функций приложения из виджетов
class DeepLinkHandler {
  static const MethodChannel _channel = MethodChannel('com.hackflow.ladder/deep_link');
  static Function()? onOpenAddTaskPanel;

  static void initialize() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == "openAddTaskPanel") {
        onOpenAddTaskPanel?.call();
      }
    });
  }
}
