import 'package:flutter/material.dart';

import 'src/app_controller.dart';
import 'src/ui/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GardendlessLoaderApp());
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
    _controller.initialize().then((_) {
      if (mounted && _controller.initialized) {
        _controller.refreshAnnouncement();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GardendlessLoader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2c6f4f)),
        useMaterial3: true,
      ),
      home: HomePage(controller: _controller),
    );
  }
}
