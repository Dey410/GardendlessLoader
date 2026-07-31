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
  'app_initialization_stage_changed': LogEventSchema(
    contextFields: <String, LogContextValueType>{
      'stage': LogContextValueType.text,
    },
  ),
  'import_transaction_recovery_started': LogEventSchema(
    contextFields: <String, LogContextValueType>{
      'transactionState': LogContextValueType.text,
      'targetSlot': LogContextValueType.text,
    },
  ),
  'import_transaction_recovery_finished': LogEventSchema(
    contextFields: <String, LogContextValueType>{
      'recoveryAction': LogContextValueType.text,
      'activeSlot': LogContextValueType.text,
      'currentResourceUsable': LogContextValueType.boolean,
    },
  ),
  'resource_import_target_prepared': LogEventSchema(
    contextFields: <String, LogContextValueType>{
      'targetSlot': LogContextValueType.text,
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
  'resource_validation_finished': LogEventSchema(
    contextFields: <String, LogContextValueType>{
      'stage': LogContextValueType.text,
      'fileCount': LogContextValueType.integer,
      'totalBytes': LogContextValueType.integer,
      'buildProfile': LogContextValueType.text,
      'gpNextVersion': LogContextValueType.text,
    },
  ),
  'resource_slot_activated': LogEventSchema(
    contextFields: <String, LogContextValueType>{
      'activeSlot': LogContextValueType.text,
      'cleanupDeferred': LogContextValueType.boolean,
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
    category: 'app.lifecycle',
    level: LogLevel.fatal,
    title: '应用初始化失败',
    action: '请重启应用；如果问题持续，请复制诊断摘要。',
    recoverable: false,
  ),
  'previous_run_unclean_shutdown': UserLogError(
    category: 'app.lifecycle',
    level: LogLevel.warn,
    title: '上次运行未正常结束',
    action: '可继续使用；若反复出现，请复制诊断摘要。',
    recoverable: true,
  ),
  'path_root_unavailable': UserLogError(
    category: 'storage.path',
    level: LogLevel.error,
    title: '应用目录不可用',
    action: '请检查设备存储状态后重启应用。',
    recoverable: false,
  ),
  'path_permission_denied': UserLogError(
    category: 'storage.path',
    level: LogLevel.error,
    title: '没有存储访问权限',
    action: '请在系统设置中允许所需权限。',
    recoverable: true,
  ),
  'manifest_json_invalid': UserLogError(
    category: 'resource.manifest',
    level: LogLevel.error,
    title: '资源清单已损坏',
    action: '请重新导入游戏资源。',
    recoverable: true,
  ),
  'manifest_write_failed': UserLogError(
    category: 'resource.manifest',
    level: LogLevel.error,
    title: '资源状态保存失败',
    action: '请检查剩余空间后重试。',
    recoverable: true,
  ),
  'import_zip_invalid': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: 'ZIP 文件无效',
    action: '请选择包含完整 docs 资源目录的 ZIP。',
    recoverable: true,
  ),
  'import_extract_failed': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: '资源解压失败',
    action: '请重新下载资源包并确认设备存储空间充足。',
    recoverable: true,
  ),
  'import_transaction_recovery_failed': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: '未完成导入恢复失败',
    action: '请重新导入资源；当前可用资源不会被主动删除。',
    recoverable: true,
  ),
  'resource_missing_index': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: '缺少游戏入口文件',
    action: '请选择包含 index.html 的完整资源包。',
    recoverable: true,
  ),
  'resource_missing_import_map': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: '缺少模块映射文件',
    action: '请重新下载完整游戏资源。',
    recoverable: true,
  ),
  'resource_path_forbidden': UserLogError(
    category: 'resource.handler',
    level: LogLevel.warn,
    title: '资源路径被安全策略拒绝',
    action: '请检查资源包内的引用路径。',
    recoverable: true,
  ),
  'resource_file_not_found': UserLogError(
    category: 'resource.handler',
    level: LogLevel.warn,
    title: '游戏资源文件不存在',
    action: '请校验或重新导入资源。',
    recoverable: true,
  ),
  'resource_read_failed': UserLogError(
    category: 'resource.handler',
    level: LogLevel.error,
    title: '游戏资源读取失败',
    action: '请检查存储状态并重新导入资源。',
    recoverable: true,
  ),
  'resource_mime_mismatch': UserLogError(
    category: 'resource.handler',
    level: LogLevel.warn,
    title: '资源类型无法识别',
    action: '请检查资源文件扩展名和内容类型。',
    recoverable: true,
  ),
  'game_host_launch_failed': UserLogError(
    category: 'game.host',
    level: LogLevel.error,
    title: '游戏启动失败',
    action: '请检查资源完整性后重试。',
    recoverable: true,
  ),
  'webview_page_load_failed': UserLogError(
    category: 'game.webview',
    level: LogLevel.error,
    title: '游戏页面加载失败',
    action: '请返回启动器，校验资源后重试。',
    recoverable: true,
  ),
  'webview_render_process_gone': UserLogError(
    category: 'game.webview',
    level: LogLevel.error,
    title: '游戏渲染进程已退出',
    action: '请返回启动器后重新进入游戏。',
    recoverable: true,
  ),
  'javascript_uncaught_error': UserLogError(
    category: 'game.javascript',
    level: LogLevel.error,
    title: '游戏脚本发生异常',
    action: '请复制诊断摘要并反馈给资源作者。',
    recoverable: true,
  ),
  'javascript_unhandled_rejection': UserLogError(
    category: 'game.javascript',
    level: LogLevel.error,
    title: '游戏异步脚本发生异常',
    action: '请复制诊断摘要并反馈给资源作者。',
    recoverable: true,
  ),
  'bridge_message_invalid': UserLogError(
    category: 'game.bridge',
    level: LogLevel.warn,
    title: '游戏桥接请求无效',
    action: '请更新或更换兼容的游戏资源。',
    recoverable: true,
  ),
  'bridge_call_failed': UserLogError(
    category: 'game.bridge',
    level: LogLevel.error,
    title: '游戏桥接调用失败',
    action: '请重试；若持续失败，请复制诊断摘要。',
    recoverable: true,
  ),
  'log_context_rejected': UserLogError(
    category: 'logging.validation',
    level: LogLevel.warn,
    title: '部分诊断字段已被拒绝',
    action: '应用可继续运行，敏感或无效字段不会写入日志。',
    recoverable: true,
  ),
  'log_write_failed': UserLogError(
    category: 'logging.storage',
    level: LogLevel.error,
    title: '日志持久化不可用',
    action: '应用仍可继续使用，但本次诊断信息可能不完整。',
    recoverable: true,
  ),
  'log_flush_timeout': UserLogError(
    category: 'logging.storage',
    level: LogLevel.warn,
    title: '日志写入等待超时',
    action: '应用可继续运行，最后几条日志可能尚未落盘。',
    recoverable: true,
  ),
  'log_rotation_failed': UserLogError(
    category: 'logging.storage',
    level: LogLevel.error,
    title: '日志轮转失败',
    action: '请删除历史日志或释放设备存储空间。',
    recoverable: true,
  ),
};

class UserLogError {
  const UserLogError({
    required this.category,
    required this.level,
    required this.title,
    required this.action,
    required this.recoverable,
  });

  final String category;
  final LogLevel level;
  final String title;
  final String action;
  final bool recoverable;
}
