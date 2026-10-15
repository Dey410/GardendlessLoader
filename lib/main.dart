import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app_controller.dart';
import 'src/logging/app_logger.dart';
import 'src/logging/log_event_catalog.dart';
import 'src/logging/native_app_logger.dart';
import 'src/ui/verdant/garden_theme.dart';
import 'src/ui/verdant/verdant_home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final logger = await NativeAppLogger.initialize(
    eventSchemas: defaultLogEventSchemas,
  );
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    logger.emit(
      level: LogLevel.error,
      category: 'app.flutter',
      event: 'flutter_framework_error',
      outcome: LogOutcome.failed,
      code: 'flutter_framework_error',
      error: details.exception,
      stackTrace: details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    logger.emit(
      level: LogLevel.fatal,
      category: 'app.dart',
      event: 'dart_unhandled_error',
      outcome: LogOutcome.failed,
      code: 'dart_unhandled_error',
      error: error,
      stackTrace: stackTrace,
    );
    return true;
  };
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
  unawaited(SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]));
  runZonedGuarded(
    () => runApp(GardendlessLoaderApp(logger: logger)),
    (error, stackTrace) => logger.emit(
      level: LogLevel.fatal,
      category: 'app.dart',
      event: 'dart_unhandled_error',
      outcome: LogOutcome.failed,
      code: 'dart_unhandled_error',
      error: error,
      stackTrace: stackTrace,
    ),
  );
}

class GardendlessLoaderApp extends StatefulWidget {
  const GardendlessLoaderApp({required this.logger, super.key});

  final NativeAppLogger logger;

  @override
  State<GardendlessLoaderApp> createState() => _GardendlessLoaderAppState();
}

class _GardendlessLoaderAppState extends State<GardendlessLoaderApp>
    with WidgetsBindingObserver {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AppController(appLogger: widget.logger);
    unawaited(_controller.initialize().then((_) {
      if (mounted && _controller.initialized) {
        unawaited(_controller.refreshAboutContent());
        unawaited(_controller.refreshAnnouncement());
      }
    }));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.logger.emit(
      level: LogLevel.info,
      category: 'app.lifecycle',
      event: 'app_lifecycle_changed',
      outcome: LogOutcome.observed,
      context: <String, Object?>{'state': state.name},
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GardendlessLoader',
      debugShowCheckedModeBanner: false,
      theme: GardenTheme.dark,
      darkTheme: GardenTheme.dark,
      themeMode: ThemeMode.dark,
      home: HomePage(controller: _controller),
    );
  }
}
