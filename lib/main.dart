import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app_controller.dart';
import 'src/services/app_logger.dart';
import 'src/ui/home_page.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      final logger = AppLogger.instance;
      final previousFlutterErrorHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        logger.fatal(
          'runtime.flutter',
          'Uncaught Flutter framework error',
          code: 'flutter_uncaught_error',
          error: details.exception,
          stackTrace: details.stack,
          data: <String, Object?>{
            'library': details.library,
            'context': details.context?.toDescription(),
          },
        );
        previousFlutterErrorHandler?.call(details);
      };
      PlatformDispatcher.instance.onError = (error, stackTrace) {
        logger.fatal(
          'runtime.platform',
          'Uncaught platform dispatcher error',
          code: 'platform_uncaught_error',
          error: error,
          stackTrace: stackTrace,
        );
        return true;
      };

      logger.info('app.lifecycle', 'Application process started');
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      runApp(const GardendlessLoaderApp());
    },
    (error, stackTrace) {
      AppLogger.instance.fatal(
        'runtime.zone',
        'Uncaught asynchronous error',
        code: 'zone_uncaught_error',
        error: error,
        stackTrace: stackTrace,
      );
    },
  );
}

class GardendlessLoaderApp extends StatefulWidget {
  const GardendlessLoaderApp({super.key});

  @override
  State<GardendlessLoaderApp> createState() => _GardendlessLoaderAppState();
}

class _GardendlessLoaderAppState extends State<GardendlessLoaderApp> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AppController();
    unawaited(_controller.initialize().then((_) {
      if (mounted && _controller.initialized) {
        unawaited(_controller.refreshAboutContent());
        unawaited(_controller.refreshAnnouncement());
      }
    }));
  }

  @override
  void dispose() {
    AppLogger.instance.info('app.lifecycle', 'Application widget disposed');
    unawaited(AppLogger.instance.flush());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GardendlessLoader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0a84ff)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff0a84ff),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomePage(controller: _controller),
    );
  }
}
