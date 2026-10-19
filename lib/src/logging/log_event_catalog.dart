import '../l10n/app_strings.dart';
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
  'resource_import_started': LogEventSchema(
    contextFields: <String, LogContextValueType>{
      'source': LogContextValueType.text,
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
    title: LocalizedText(
      '应用初始化失败',
      'App failed to start',
    ),
    action: LocalizedText(
      '请重启加载器；仍失败请检查设备剩余空间，并在「日志」页复制诊断反馈。',
      'Restart the loader. If it still fails, check free storage and copy the diagnostics from the Logs page.',
    ),
    recoverable: false,
  ),
  'previous_run_unclean_shutdown': UserLogError(
    category: 'app.lifecycle',
    level: LogLevel.warn,
    title: LocalizedText(
      '上次运行未正常结束',
      'The last run did not exit cleanly',
    ),
    action: LocalizedText(
      '可继续使用；若反复出现，请复制诊断摘要。',
      'You can keep using the app; if this keeps happening, copy the diagnostic summary.',
    ),
    recoverable: true,
  ),
  'path_root_unavailable': UserLogError(
    category: 'storage.path',
    level: LogLevel.error,
    title: LocalizedText(
      '应用目录不可用',
      'App folder unavailable',
    ),
    action: LocalizedText(
      '请检查设备存储状态后重启应用。',
      'Check the device storage, then restart the app.',
    ),
    recoverable: false,
  ),
  'path_permission_denied': UserLogError(
    category: 'storage.path',
    level: LogLevel.error,
    title: LocalizedText(
      '没有存储访问权限',
      'No storage permission',
    ),
    action: LocalizedText(
      '请在系统设置中允许所需权限。',
      'Allow the required permission in system settings.',
    ),
    recoverable: true,
  ),
  'manifest_json_invalid': UserLogError(
    category: 'resource.manifest',
    level: LogLevel.error,
    title: LocalizedText(
      '资源清单已损坏',
      'Resource manifest is corrupted',
    ),
    action: LocalizedText(
      '请到「资源」页重新导入游戏资源。',
      'Re-import the game resources on the Resources page.',
    ),
    recoverable: true,
  ),
  'manifest_write_failed': UserLogError(
    category: 'resource.manifest',
    level: LogLevel.error,
    title: LocalizedText(
      '资源状态保存失败',
      'Could not save resource state',
    ),
    action: LocalizedText(
      '请检查剩余空间后重试。',
      'Check free storage and try again.',
    ),
    recoverable: true,
  ),
  'import_zip_invalid': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: LocalizedText(
      'ZIP 文件无效',
      'Invalid ZIP file',
    ),
    action: LocalizedText(
      '请选择包含完整 docs 资源目录的游戏资源 ZIP。',
      'Choose a game resource ZIP that contains the complete docs folder.',
    ),
    recoverable: true,
  ),
  'import_extract_failed': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: LocalizedText(
      '资源解压失败',
      'Could not extract resources',
    ),
    action: LocalizedText(
      '请重新下载资源包并确认设备存储空间充足。',
      'Download the resource package again and make sure there is enough free storage.',
    ),
    recoverable: true,
  ),
  'import_transaction_recovery_failed': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: LocalizedText(
      '未完成导入恢复失败',
      'Could not recover the unfinished import',
    ),
    action: LocalizedText(
      '请重新导入资源；当前可用资源不会被主动删除。',
      'Import the resources again; the current resources are not deleted.',
    ),
    recoverable: true,
  ),
  'resource_missing_index': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: LocalizedText(
      '缺少游戏入口文件',
      'Game entry file missing',
    ),
    action: LocalizedText(
      '请选择包含 index.html 的完整资源包。',
      'Choose a complete resource package that contains index.html.',
    ),
    recoverable: true,
  ),
  'resource_missing_import_map': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: LocalizedText(
      '缺少模块映射文件',
      'Module map file missing',
    ),
    action: LocalizedText(
      '请重新下载完整游戏资源。',
      'Download the complete game resources again.',
    ),
    recoverable: true,
  ),
  'resource_path_forbidden': UserLogError(
    category: 'resource.handler',
    level: LogLevel.warn,
    title: LocalizedText(
      '资源路径被安全策略拒绝',
      'Resource path blocked by the security policy',
    ),
    action: LocalizedText(
      '请检查资源包内的引用路径。',
      'Check the paths referenced inside the resource package.',
    ),
    recoverable: true,
  ),
  'resource_file_not_found': UserLogError(
    category: 'resource.handler',
    level: LogLevel.warn,
    title: LocalizedText(
      '游戏资源文件不存在',
      'Game resource file not found',
    ),
    action: LocalizedText(
      '请校验或重新导入资源。',
      'Validate or re-import the resources.',
    ),
    recoverable: true,
  ),
  'resource_read_failed': UserLogError(
    category: 'resource.handler',
    level: LogLevel.error,
    title: LocalizedText(
      '游戏资源读取失败',
      'Could not read game resources',
    ),
    action: LocalizedText(
      '请检查存储状态并重新导入资源。',
      'Check the storage, then re-import the resources.',
    ),
    recoverable: true,
  ),
  'resource_mime_mismatch': UserLogError(
    category: 'resource.handler',
    level: LogLevel.warn,
    title: LocalizedText(
      '资源类型无法识别',
      'Unrecognized resource type',
    ),
    action: LocalizedText(
      '请检查资源文件扩展名和内容类型。',
      'Check the resource file extensions and content types.',
    ),
    recoverable: true,
  ),
  'game_host_launch_failed': UserLogError(
    category: 'game.host',
    level: LogLevel.error,
    title: LocalizedText(
      '游戏启动失败',
      'Game failed to start',
    ),
    action: LocalizedText(
      '请到「资源」页重新导入游戏资源后再试；仍失败请在「日志」页复制诊断反馈。',
      'Re-import the game resources on the Resources page and try again; if it still fails, copy the diagnostics from the Logs page.',
    ),
    recoverable: true,
  ),
  'webview_page_load_failed': UserLogError(
    category: 'game.webview',
    level: LogLevel.error,
    title: LocalizedText(
      '游戏页面加载失败',
      'Game page failed to load',
    ),
    action: LocalizedText(
      '请到「资源」页重新导入游戏资源后再开始游戏。',
      'Re-import the game resources on the Resources page, then start the game.',
    ),
    recoverable: true,
  ),
  'webview_render_process_gone': UserLogError(
    category: 'game.webview',
    level: LogLevel.error,
    title: LocalizedText(
      '游戏渲染进程已退出',
      'Game renderer exited',
    ),
    action: LocalizedText(
      '通常是内存不足，请关闭其他应用后重新开始游戏。',
      'This is usually low memory. Close other apps and start the game again.',
    ),
    recoverable: true,
  ),
  'javascript_uncaught_error': UserLogError(
    category: 'game.javascript',
    level: LogLevel.error,
    title: LocalizedText(
      '游戏脚本发生异常',
      'Game script error',
    ),
    action: LocalizedText(
      '请复制诊断摘要并反馈给资源作者。',
      'Copy the diagnostic summary and report it to the resource author.',
    ),
    recoverable: true,
  ),
  'javascript_unhandled_rejection': UserLogError(
    category: 'game.javascript',
    level: LogLevel.error,
    title: LocalizedText(
      '游戏异步脚本发生异常',
      'Game async script error',
    ),
    action: LocalizedText(
      '请复制诊断摘要并反馈给资源作者。',
      'Copy the diagnostic summary and report it to the resource author.',
    ),
    recoverable: true,
  ),
  'bridge_message_invalid': UserLogError(
    category: 'game.bridge',
    level: LogLevel.warn,
    title: LocalizedText(
      '游戏桥接请求无效',
      'Invalid game bridge request',
    ),
    action: LocalizedText(
      '请更新或更换兼容的游戏资源。',
      'Update or switch to compatible game resources.',
    ),
    recoverable: true,
  ),
  'bridge_call_failed': UserLogError(
    category: 'game.bridge',
    level: LogLevel.error,
    title: LocalizedText(
      '游戏桥接调用失败',
      'Game bridge call failed',
    ),
    action: LocalizedText(
      '请重试；若持续失败，请复制诊断摘要。',
      'Try again; if it keeps failing, copy the diagnostic summary.',
    ),
    recoverable: true,
  ),
  'log_context_rejected': UserLogError(
    category: 'logging.validation',
    level: LogLevel.warn,
    title: LocalizedText(
      '部分诊断字段已被拒绝',
      'Some diagnostic fields were rejected',
    ),
    action: LocalizedText(
      '应用可继续运行，敏感或无效字段不会写入日志。',
      'The app keeps running; sensitive or invalid fields are not logged.',
    ),
    recoverable: true,
  ),
  'log_write_failed': UserLogError(
    category: 'logging.storage',
    level: LogLevel.error,
    title: LocalizedText(
      '日志持久化不可用',
      'Log persistence unavailable',
    ),
    action: LocalizedText(
      '应用仍可继续使用，但本次诊断信息可能不完整。',
      'The app still works, but the diagnostics of this run may be incomplete.',
    ),
    recoverable: true,
  ),
  'log_flush_timeout': UserLogError(
    category: 'logging.storage',
    level: LogLevel.warn,
    title: LocalizedText(
      '日志写入等待超时',
      'Log write timed out',
    ),
    action: LocalizedText(
      '应用可继续运行，最后几条日志可能尚未落盘。',
      'The app keeps running; the last few log entries may not be saved yet.',
    ),
    recoverable: true,
  ),
  'log_rotation_failed': UserLogError(
    category: 'logging.storage',
    level: LogLevel.error,
    title: LocalizedText(
      '日志轮转失败',
      'Log rotation failed',
    ),
    action: LocalizedText(
      '请删除历史日志或释放设备存储空间。',
      'Delete the log history or free up device storage.',
    ),
    recoverable: true,
  ),
  'dart_unhandled_error': UserLogError(
    category: 'app.lifecycle',
    level: LogLevel.error,
    title: LocalizedText(
      '加载器内部错误',
      'Loader internal error',
    ),
    action: LocalizedText(
      '请重启加载器；若反复出现，请在「日志」页复制诊断反馈。',
      'Restart the loader; if it keeps happening, copy the diagnostics from the Logs page.',
    ),
    recoverable: true,
  ),
  'flutter_framework_error': UserLogError(
    category: 'app.lifecycle',
    level: LogLevel.error,
    title: LocalizedText(
      '加载器界面错误',
      'Loader interface error',
    ),
    action: LocalizedText(
      '请重启加载器；若反复出现，请在「日志」页复制诊断反馈。',
      'Restart the loader; if it keeps happening, copy the diagnostics from the Logs page.',
    ),
    recoverable: true,
  ),
  'update_check_failed': UserLogError(
    category: 'app.update',
    level: LogLevel.warn,
    title: LocalizedText(
      '更新检查失败',
      'Update check failed',
    ),
    action: LocalizedText(
      '请检查网络连接，稍后点右上角的刷新图标重试。',
      'Check your network connection, then tap the refresh icon at the top right to try again.',
    ),
    recoverable: true,
  ),
  'import_busy': UserLogError(
    category: 'resource.import',
    level: LogLevel.warn,
    title: LocalizedText(
      '已有导入正在进行',
      'An import is already running',
    ),
    action: LocalizedText(
      '请等当前导入结束后再试。',
      'Wait for the current import to finish, then try again.',
    ),
    recoverable: true,
  ),
  'zip_import_busy': UserLogError(
    category: 'resource.import',
    level: LogLevel.warn,
    title: LocalizedText(
      '已有导入正在进行',
      'An import is already running',
    ),
    action: LocalizedText(
      '请等当前导入结束后再试。',
      'Wait for the current import to finish, then try again.',
    ),
    recoverable: true,
  ),
  'invalid_import_target': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: LocalizedText(
      '导入目标槽状态异常',
      'Import slot is in an unexpected state',
    ),
    action: LocalizedText(
      '请重启加载器后重新导入。',
      'Restart the loader and import again.',
    ),
    recoverable: true,
  ),
  'invalid_target_directory': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: LocalizedText(
      '导入目标目录缺失',
      'Import target folder missing',
    ),
    action: LocalizedText(
      '请重启加载器后重新导入。',
      'Restart the loader and import again.',
    ),
    recoverable: true,
  ),
  'platform_unsupported': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: LocalizedText(
      '当前平台不支持导入',
      'Import is not supported on this platform',
    ),
    action: LocalizedText(
      '请在 Android、iOS 或鸿蒙设备上导入游戏资源。',
      'Import game resources on an Android, iOS or HarmonyOS device.',
    ),
    recoverable: false,
  ),
  'zip_picker_failed': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: LocalizedText(
      '无法打开文件选择器',
      'Could not open the file picker',
    ),
    action: LocalizedText(
      '请重启加载器后再点「导入资源」。',
      'Restart the loader, then try importing again.',
    ),
    recoverable: true,
  ),
  'zip_docs_missing': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: LocalizedText(
      'ZIP 里没有游戏资源',
      'No game resources in the ZIP',
    ),
    action: LocalizedText(
      '请选择 Gardendless 游戏资源 ZIP（里面要有 docs/index.html）；Mod 包请在游戏内的 Mods 页面安装。',
      'Choose a Gardendless game resource ZIP (it must contain docs/index.html); install Mod packages from the Mods page in the game.',
    ),
    recoverable: true,
  ),
  'zip_invalid': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: LocalizedText(
      'ZIP 文件已损坏',
      'ZIP file is damaged',
    ),
    action: LocalizedText(
      '文件可能没有下载完整，请重新下载资源包后再导入。',
      'The file may not have finished downloading; download the resource package again and import it.',
    ),
    recoverable: true,
  ),
  'zip_encrypted': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: LocalizedText(
      'ZIP 已加密',
      'ZIP is encrypted',
    ),
    action: LocalizedText(
      '请使用未加密的资源包；自己打包时不要设置密码。',
      'Use an unencrypted resource package; do not set a password when packing it yourself.',
    ),
    recoverable: true,
  ),
  'zip_unsupported': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: LocalizedText(
      'ZIP 格式不受支持',
      'Unsupported ZIP format',
    ),
    action: LocalizedText(
      '请使用官方发布的资源包；自己打包时请用系统自带的压缩功能，不要用 ZIP64 或特殊压缩算法。',
      'Use an officially released package; when packing it yourself, use the built-in system compression without ZIP64 or special algorithms.',
    ),
    recoverable: true,
  ),
  'zip_path_unsafe': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: LocalizedText(
      'ZIP 含有不安全的路径',
      'ZIP contains unsafe paths',
    ),
    action: LocalizedText(
      '资源包可能被改动过，请从官方渠道重新下载。',
      'The package may have been modified; download it again from an official source.',
    ),
    recoverable: true,
  ),
  'zip_write_failed': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: LocalizedText(
      '无法写入导入文件',
      'Could not write imported files',
    ),
    action: LocalizedText(
      '请清理设备存储空间后重新导入。',
      'Free up device storage and import again.',
    ),
    recoverable: true,
  ),
  'zip_import_failed': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: LocalizedText(
      'ZIP 导入失败',
      'ZIP import failed',
    ),
    action: LocalizedText(
      '请重新下载资源包，并确认设备剩余空间充足后再导入。',
      'Download the resource package again and make sure there is enough free storage before importing.',
    ),
    recoverable: true,
  ),
  'import_failed': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: LocalizedText(
      '资源导入失败',
      'Resource import failed',
    ),
    action: LocalizedText(
      '请重新下载资源包，并确认设备剩余空间充足后再导入。',
      'Download the resource package again and make sure there is enough free storage before importing.',
    ),
    recoverable: true,
  ),
  'import_interrupted': UserLogError(
    category: 'resource.import',
    level: LogLevel.warn,
    title: LocalizedText(
      '上次导入意外中断',
      'The last import was interrupted',
    ),
    action: LocalizedText(
      '请到「资源」页重新导入，导入时让加载器保持在前台。',
      'Import again on the Resources page and keep the loader in the foreground while importing.',
    ),
    recoverable: true,
  ),
  'legacy_migration_failed': UserLogError(
    category: 'resource.import',
    level: LogLevel.error,
    title: LocalizedText(
      '旧版资源迁移失败',
      'Could not migrate old resources',
    ),
    action: LocalizedText(
      '请到「资源」页重新导入游戏资源。',
      'Re-import the game resources on the Resources page.',
    ),
    recoverable: true,
  ),
  'old_slot_cleanup_failed': UserLogError(
    category: 'resource.import',
    level: LogLevel.warn,
    title: LocalizedText(
      '旧资源清理失败',
      'Could not clean up old resources',
    ),
    action: LocalizedText(
      '不影响游戏；请确认设备剩余空间充足，下次启动会自动重试。',
      'The game is not affected; make sure there is enough free storage. Cleanup retries on the next start.',
    ),
    recoverable: true,
  ),
  'candidate_recovery_failed': UserLogError(
    category: 'resource.import',
    level: LogLevel.warn,
    title: LocalizedText(
      '未完成的导入已作废',
      'Unfinished import discarded',
    ),
    action: LocalizedText(
      '请到「资源」页重新导入游戏资源。',
      'Re-import the game resources on the Resources page.',
    ),
    recoverable: true,
  ),
  'resource_missing': UserLogError(
    category: 'resource.validation',
    level: LogLevel.warn,
    title: LocalizedText(
      '尚未导入游戏资源',
      'No game resources imported',
    ),
    action: LocalizedText(
      '请到「资源」页导入游戏资源 ZIP。',
      'Import a game resource ZIP on the Resources page.',
    ),
    recoverable: true,
  ),
  'resource_validation_failed': UserLogError(
    category: 'game.host',
    level: LogLevel.error,
    title: LocalizedText(
      '资源校验未通过',
      'Resource validation did not pass',
    ),
    action: LocalizedText(
      '请到「资源」页重新导入游戏资源。',
      'Re-import the game resources on the Resources page.',
    ),
    recoverable: true,
  ),
  'validation_failed': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: LocalizedText(
      '资源校验失败',
      'Resource validation failed',
    ),
    action: LocalizedText(
      '请重新下载完整的游戏资源包后再导入。',
      'Download the complete game resource package again and import it.',
    ),
    recoverable: true,
  ),
  'host_abi_unsupported': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: LocalizedText(
      '资源包需要新版加载器',
      'This package needs a newer loader',
    ),
    action: LocalizedText(
      '请点右上角的刷新图标检查更新，升级加载器后重新导入。',
      'Tap the refresh icon at the top right to check for updates, upgrade the loader, then import again.',
    ),
    recoverable: true,
  ),
  'package_metadata_invalid': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: LocalizedText(
      '资源包内容与索引不一致',
      'Package contents do not match its index',
    ),
    action: LocalizedText(
      '资源包可能下载不完整或被改动过，请重新下载官方资源包。',
      'The package may be incomplete or modified; download the official package again.',
    ),
    recoverable: true,
  ),
  'resource_path_unsafe': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: LocalizedText(
      '资源包含不安全的路径',
      'Resources contain unsafe paths',
    ),
    action: LocalizedText(
      '资源包可能被改动过，请从官方渠道重新下载。',
      'The package may have been modified; download it again from an official source.',
    ),
    recoverable: true,
  ),
  'missing_required_directory': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: LocalizedText(
      '资源缺少必要目录',
      'A required resource folder is missing',
    ),
    action: LocalizedText(
      '请选择完整的游戏资源 ZIP，不要只压缩其中一部分文件。',
      'Choose the complete game resource ZIP, not a ZIP of only some of its files.',
    ),
    recoverable: true,
  ),
  'missing_required_file': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: LocalizedText(
      '资源缺少必要文件',
      'A required resource file is missing',
    ),
    action: LocalizedText(
      '请选择完整的游戏资源 ZIP，不要只压缩其中一部分文件。',
      'Choose the complete game resource ZIP, not a ZIP of only some of its files.',
    ),
    recoverable: true,
  ),
  'title_fingerprint_mismatch': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: LocalizedText(
      '不是 Gardendless 资源',
      'Not a Gardendless resource',
    ),
    action: LocalizedText(
      '请选择 PvZ2 Gardendless 的 Web 资源包。',
      'Choose a PvZ2 Gardendless web resource package.',
    ),
    recoverable: true,
  ),
  'index_fingerprint_mismatch': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: LocalizedText(
      '不是 Gardendless 资源',
      'Not a Gardendless resource',
    ),
    action: LocalizedText(
      '请选择 PvZ2 Gardendless 的 Web 资源包。',
      'Choose a PvZ2 Gardendless web resource package.',
    ),
    recoverable: true,
  ),
  'settings_json_invalid': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: LocalizedText(
      '游戏配置文件损坏',
      'Game configuration file is corrupted',
    ),
    action: LocalizedText(
      '请重新下载完整的游戏资源包后再导入。',
      'Download the complete game resource package again and import it.',
    ),
    recoverable: true,
  ),
  'settings_cocos_config_missing': UserLogError(
    category: 'resource.validation',
    level: LogLevel.error,
    title: LocalizedText(
      '游戏配置文件不完整',
      'Game configuration file is incomplete',
    ),
    action: LocalizedText(
      '请重新下载完整的游戏资源包后再导入。',
      'Download the complete game resource package again and import it.',
    ),
    recoverable: true,
  ),
  'gp_next_incompatible': UserLogError(
    category: 'resource.validation',
    level: LogLevel.warn,
    title: LocalizedText(
      'GP-Next 不兼容',
      'GP-Next incompatible',
    ),
    action: LocalizedText(
      '请点右上角的刷新图标检查更新并升级加载器，或换用加载器支持的 GP-Next 资源包。',
      'Tap the refresh icon at the top right to check for and install loader updates, or use a GP-Next package this loader supports.',
    ),
    recoverable: true,
  ),
  'webview_unsupported': UserLogError(
    category: 'game.host',
    level: LogLevel.error,
    title: LocalizedText(
      '系统 WebView 版本过旧',
      'System WebView is too old',
    ),
    action: LocalizedText(
      '请在应用商店更新 Android System WebView（或 Chrome）后重新开始游戏。',
      'Update Android System WebView (or Chrome) in the app store, then start the game again.',
    ),
    recoverable: true,
  ),
  'game_host_launch_busy': UserLogError(
    category: 'game.host',
    level: LogLevel.warn,
    title: LocalizedText(
      '游戏正在启动',
      'The game is starting',
    ),
    action: LocalizedText(
      '请稍候，不要重复点「开始游戏」。',
      'Please wait; do not tap Start Game again.',
    ),
    recoverable: true,
  ),
  'game_host_unavailable': UserLogError(
    category: 'game.host',
    level: LogLevel.error,
    title: LocalizedText(
      '游戏宿主不可用',
      'Game host unavailable',
    ),
    action: LocalizedText(
      '请重启加载器后再开始游戏。',
      'Restart the loader, then start the game.',
    ),
    recoverable: true,
  ),
  'invalid_game_session': UserLogError(
    category: 'game.host',
    level: LogLevel.error,
    title: LocalizedText(
      '游戏会话无效',
      'Invalid game session',
    ),
    action: LocalizedText(
      '请重启加载器后再开始游戏。',
      'Restart the loader, then start the game.',
    ),
    recoverable: true,
  ),
};

/// The user-facing title of [code] in the current language; [fallback] when
/// the catalog does not know the code.
String userErrorTitle(String? code, String fallback) =>
    userErrorCatalog[code]?.title.of(AppStrings.current) ?? fallback;

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
  final LocalizedText title;
  final LocalizedText action;
  final bool recoverable;
}
