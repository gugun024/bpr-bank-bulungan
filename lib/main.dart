import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'audience/audience_app.dart';
import 'operator/operator_app.dart';

/// Entry point ganda (satu executable, dua window):
/// - window utama (arguments kosong) → OPERATOR
/// - window tambahan (arguments 'audience') → PENONTON
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // SQLite untuk Windows (dipakai window operator).
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final controller = await WindowController.fromCurrentEngine();
  if (controller.arguments == 'audience') {
    runApp(const AudienceApp());
  } else {
    runApp(const OperatorApp());
  }
}
