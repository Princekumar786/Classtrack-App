import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../firebase_options.dart';
import 'cms_app.dart';

/// Web entrypoint for the ClassTracks CMS.
///
/// Run with:  flutter run -d chrome -t lib/features/cms/main_cms.dart
/// Build with: flutter build web -t lib/features/cms/main_cms.dart
///
/// This is intentionally separate from the mobile app's `lib/main.dart`; the
/// two share the Firebase project, the [DefaultFirebaseOptions], the Resource
/// model and the theme, but nothing here runs in the mobile app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  runApp(const ProviderScope(child: CmsApp()));
}
