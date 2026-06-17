import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/database_instance.dart';
import '../data/repositories/task_repository.dart';
import '../data/user_session.dart';

/// Сервис для синхронизации данных с виджетами iOS/Android
class WidgetDataSync {
  static const MethodChannel _channel = MethodChannel('com.hackflow.ladder/widget_data_sync');
  
  /// Синхронизировать данные задач на сегодня для виджета
  static Future<void> syncTodayTasks() async {
    if (!Platform.isIOS) return; // Пока только iOS
    
    try {
      final userId = UserSession.currentUserId;
      if (userId == null) return;
      
      final taskRepository = TaskRepository(appDatabase);
      final today = DateTime.now();
      
      // Загружаем задачи на сегодня
      final tasks = await taskRepository.tasksForDate(today);
      
      // Фильтруем только незавершенные задачи
      final incompleteTasks = tasks.where((t) => !t.isCompleted).take(4).toList();
      
      // Сохраняем через Method Channel в App Group
      await _channel.invokeMethod('syncTodayTasks', {
        'taskCount': incompleteTasks.length,
        'tasks': incompleteTasks.map((t) => t.title).toList(),
      });
    } catch (e) {
      debugPrint('Ошибка синхронизации данных виджета: $e');
    }
  }
}
