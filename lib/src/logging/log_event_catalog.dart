import 'app_logger.dart';

const defaultLogEventSchemas = <String, LogEventSchema>{
  'app_session_started': LogEventSchema(
    contextFields: <String, LogContextValueType>{
      'appVersion': LogContextValueType.text,
      'platform': LogContextValueType.text,
      'osVersion': LogContextValueType.text,
    },
  ),
  'app_lifecycle_changed': LogEventSchema(
    contextFields: <String, LogContextValueType>{
      'state': LogContextValueType.text,
    },
  ),
  'resource_import_picker_finished': LogEventSchema(
    contextFields: <String, LogContextValueType>{
      'stage': LogContextValueType.text,
    },
  ),
  'resource_import_progress': LogEventSchema(
    contextFields: <String, LogContextValueType>{
      'stage': LogContextValueType.text,
      'processedBytes': LogContextValueType.integer,
      'totalBytes': LogContextValueType.integer,
      'processedFiles': LogContextValueType.integer,
      'totalFiles': LogContextValueType.integer,
    },
  ),
  'resource_import_finished': LogEventSchema(
    contextFields: <String, LogContextValueType>{
      'stage': LogContextValueType.text,
      'activeSlot': LogContextValueType.text,
      'fileCount': LogContextValueType.integer,
      'totalBytes': LogContextValueType.integer,
    },
  ),
  'game_host_launch_finished': LogEventSchema(
    contextFields: <String, LogContextValueType>{
      'platform': LogContextValueType.text,
      'gameVersion': LogContextValueType.text,
    },
  ),
  'javascript_uncaught_error': LogEventSchema(
    contextFields: <String, LogContextValueType>{
      'page': LogContextValueType.path,
      'line': LogContextValueType.integer,
      'column': LogContextValueType.integer,
    },
  ),
  'javascript_unhandled_rejection': LogEventSchema(
    contextFields: <String, LogContextValueType>{
      'page': LogContextValueType.path,
    },
  ),
  'javascript_console': LogEventSchema(
    contextFields: <String, LogContextValueType>{
      'consoleLevel': LogContextValueType.text,
      'line': LogContextValueType.integer,
      'page': LogContextValueType.path,
    },
  ),
};

const userErrorCatalog = <String, UserLogError>{
  'app_initialization_failed': UserLogError(
    title: '应用初始化失败',
    action: '请重启应用；如果问题持续，请复制诊断摘要。',
  ),
  'import_zip_invalid': UserLogError(
    title: 'ZIP 文件无效',
    action: '请选择包含完整 docs 资源目录的 ZIP。',
  ),
  'import_extract_failed': UserLogError(
    title: '资源解压失败',
    action: '请重新下载资源包并确认设备存储空间充足。',
  ),
  'game_host_launch_failed': UserLogError(
    title: '游戏启动失败',
    action: '请检查资源完整性后重试。',
  ),
  'webview_render_process_gone': UserLogError(
    title: '游戏渲染进程已退出',
    action: '请返回启动器后重新进入游戏。',
  ),
  'log_write_failed': UserLogError(
    title: '日志持久化不可用',
    action: '应用仍可继续使用，但本次诊断信息可能不完整。',
  ),
};

class UserLogError {
  const UserLogError({required this.title, required this.action});

  final String title;
  final String action;
}
