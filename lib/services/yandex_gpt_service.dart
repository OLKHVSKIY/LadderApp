import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../models/task.dart' as task_model;
import '../data/repositories/task_repository.dart';
import '../data/database_instance.dart';

class YandexGptService {
  static final YandexGptService _instance = YandexGptService._internal();
  factory YandexGptService() => _instance;
  YandexGptService._internal();

  final String _apiKey = dotenv.env['YANDEX_GPT_API_KEY'] ?? '';
  final String _folderId = dotenv.env['YANDEX_GPT_FOLDER_ID'] ?? '';
  final String _apiUrl = 'https://llm.api.cloud.yandex.net/foundationModels/v1/completion';

  Future<String> sendMessage(
    String userMessage,
    List<Map<String, String>> chatHistory,
    String language,
  ) async {
    try {
      // Загружаем задачи для контекста
      final taskRepository = TaskRepository(appDatabase);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tasks = await taskRepository.tasksForDateRange(
        today.subtract(const Duration(days: 30)),
        today.add(const Duration(days: 30)),
      ) as List<task_model.Task>;

      // Формируем промпт
      final systemPrompt = _buildSystemPrompt(tasks, language);

      // Формируем историю сообщений
      // Yandex GPT не поддерживает system role, поэтому добавляем системный промпт в первое сообщение
      final messages = <Map<String, String>>[];
      
      if (chatHistory.isEmpty) {
        // Если истории нет, добавляем системный промпт в первое сообщение
        messages.add({
          'role': 'user',
          'text': '$systemPrompt\n\nПользователь: $userMessage',
        });
      } else {
        // Если есть история, добавляем системный промпт в первое сообщение истории
        final firstMessage = chatHistory.first;
        messages.add({
          'role': firstMessage['role'] ?? 'user',
          'text': '$systemPrompt\n\n${firstMessage['text'] ?? ''}',
        });
        // Добавляем остальные сообщения
        for (var i = 1; i < chatHistory.length; i++) {
          messages.add({
            'role': chatHistory[i]['role'] ?? 'user',
            'text': chatHistory[i]['text'] ?? '',
          });
        }
        // Добавляем текущее сообщение
        messages.add({
          'role': 'user',
          'text': userMessage,
        });
      }

      // Отправляем запрос к Yandex GPT
      final response = await http.post(
        Uri.parse('https://llm.api.cloud.yandex.net/foundationModels/v1/completion'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Api-Key $_apiKey',
          'x-folder-id': _folderId,
        },
        body: jsonEncode({
          'modelUri': 'gpt://$_folderId/yandexgpt/latest',
          'completionOptions': {
            'stream': false,
            'temperature': 0.6,
            'maxTokens': 2000,
          },
          'messages': messages,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['result']['alternatives'][0]['message']['text'] ?? '';
      } else {
        throw Exception('API Error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  String _buildSystemPrompt(List<task_model.Task> tasks, String language) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayStr = _formatDate(today);
    final tomorrow = today.add(const Duration(days: 1));
    final yesterday = today.subtract(const Duration(days: 1));
    final dayAfterTomorrow = today.add(const Duration(days: 2));

    final todayTasks = tasks.where((t) => _isSameDay(t.date, today)).toList();
    final tomorrowTasks = tasks.where((t) => _isSameDay(t.date, tomorrow)).toList();
    final yesterdayTasks = tasks.where((t) => _isSameDay(t.date, yesterday)).toList();
    final dayAfterTomorrowTasks =
        tasks.where((t) => _isSameDay(t.date, dayAfterTomorrow)).toList();

    final todayCompleted = todayTasks.where((t) => t.isCompleted).length;
    final thisWeekTasks = tasks.where((t) {
      final weekStart = today.subtract(Duration(days: today.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 6));
      return t.date.isAfter(weekStart.subtract(const Duration(days: 1))) &&
          t.date.isBefore(weekEnd.add(const Duration(days: 1)));
    }).toList();
    final thisWeekCompleted = thisWeekTasks.where((t) => t.isCompleted).length;

    final languageInstructions = {
      'ru': '''Ты - умный и дружелюбный ассистент. ВСЕГДА отвечай ТОЛЬКО на русском языке.

ТВОИ ОСНОВНЫЕ ВОЗМОЖНОСТИ:
1. Отвечать на любые вопросы: образовательные, поучительные, общие вопросы, помощь с информацией
2. Помогать с управлением задачами и заметками (создание, анализ, статистика)
3. Давать советы и рекомендации
4. Объяснять сложные темы простым языком

ОГРАНИЧЕНИЯ:
- НЕ обсуждай политику, политические темы, политические партии и политических деятелей
- НЕ используй нецензурную лексику, мат, оскорбления
- НЕ давай медицинские диагнозы или рекомендации по лечению (только общую информацию)
- Будь вежливым, дружелюбным и профессиональным

КОГДА ПОЛЬЗОВАТЕЛЬ ПРОСИТ СОЗДАТЬ ЗАДАЧУ ИЛИ ЗАМЕТКУ - используй специальные команды (см. ниже).
КОГДА ПОЛЬЗОВАТЕЛЬ ЗАДАЕТ ОБЩИЙ ВОПРОС - отвечай на него полно и полезно, как обычный AI-ассистент.''',
      'en': '''You are a smart and friendly assistant. ALWAYS respond ONLY in English.

YOUR MAIN CAPABILITIES:
1. Answer any questions: educational, instructive, general questions, help with information
2. Help with task and note management (creation, analysis, statistics)
3. Give advice and recommendations
4. Explain complex topics in simple language

RESTRICTIONS:
- DO NOT discuss politics, political topics, political parties, or political figures
- DO NOT use profanity, swear words, or offensive language
- DO NOT provide medical diagnoses or treatment recommendations (only general information)
- Be polite, friendly, and professional

WHEN USER ASKS TO CREATE A TASK OR NOTE - use special commands (see below).
WHEN USER ASKS A GENERAL QUESTION - answer it fully and helpfully, like a regular AI assistant.''',
      'es': '''Eres un asistente inteligente y amigable. SIEMPRE responde SOLO en español.

TUS CAPACIDADES PRINCIPALES:
1. Responder cualquier pregunta: educativas, instructivas, preguntas generales, ayuda con información
2. Ayudar con la gestión de tareas y notas (creación, análisis, estadísticas)
3. Dar consejos y recomendaciones
4. Explicar temas complejos en lenguaje simple

RESTRICCIONES:
- NO discutas política, temas políticos, partidos políticos o figuras políticas
- NO uses lenguaje soez, palabrotas o lenguaje ofensivo
- NO proporciones diagnósticos médicos o recomendaciones de tratamiento (solo información general)
- Sé educado, amigable y profesional

CUANDO EL USUARIO PIDE CREAR UNA TAREA O NOTA - usa comandos especiales (ver abajo).
CUANDO EL USUARIO HACE UNA PREGUNTA GENERAL - respóndela completamente y de manera útil, como un asistente de IA regular.''',
    };

    final baseInstruction = languageInstructions[language] ?? languageInstructions['ru']!;

    final context = '''$baseInstruction

СТАТИСТИКА ЗАДАЧ:
- Сегодня ($todayStr): ${todayTasks.length} задач (выполнено: $todayCompleted)
- Текущая неделя: ${thisWeekTasks.length} задач (выполнено: $thisWeekCompleted)
- Задач на завтра: ${tomorrowTasks.length}
- Задач на вчера: ${yesterdayTasks.length}
- Задач на послезавтра: ${dayAfterTomorrowTasks.length}

Задачи на сегодня ($todayStr):
${todayTasks.isEmpty ? 'Нет задач на сегодня' : todayTasks.asMap().entries.map((e) => '${e.key + 1}. ${e.value.title}${e.value.description != null ? ' - ${e.value.description}' : ''} (Выполнено: ${e.value.isCompleted ? 'да' : 'нет'})').join('\n')}

Задачи на завтра (${_formatDate(tomorrow)}):
${tomorrowTasks.isEmpty ? 'Нет задач на завтра' : tomorrowTasks.asMap().entries.map((e) => '${e.key + 1}. ${e.value.title}${e.value.description != null ? ' - ${e.value.description}' : ''} (Выполнено: ${e.value.isCompleted ? 'да' : 'нет'})').join('\n')}

ВАЖНО: Если пользователь задает общий вопрос (не про создание задачи/заметки), просто отвечай на него полно и полезно!''';

    return context;
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  String _formatDate(DateTime date) {
    const months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

