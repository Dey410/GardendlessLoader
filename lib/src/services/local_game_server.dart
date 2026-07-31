import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../constants.dart';
import '../models.dart';
import 'app_logger.dart';

class LocalGameServer {
  LocalGameServer({AppLogger? logger}) : _logger = logger ?? AppLogger.instance;

  final AppLogger _logger;
  HttpServer? _server;
  Directory? _root;
  ServerStatus _status = ServerStatus.stopped;
  String? _lastError;

  ServerStatus get status => _status;
  bool get isRunning => _server != null;
  String? get lastError => _lastError;

  Future<void> start({required Directory root}) async {
    final operationId = _logger.nextOperationId('server-start');
    if (_server != null) {
      _root = root;
      _logger.debug(
        'server.lifecycle',
        'Server already running; updated resource root',
        operationId: operationId,
        data: <String, Object?>{'root': root.path},
      );
      return;
    }

    _status = ServerStatus.starting;
    _root = root;
    _logger.info(
      'server.lifecycle',
      'Starting local game server',
      operationId: operationId,
      data: <String, Object?>{
        'host': localServerHost,
        'port': localServerPort,
        'root': root.path,
      },
    );
    try {
      _server = await _bindWithRetry(operationId: operationId);
      _server!.listen(
        _handleRequest,
        onError: (Object error, StackTrace stackTrace) {
          _logger.error(
            'server.listener',
            'Local server listener reported an error',
            operationId: operationId,
            code: 'server_listener_error',
            error: error,
            stackTrace: stackTrace,
          );
        },
      );
      _status = ServerStatus.running;
      _lastError = null;
      _logger.info(
        'server.lifecycle',
        'Local game server started',
        operationId: operationId,
        data: <String, Object?>{
          'host': localServerHost,
          'port': localServerPort,
        },
      );
    } catch (error, stackTrace) {
      _server = null;
      _status = ServerStatus.failed;
      _lastError = error.toString();
      _logger.error(
        'server.lifecycle',
        'Unable to start local game server',
        operationId: operationId,
        code: 'server_start_failed',
        error: error,
        stackTrace: stackTrace,
        data: <String, Object?>{
          'host': localServerHost,
          'port': localServerPort,
          'root': root.path,
        },
      );
      rethrow;
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _status = ServerStatus.stopped;
    if (server != null) {
      try {
        await server.close(force: true);
        _logger.info('server.lifecycle', 'Local game server stopped');
      } catch (error, stackTrace) {
        _logger.warning(
          'server.lifecycle',
          'Local game server close failed',
          code: 'server_stop_failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> selfCheck({required Directory root}) async {
    final operationId = _logger.nextOperationId('server-self-check');
    final stopwatch = Stopwatch()..start();
    _logger.info(
      'server.self_check',
      'Local server self-check started',
      operationId: operationId,
      data: <String, Object?>{'root': root.path},
    );
    try {
      await start(root: root);

      final checks = <_SelfCheckRequest>[
        const _SelfCheckRequest('/index.html', expectedMime: 'text/html'),
        const _SelfCheckRequest(
          '/src/settings.json',
          expectedMime: 'application/json',
        ),
        const _SelfCheckRequest(
          '/src/import-map.json',
          expectedMime: 'application/json',
        ),
        const _SelfCheckRequest(
          '/cocos-js/cc.js',
          expectedMime: 'application/javascript',
        ),
      ];

      final wasm = await _firstWasm(root);
      if (wasm != null) {
        checks.add(_SelfCheckRequest(wasm, expectedMime: 'application/wasm'));
      }

      final client = HttpClient();
      try {
        for (final check in checks) {
          final request =
              await client.getUrl(Uri.parse('$localOrigin${check.path}'));
          final response = await request.close();
          await response.drain<void>();
          final mimeType = response.headers.contentType?.mimeType;
          _logger.debug(
            'server.self_check',
            'Self-check response received',
            operationId: operationId,
            data: <String, Object?>{
              'path': check.path,
              'statusCode': response.statusCode,
              'mimeType': mimeType,
              'expectedMimeType': check.expectedMime,
            },
          );
          if (response.statusCode != HttpStatus.ok) {
            throw StateError(
              '自检失败 ${check.path}: HTTP ${response.statusCode}',
            );
          }
          if (mimeType != check.expectedMime) {
            throw StateError('自检 MIME 错误 ${check.path}: $mimeType');
          }
        }
      } finally {
        client.close(force: true);
      }
      stopwatch.stop();
      _logger.info(
        'server.self_check',
        'Local server self-check completed',
        operationId: operationId,
        data: <String, Object?>{
          'durationMs': stopwatch.elapsedMilliseconds,
          'requestCount': checks.length,
        },
      );
    } catch (error, stackTrace) {
      stopwatch.stop();
      _logger.error(
        'server.self_check',
        'Local server self-check failed',
        operationId: operationId,
        code: 'server_self_check_failed',
        error: error,
        stackTrace: stackTrace,
        data: <String, Object?>{
          'durationMs': stopwatch.elapsedMilliseconds,
          'root': root.path,
        },
      );
      rethrow;
    }
  }

  Future<HttpServer> _bindWithRetry({required String operationId}) async {
    try {
      return await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        localServerPort,
        shared: false,
      );
    } on SocketException catch (error, stackTrace) {
      _logger.warning(
        'server.bind',
        'Initial local server bind failed; retrying once',
        operationId: operationId,
        code: 'server_bind_retry',
        error: error,
        stackTrace: stackTrace,
        data: <String, Object?>{
          'host': localServerHost,
          'port': localServerPort,
          'retryDelayMs': 250,
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      return HttpServer.bind(
        InternetAddress.loopbackIPv4,
        localServerPort,
        shared: false,
      );
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final stopwatch = Stopwatch()..start();
    try {
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
      request.response.headers
          .set(HttpHeaders.contentTypeHeader, _mimeFor(file.path));
      request.response.contentLength = await file.length();

      if (request.method == 'HEAD') {
        await request.response.close();
        return;
      }

      await request.response.addStream(file.openRead());
      await request.response.close();
    } catch (error, stackTrace) {
      _logger.error(
        'server.request',
        'Local server request failed',
        code: 'server_request_failed',
        error: error,
        stackTrace: stackTrace,
        data: <String, Object?>{
          'method': request.method,
          'path': request.uri.path,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {
        // The response may already be closed; the original error is logged.
      }
    }
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
      _logger.warning(
        'server.request',
        'Rejected request path outside resource root',
        code: 'server_path_traversal_rejected',
        data: <String, Object?>{'requestPath': uri.path},
      );
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
        final relative =
            p.relative(entity.path, from: root.path).replaceAll('\\', '/');
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
