import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/time/business_time.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ensureTimeZonesLoaded();
  runApp(const ProviderScope(child: CafeDeskApp()));
}
