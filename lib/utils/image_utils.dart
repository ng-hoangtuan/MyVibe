import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Helper an toàn chuyển đổi đường dẫn (URL mạng, data base64 URI, hoặc file
/// cục bộ) thành ImageProvider.
///
/// Dùng chung cho card ở màn hình chính và màn hình nhắc toàn khung.
ImageProvider getCustomImageProvider(String pathOrUrl) {
  final trimmed = pathOrUrl.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return NetworkImage(trimmed);
  } else if (trimmed.startsWith('data:image') ||
      trimmed.startsWith('data:application')) {
    try {
      final base64Content = trimmed.split(',').last;
      return MemoryImage(base64Decode(base64Content));
    } catch (_) {
      return NetworkImage(trimmed);
    }
  } else if (kIsWeb) {
    return NetworkImage(trimmed);
  } else {
    return FileImage(File(trimmed));
  }
}
