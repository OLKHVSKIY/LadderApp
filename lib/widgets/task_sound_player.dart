import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

// Общий AudioPlayer для всех задач - уменьшает задержку воспроизведения
class TaskSoundPlayer {
  static final TaskSoundPlayer _instance = TaskSoundPlayer._internal();
  factory TaskSoundPlayer() => _instance;

  TaskSoundPlayer._internal() {
    // Настраиваем аудио-сессию ОДИН раз глобально: звук эффекта микшируется
    // с уже играющей музыкой и НЕ прерывает её.
    // iOS: категория playback + mixWithOthers. Android: не запрашиваем
    // аудио-фокус (audioFocus.none) — фоновая музыка не глушится.
    unawaited(
      AudioPlayer.global.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
          android: const AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.assistanceSonification,
            audioFocus: AndroidAudioFocus.none,
          ),
        ),
      ),
    );
  }

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
