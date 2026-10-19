import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

/// Simpan file contoh CSV dari assets ke lokasi pilihan user.
///
/// Mengembalikan path file bila berhasil, null bila dibatalkan.
Future<String?> downloadSampleCsv({
  required String assetPath,
  required String suggestedName,
}) async {
  final data = await rootBundle.load(assetPath);
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Simpan contoh CSV',
    fileName: suggestedName,
  );
  if (path == null) return null;
  await File(path).writeAsBytes(data.buffer.asUint8List());
  return path;
}
