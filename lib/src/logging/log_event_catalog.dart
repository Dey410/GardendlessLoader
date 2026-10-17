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
    action: '请重启加载器；仍失败请检查设备剩余空间，并在「日志」页复制诊断反馈。',
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
    action: '请到「资源」页重新导入游戏资源。',
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
    action: '请选择包含完整 docs 资源目录的游戏资源 ZIP。',
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
    action: '请到「资源」页重新导入游戏资源后再试；仍失败请在「日志」页复制诊断反馈。',
    recoverable: true,
  ),
  'webview_page_load_failed': UserLogError(
    category: 'game.webview',
    level: LogLevel.error,
    title: '游戏页面加载失败',
    action: '请到「资源」页重新导入游戏资源后再开始游戏。',
    recoverable: true,
  ),
  'webview_render_process_gone': UserLogError(
    category: 'game.webview',
    level: LogLevel.error,
    title: '游戏渲染进程已退出',
    action: '通常是内存不足，请关闭其他应用后重新开始游戏。',
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
  'dart_unhandled_error': UserLogError(
    category: 'app.lifecycle',
    level: LogLevel.error,
    title: '加载器内部错误',
    action: '请重启加载器；若反复出现，请在「日志」页复制诊断反馈。',
    recoverable: true,
  ),
  'flutter_framework_error': UserLogError(
    category: 'app.lifecycle',
    level: LogLevel.error,
    title: '加载器界面错误',
    action: '请重启加载器；若反复出现，请在「日志」页复制诊断反馈。',
    recoverable: true,
  ),
  'update_check_failed': UserLogError(
    category: 'app.update',
    level: LogLevel.warn,
    title: '更新检查失败',
    action: '请检查网络连接，稍后点右上角的刷新图标重试。',
    recoverable: true,
  ),
  'import_busy': UserLogError(
    category: 'resource.import',
    level: LogLevel.warn,
    title: '已有导入正在进行',
    action: '请等当前导入结束后再试。',
    recoverable: true,
  ),
  'zip_import_busy': UserLogError(
    category: 'resource.import',
    level: LogLevel.warn,
    title: '已有导入正在进行',
    action: '请等当前导入结束后再试。',
    recoverable: true,
  ),
  'invalid_import_target': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: '导入目标槽状态异常',
    action: '请重启加载器后重新导入。',
    recoverable: true,
  ),
  'invalid_target_directory': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: '导入目标目录缺失',
    action: '请重启加载器后重新导入。',
    recoverable: true,
  ),
  'platform_unsupported': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: '当前平台不支持导入',
    action: '请在 Android、iOS 或鸿蒙设备上导入游戏资源。',
    recoverable: false,
  ),
  'zip_picker_failed': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: '无法打开文件选择器',
    action: '请重启加载器后再点「导入资源」。',
    recoverable: true,
  ),
  'zip_docs_missing': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: 'ZIP 里没有游戏资源',
    action:
        '请选择 Gardendless 游戏资源 ZIP（里面要有 docs/index.html）；Mod 包请在游戏内的 Mods 页面安装。',
    recoverable: true,
  ),
  'zip_invalid': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: 'ZIP 文件已损坏',
    action: '文件可能没有下载完整，请重新下载资源包后再导入。',
    recoverable: true,
  ),
  'zip_encrypted': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: 'ZIP 已加密',
    action: '请使用未加密的资源包；自己打包时不要设置密码。',
    recoverable: true,
  ),
  'zip_unsupported': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: 'ZIP 格式不受支持',
    action: '请使用官方发布的资源包；自己打包时请用系统自带的压缩功能，不要用 ZIP64 或特殊压缩算法。',
    recoverable: true,
  ),
  'zip_path_unsafe': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: 'ZIP 含有不安全的路径',
    action: '资源包可能被改动过，请从官方渠道重新下载。',
    recoverable: true,
  ),
  'zip_write_failed': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: '无法写入导入文件',
    action: '请清理设备存储空间后重新导入。',
    recoverable: true,
  ),
  'zip_import_failed': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: 'ZIP 导入失败',
    action: '请重新下载资源包，并确认设备剩余空间充足后再导入。',
    recoverable: true,
  ),
  'import_failed': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: '资源导入失败',
    action: '请重新下载资源包，并确认设备剩余空间充足后再导入。',
    recoverable: true,
  ),
  'import_interrupted': UserLogError(
    category: 'resource.import',
    level: LogLevel.warn,
    title: '上次导入意外中断',
    action: '请到「资源」页重新导入，导入时让加载器保持在前台。',
    recoverable: true,
  ),
  'legacy_migration_failed': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: '旧版资源迁移失败',
    action: '请到「资源」页重新导入游戏资源。',
    recoverable: true,
  ),
  'old_slot_cleanup_failed': UserLogError(
    category: 'resource.import',
    level: LogLevel.warn,
    title: '旧资源清理失败',
    action: '不影响游戏；请确认设备剩余空间充足，下次启动会自动重试。',
    recoverable: true,
  ),
  'candidate_recovery_failed': UserLogError(
    category: 'resource.import',
    level: LogLevel.warn,
    title: '未完成的导入已作废',
    action: '请到「资源」页重新导入游戏资源。',
    recoverable: true,
  ),
  'resource_missing': UserLogError(
    category: 'resource.validation',
    level: LogLevel.warn,
    title: '尚未导入游戏资源',
    action: '请到「资源」页导入游戏资源 ZIP。',
    recoverable: true,
  ),
  'resource_validation_failed': UserLogError(
    category: 'game.host',
    level: LogLevel.error,
    title: '资源校验未通过',
    action: '请到「资源」页重新导入游戏资源。',
    recoverable: true,
  ),
  'validation_failed': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: '资源校验失败',
    action: '请重新下载完整的游戏资源包后再导入。',
    recoverable: true,
  ),
  'host_abi_unsupported': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: '资源包需要新版加载器',
    action: '请点右上角的刷新图标检查更新，升级加载器后重新导入。',
    recoverable: true,
  ),
  'package_metadata_invalid': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: '资源包内容与索引不一致',
    action: '资源包可能下载不完整或被改动过，请重新下载官方资源包。',
    recoverable: true,
  ),
  'resource_path_unsafe': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: '资源包含不安全的路径',
    action: '资源包可能被改动过，请从官方渠道重新下载。',
    recoverable: true,
  ),
  'missing_required_directory': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: '资源缺少必要目录',
    action: '请选择完整的游戏资源 ZIP，不要只压缩其中一部分文件。',
    recoverable: true,
  ),
  'missing_required_file': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: '资源缺少必要文件',
    action: '请选择完整的游戏资源 ZIP，不要只压缩其中一部分文件。',
    recoverable: true,
  ),
  'title_fingerprint_mismatch': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: '不是 Gardendless 资源',
    action: '请选择 PvZ2 Gardendless 的 Web 资源包。',
    recoverable: true,
  ),
  'index_fingerprint_mismatch': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: '不是 Gardendless 资源',
    action: '请选择 PvZ2 Gardendless 的 Web 资源包。',
    recoverable: true,
  ),
  'settings_json_invalid': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: '游戏配置文件损坏',
    action: '请重新下载完整的游戏资源包后再导入。',
    recoverable: true,
  ),
  'settings_cocos_config_missing': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: '游戏配置文件不完整',
    action: '请重新下载完整的游戏资源包后再导入。',
    recoverable: true,
  ),
  'gp_next_incompatible': UserLogError(
    category: 'resource.validation',
    level: LogLevel.warn,
    title: 'GP-Next 不兼容',
    action: '请点右上角的刷新图标检查更新并升级加载器，或换用加载器支持的 GP-Next 资源包。',
    recoverable: true,
  ),
  'webview_unsupported': UserLogError(
    category: 'game.host',
    level: LogLevel.error,
    title: '系统 WebView 版本过旧',
    action: '请在应用商店更新 Android System WebView（或 Chrome）后重新开始游戏。',
    recoverable: true,
  ),
  'game_host_launch_busy': UserLogError(
    category: 'game.host',
    level: LogLevel.warn,
    title: '游戏正在启动',
    action: '请稍候，不要重复点「开始游戏」。',
    recoverable: true,
  ),
  'game_host_unavailable': UserLogError(
    category: 'game.host',
    level: LogLevel.error,
    title: '游戏宿主不可用',
    action: '请重启加载器后再开始游戏。',
    recoverable: true,
  ),
  'invalid_game_session': UserLogError(
    category: 'game.host',
    level: LogLevel.error,
    title: '游戏会话无效',
    action: '请重启加载器后再开始游戏。',
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
