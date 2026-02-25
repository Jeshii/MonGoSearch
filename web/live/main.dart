import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:mon_go_search/src/app.dart';

void main() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    debugPrint('${record.level.name}: ${record.time}: ${record.message}');
  });
  runApp(const MyApp());
}
