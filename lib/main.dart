import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/router/app_router.dart';
import 'core/startup/app_bootstrap.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/app_settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bootstrapCompleter = Completer<void>();

  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
  unawaited(
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]),
  );

  runApp(
    ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(bootstrapCompleter.future),
      ],
      child: const WenaTvApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      _bootstrapServices()
          .then(bootstrapCompleter.complete)
          .catchError(bootstrapCompleter.completeError),
    );
  });
}

Future<void> _bootstrapServices() async {
  await Hive.initFlutter();
  await Hive.openBox('wenatv_cache');
  await Hive.openBox('wenatv_user');
  unawaited(_initializeFirebase());
}

Future<void> _initializeFirebase() async {
  try {
    await Firebase.initializeApp();
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
  } catch (_) {
    FlutterError.onError = FlutterError.presentError;
  }
}

class WenaTvApp extends ConsumerWidget {
  const WenaTvApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<void>(
      future: ref.watch(appBootstrapProvider),
      builder: (context, snapshot) {
        final settings = snapshot.connectionState == ConnectionState.done
            ? ref.watch(appSettingsProvider)
            : const AppSettings();
        return MaterialApp.router(
          title: 'WenaTV',
          debugShowCheckedModeBanner: false,
          theme: WenaTheme.light,
          darkTheme: WenaTheme.dark,
          themeMode: settings.themeMode,
          routerConfig: ref.watch(appRouterProvider),
        );
      },
    );
  }
}
