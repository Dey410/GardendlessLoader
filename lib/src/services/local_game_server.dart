import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../constants.dart';
import '../models.dart';

class LocalGameServer {
  HttpServer? _server;
  Directory? _root;
  ServerStatus _status = ServerStatus.stopped;
  String? _lastError;

  ServerStatus get status => _status;
  bool get isRunning => _server != null;
  String? get lastError => _lastError;

  Future<void> start({required Directory root}) async {
    if (_server != null) {
      _root = root;
      return;
    }

    _status = ServerStatus.starting;
    _root = root;
    try {
      _server = await _bindWithRetry();
      _server!.listen(_handleRequest, onError: (_) {});
      _status = ServerStatus.running;
      _lastError = null;
    } catch (error) {
      _server = null;
      _status = ServerStatus.failed;
      _lastError = error.toString();
      rethrow;
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _status = ServerStatus.stopped;
    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<void> selfCheck({required Directory root}) async {
    await start(root: root);

    final checks = <_SelfCheckRequest>[
      const _SelfCheckRequest('/index.html', expectedMime: 'text/html'),
      const _SelfCheckRequest('/src/settings.json', expectedMime: 'application/json'),
      const _SelfCheckRequest('/src/import-map.json', expectedMime: 'application/json'),
      const _SelfCheckRequest('/cocos-js/cc.js', expectedMime: 'application/javascript'),
    ];

    final wasm = await _firstWasm(root);
    if (wasm != null) {
      checks.add(_SelfCheckRequest(wasm, expectedMime: 'application/wasm'));
    }

    final client = HttpClient();
    try {
      for (final check in checks) {
        final request = await client.getUrl(Uri.parse('$localOrigin${check.path}'));
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode != HttpStatus.ok) {
          throw StateError('自检失败 ${check.path}: HTTP ${response.statusCode}');
        }
        final mimeType = response.headers.contentType?.mimeType;
        if (mimeType != check.expectedMime) {
          throw StateError('自检 MIME 错误 ${check.path}: $mimeType');
        }
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<HttpServer> _bindWithRetry() async {
    try {
      return await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        localServerPort,
        shared: false,
      );
    } on SocketException {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      return HttpServer.bind(
        InternetAddress.loopbackIPv4,
        localServerPort,
        shared: false,
      );
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      request.response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      await request.response.close();
      return;
    }

    final root = _root;
    if (root == null) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }

    final file = await _resolveRequestFile(root, request.uri);
    if (file == null || !await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final type = await FileSystemEntity.type(file.path, followLinks: true);
    if (type != FileSystemEntityType.file) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    request.response.headers.set(HttpHeaders.contentTypeHeader, _mimeFor(file.path));
    request.response.contentLength = await file.length();

    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }

    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  Future<File?> _resolveRequestFile(Directory root, Uri uri) async {
    final normalizedRoot = await _canonicalDirectory(root);
    final relativePath = uri.path == '/'
        ? 'index.html'
        : p.joinAll(uri.pathSegments.map(Uri.decodeComponent));
    final candidate = File(p.normalize(p.join(normalizedRoot, relativePath)));

    final normalizedCandidate = await candidate.exists()
        ? await candidate.resolveSymbolicLinks()
        : p.normalize(candidate.absolute.path);
    if (!_isInside(normalizedRoot, normalizedCandidate)) {
      return null;
    }

    return File(normalizedCandidate);
  }

  Future<String> _canonicalDirectory(Directory directory) async {
    if (await directory.exists()) {
      return p.normalize(await directory.resolveSymbolicLinks());
    }
    return p.normalize(directory.absolute.path);
  }

  bool _isInside(String root, String child) {
    final normalizedRoot = p.normalize(root);
    final normalizedChild = p.normalize(child);
    return p.equals(normalizedRoot, normalizedChild) ||
        p.isWithin(normalizedRoot, normalizedChild);
  }

  String _mimeFor(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.html':
        return 'text/html; charset=utf-8';
      case '.js':
        return 'application/javascript';
      case '.json':
        return 'application/json';
      case '.wasm':
        return 'application/wasm';
      case '.css':
        return 'text/css';
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.webp':
        return 'image/webp';
      case '.mp3':
        return 'audio/mpeg';
      case '.bin':
        return 'application/octet-stream';
      default:
        return 'application/octet-stream';
    }
  }

  Future<String?> _firstWasm(Directory root) async {
    if (!await root.exists()) {
      return null;
    }

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File && p.extension(entity.path).toLowerCase() == '.wasm') {
        final relative = p.relative(entity.path, from: root.path).replaceAll('\\', '/');
        return '/$relative';
      }
    }
    return null;
  }
}

class _SelfCheckRequest {
  const _SelfCheckRequest(this.path, {required this.expectedMime});

  final String path;
  final String expectedMime;
}
