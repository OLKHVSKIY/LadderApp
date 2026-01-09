import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:open_filex/open_filex.dart';
import '../models/attached_file.dart';

class FileAttachmentDisplay extends StatelessWidget {
  final List<AttachedFile> files;
  final bool isCompact;

  const FileAttachmentDisplay({
    super.key,
    required this.files,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: files.map((file) {
        return _buildFileItem(context, file);
      }).toList(),
    );
  }

  Widget _buildFileItem(BuildContext context, AttachedFile file) {
    return GestureDetector(
      onTap: () => _downloadFile(context, file),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFFE5E5E5),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            _getFileIcon(file.fileType),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                file.fileName,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _getFileIcon(String fileType) {
    IconData iconData;
    Color iconColor;
    
    switch (fileType) {
      case 'pdf':
        iconData = Icons.picture_as_pdf;
        iconColor = Colors.red;
        break;
      case 'word':
        iconData = Icons.description;
        iconColor = Colors.blue;
        break;
      case 'excel':
        iconData = Icons.table_chart;
        iconColor = Colors.green;
        break;
      case 'powerpoint':
        iconData = Icons.slideshow;
        iconColor = Colors.orange;
        break;
      case 'image':
        iconData = Icons.image;
        iconColor = Colors.purple;
        break;
      case 'text':
        iconData = Icons.text_snippet;
        iconColor = Colors.grey;
        break;
      default:
        iconData = Icons.insert_drive_file;
        iconColor = Colors.grey;
    }
    
    return Container(
      width: isCompact ? 28 : 32,
      height: isCompact ? 28 : 32,
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        iconData,
        size: isCompact ? 16 : 18,
        color: iconColor,
      ),
    );
  }

  Future<void> _downloadFile(BuildContext context, AttachedFile file) async {
    try {
      HapticFeedback.mediumImpact();
      
      final sourceFile = File(file.filePath);
      if (!await sourceFile.exists()) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Файл не найден')),
        );
        return;
      }

      // Получаем директорию для загрузок
      Directory? directory = await getDownloadsDirectory();
      
      // Если папка Downloads недоступна, используем Documents
      if (directory == null || !await directory.exists()) {
        directory = await getApplicationDocumentsDirectory();
      }
      
      // Создаем папку Downloads внутри Documents, если её нет
      final downloadsDir = Directory(path.join(directory.path, 'Downloads'));
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }
      
      // Очищаем имя файла от префикса timestamp, если он есть
      String cleanFileName = file.fileName;
      final timestampPattern = RegExp(r'^\d+_');
      if (timestampPattern.hasMatch(cleanFileName)) {
        cleanFileName = cleanFileName.replaceFirst(timestampPattern, '');
      }
      
      final downloadsPath = path.join(downloadsDir.path, cleanFileName);
      final targetFile = File(downloadsPath);
      
      // Если файл уже существует, добавляем номер
      int counter = 1;
      String finalPath = downloadsPath;
      while (await targetFile.exists()) {
        final nameWithoutExt = path.basenameWithoutExtension(cleanFileName);
        final ext = path.extension(cleanFileName);
        finalPath = path.join(downloadsDir.path, '${nameWithoutExt}_$counter$ext');
        counter++;
      }
      
      // Копируем файл в папку загрузок
      await sourceFile.copy(finalPath);
      
      // Пытаемся открыть файл
      final result = await OpenFilex.open(finalPath);
      
      if (!context.mounted) return;
      
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Файл сохранен: $cleanFileName'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при открытии файла: $e')),
      );
    }
  }
}
