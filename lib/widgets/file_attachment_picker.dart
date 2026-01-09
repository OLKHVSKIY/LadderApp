import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/attached_file.dart';

class FileAttachmentPicker extends StatefulWidget {
  final List<AttachedFile> initialFiles;
  final Function(List<AttachedFile>) onFilesChanged;

  const FileAttachmentPicker({
    super.key,
    this.initialFiles = const [],
    required this.onFilesChanged,
  });

  @override
  State<FileAttachmentPicker> createState() => _FileAttachmentPickerState();
}

class _FileAttachmentPickerState extends State<FileAttachmentPicker>
    with SingleTickerProviderStateMixin {
  late List<AttachedFile> _files;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _files = List.from(widget.initialFiles);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    if (_files.isNotEmpty) {
      _animationController.forward();
    }
  }

  @override
  void didUpdateWidget(FileAttachmentPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFiles != widget.initialFiles) {
      setState(() {
        _files = List.from(widget.initialFiles);
      });
      if (_files.isNotEmpty) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    try {
      // Закрываем клавиатуру при нажатии на прикрепление файла
      FocusScope.of(context).unfocus();
      HapticFeedback.mediumImpact();
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final newFiles = <AttachedFile>[];
        
        for (var platformFile in result.files) {
          if (platformFile.path != null || platformFile.bytes != null) {
            String? filePath;
            int fileSize = 0;
            
            if (platformFile.path != null) {
              // Для десктопных платформ
              filePath = platformFile.path;
              final file = File(filePath!);
              if (await file.exists()) {
                fileSize = await file.length();
              }
            } else if (platformFile.bytes != null) {
              // Для веба
              final tempDir = await getTemporaryDirectory();
              final fileName = platformFile.name;
              final tempFile = File(path.join(tempDir.path, fileName));
              await tempFile.writeAsBytes(platformFile.bytes!);
              filePath = tempFile.path;
              fileSize = platformFile.bytes!.length;
            }

            if (filePath != null) {
              final extension = path.extension(platformFile.name).toLowerCase().replaceFirst('.', '');
              final fileType = _getFileType(extension);
              
              final attachedFile = AttachedFile(
                fileName: platformFile.name,
                filePath: filePath,
                fileType: fileType,
                fileSize: fileSize,
              );
              
              newFiles.add(attachedFile);
            }
          }
        }

        if (newFiles.isNotEmpty) {
          setState(() {
            _files.addAll(newFiles);
          });
          widget.onFilesChanged(_files);
          _animationController.forward();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при выборе файла: $e')),
        );
      }
    }
  }

  String _getFileType(String extension) {
    final imageTypes = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];
    final docTypes = ['doc', 'docx'];
    final excelTypes = ['xls', 'xlsx'];
    final pptTypes = ['ppt', 'pptx'];
    
    if (imageTypes.contains(extension)) return 'image';
    if (extension == 'pdf') return 'pdf';
    if (docTypes.contains(extension)) return 'word';
    if (excelTypes.contains(extension)) return 'excel';
    if (pptTypes.contains(extension)) return 'powerpoint';
    if (extension == 'txt') return 'text';
    if (extension == 'rtf') return 'rtf';
    return 'other';
  }

  void _removeFile(int index) {
    setState(() {
      _files.removeAt(index);
    });
    widget.onFilesChanged(_files);
    if (_files.isEmpty) {
      _animationController.reverse();
    }
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _pickFiles,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFE5E5E5),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.attach_file,
                    size: 20,
                    color: Color(0xFF666666),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Прикрепить файл',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'PDF, Word, Excel, фото и другие',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Color(0xFF999999),
                ),
              ],
            ),
          ),
        ),
        if (_files.isNotEmpty) ...[
          const SizedBox(height: 12),
          FadeTransition(
            opacity: _fadeAnimation,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _files.asMap().entries.map((entry) {
                final index = entry.key;
                final file = entry.value;
                return _buildFileChip(file, index);
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFileChip(AttachedFile file, int index) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFE5E5E5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _getFileIcon(file.fileType),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              file.displayName,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _removeFile(index),
            child: Container(
              padding: const EdgeInsets.all(2),
              child: const Icon(
                Icons.close,
                size: 16,
                color: Color(0xFF999999),
              ),
            ),
          ),
        ],
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
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        iconData,
        size: 16,
        color: iconColor,
      ),
    );
  }
}
