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
    // Настраиваем без await для мгновенного запуска
    player.setReleaseMode(ReleaseMode.stop);
    player.setPlayerMode(PlayerMode.lowLatency);
    
    // Воспроизводим звук сразу, без await для одновременного запуска с вибрацией
    player.play(AssetSource('sounds/Выполнено.mp3'), volume: 0.9).then((_) {
      // После окончания воспроизведения освобождаем ресурсы
      Future.delayed(const Duration(seconds: 1), () {
        try {
          player.dispose();
        } catch (e) {
          // Игнорируем ошибки при dispose
        }
      });
    }).catchError((error) {
      debugPrint('Ошибка воспроизведения звука: $error');
      try {
        player.dispose();
      } catch (e) {
        // Игнорируем ошибки
      }
    });
  }

  void dispose() {
    // Не нужно - каждый плеер освобождается самостоятельно
  }
}
