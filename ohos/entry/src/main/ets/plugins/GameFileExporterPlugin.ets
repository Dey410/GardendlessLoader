import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';

const CHANNEL_NAME = 'io.github.dey410.gardendlessloader/game_file_exporter';
const METHOD_EXPORT_FILE = 'exportFile';

export class GameFileExporterPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private busy: boolean = false;

  getUniqueClassName(): string {
    return 'GameFileExporterPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== METHOD_EXPORT_FILE) {
      result.notImplemented();
      return;
    }

    const path = call.argument('path') as string;
    if (path == null || path.length === 0) {
      result.error('invalid_arguments', '缺少导出文件路径', null);
      return;
    }

    if (!this.isFile(path)) {
      result.error('file_not_found', '导出文件不存在', path);
      return;
    }

    if (this.busy) {
      result.error('export_in_progress', '已有导出正在进行', null);
      return;
    }

    const nameArg = call.argument('name') as string;
    const fileName = nameArg == null || nameArg.length === 0 ? this.basename(path) : nameArg;

    this.busy = true;
    this.exportFile(path, fileName)
      .then(() => {
        this.busy = false;
        result.success(null);
      })
      .catch((error: Error) => {
        this.busy = false;
        if (this.isCancelledError(error)) {
          result.error('export_cancelled', '已取消导出', null);
          return;
        }
        result.error(
          'export_failed',
          `无法保存导出文件：${error.message ?? error.toString()}`,
          null,
        );
      });
  }

  private async exportFile(sourcePath: string, fileName: string): Promise<void> {
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [fileName];

    const documentViewPicker = new picker.DocumentViewPicker();
    const savedUris = await documentViewPicker.save(options);
    if (savedUris == null || savedUris.length === 0) {
      throw new Error('export_cancelled');
    }

    this.copyFile(sourcePath, savedUris[0]);
  }

  private isCancelledError(error: Error): boolean {
    const message = error.message ?? '';
    return message === 'export_cancelled' ||
      message.toLowerCase().includes('cancel') ||
      message.includes('取消');
  }

  private copyFile(sourcePath: string, targetUri: string): void {
    let input: fs.File | null = null;
    try {
      input = fs.openSync(sourcePath, fs.OpenMode.READ_ONLY);
      fs.copyFileSync(input.fd, targetUri);
    } finally {
      if (input != null) {
        fs.closeSync(input.fd);
      }
    }
  }

  private isFile(path: string): boolean {
    try {
      return fs.accessSync(path) && !fs.statSync(path).isDirectory();
    } catch (_) {
      return false;
    }
  }

  private basename(path: string): string {
    const index = path.lastIndexOf('/');
    return index === -1 ? path : path.substring(index + 1);
  }
}
