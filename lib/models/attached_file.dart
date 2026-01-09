class AttachedFile {
  final int? id;
  final String fileName;
  final String filePath;
  final String fileType;
  final int fileSize;

  AttachedFile({
    this.id,
    required this.fileName,
    required this.filePath,
    required this.fileType,
    required this.fileSize,
  });

  String get fileExtension {
    final parts = fileName.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  bool get isImage {
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(fileExtension);
  }

  bool get isDocument {
    return ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf'].contains(fileExtension);
  }

  String get displayName {
    return fileName;
  }

  String get formattedSize {
    if (fileSize < 1024) {
      return '$fileSize B';
    } else if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}
