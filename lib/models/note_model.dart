import 'attached_file.dart';

class NoteModel {
  final int? id;
  final String title;
  final String content;
  final double x; // Позиция X
  final double y; // Позиция Y
  final double width; // Ширина
  final double height; // Высота
  final String color; // Цвет заметки (hex)
  final bool isLocked; // Закреплена ли заметка
  final String? drawingData; // JSON данные для рисунка
  final List<AttachedFile>? attachedFiles;
  final DateTime createdAt;
  final DateTime updatedAt;

  NoteModel({
    this.id,
    required this.title,
    required this.content,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.color = '#FFEB3B', // Желтый по умолчанию
    this.isLocked = false,
    this.drawingData,
    this.attachedFiles,
    required this.createdAt,
    required this.updatedAt,
  });

  NoteModel copyWith({
    int? id,
    String? title,
    String? content,
    double? x,
    double? y,
    double? width,
    double? height,
    String? color,
    bool? isLocked,
    String? drawingData,
    List<AttachedFile>? attachedFiles,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NoteModel(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      color: color ?? this.color,
      isLocked: isLocked ?? this.isLocked,
      drawingData: drawingData ?? this.drawingData,
      attachedFiles: attachedFiles ?? this.attachedFiles,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Преобразование в JSON для хранения в БД
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'content': content,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'color': color,
      'isLocked': isLocked,
      'drawingData': drawingData,
    };
  }

  // Создание из JSON
  factory NoteModel.fromJson(Map<String, dynamic> json, {int? id, DateTime? createdAt, DateTime? updatedAt}) {
    return NoteModel(
      id: id,
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      x: (json['x'] ?? 0.0).toDouble(),
      y: (json['y'] ?? 0.0).toDouble(),
      width: (json['width'] ?? 395.0).toDouble(),
      height: (json['height'] ?? 150.0).toDouble(),
      color: json['color'] ?? '#FFEB3B',
      isLocked: json['isLocked'] ?? false,
      drawingData: json['drawingData'],
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

