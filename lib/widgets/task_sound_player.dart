import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

// Общий AudioPlayer для всех задач - уменьшает задержку воспроизведения
class TaskSoundPlayer {
  static final TaskSoundPlayer _instance = TaskSoundPlayer._internal();
  factory TaskSoundPlayer() => _instance;
  
  TaskSoundPlayer._internal();

  void playTaskCompleteSound() {
    // Создаем новый AudioPlayer для каждого воспроизведения
    // Это гарантирует параллельное воспроизведение без конфликтов
    final player = AudioPlayer();
    
    // Воспроизводим звук СРАЗУ, без await и без предварительных настроек
    // Все настройки делаем асинхронно после запуска воспроизведения
    player.play(AssetSource('sounds/Выполнено.mp3'), volume: 0.9);
    
    // Настройки делаем параллельно, не блокируя воспроизведение
    unawaited(player.setReleaseMode(ReleaseMode.stop));
    unawaited(player.setPlayerMode(PlayerMode.lowLatency));
    
    // Освобождаем ресурсы после окончания
    Future.delayed(const Duration(milliseconds: 500), () {
      try {
        player.dispose();
      } catch (e) {
        // Игнорируем ошибки при dispose
      }
    });
  }

  void dispose() {
    // Не нужно - каждый плеер освобождается самостоятельно
  }
}
