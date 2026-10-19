import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../constants.dart';

class HttpTextResponse {
  const HttpTextResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

Future<HttpTextResponse> loadHttpText(
  Uri uri,
  Duration timeout,
  int maxBytes,
) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    return await (() async {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, appDisplayName);
      final response = await request.close();
      if (response.contentLength > maxBytes) {
        throw const FormatException('HTTP response is too large');
      }
      final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) {
        if (buffer.length + chunk.length > maxBytes) {
          throw const FormatException('HTTP response is too large');
        }
        buffer.addAll(chunk);
        return buffer;
      });
      return HttpTextResponse(
        statusCode: response.statusCode,
        body: utf8.decode(bytes),
      );
    })()
        .timeout(timeout);
  } finally {
    client.close(force: true);
  }
}
