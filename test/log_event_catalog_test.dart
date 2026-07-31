import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/logging/log_event_catalog.dart';

void main() {
  test('first-phase error catalog contains complete user-facing metadata', () {
    const requiredCodes = <String>{
      'app_initialization_failed',
      'previous_run_unclean_shutdown',
      'path_root_unavailable',
      'path_permission_denied',
      'manifest_json_invalid',
      'manifest_write_failed',
      'import_zip_invalid',
      'import_extract_failed',
      'import_transaction_recovery_failed',
      'resource_missing_index',
      'resource_missing_import_map',
      'resource_path_forbidden',
      'resource_file_not_found',
      'resource_read_failed',
      'resource_mime_mismatch',
      'game_host_launch_failed',
      'webview_page_load_failed',
      'webview_render_process_gone',
      'javascript_uncaught_error',
      'javascript_unhandled_rejection',
      'bridge_message_invalid',
      'bridge_call_failed',
      'log_context_rejected',
      'log_write_failed',
      'log_flush_timeout',
      'log_rotation_failed',
    };

    expect(userErrorCatalog.keys, containsAll(requiredCodes));
    for (final code in requiredCodes) {
      final metadata = userErrorCatalog[code]!;
      expect(metadata.category, isNotEmpty, reason: code);
      expect(metadata.title, isNotEmpty, reason: code);
      expect(metadata.action, isNotEmpty, reason: code);
    }
  });
}
