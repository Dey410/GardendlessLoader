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

const CHANNEL_NAME = 'io.github.dey410.gardendlessloader/gp_next_file_importer';
const METHOD_PICK_AND_COPY = 'pickAndCopyFiles';

export class GpNextFileImporterPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private busy: boolean = false;

  getUniqueClassName(): string {
    return 'GpNextFileImporterPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== METHOD_PICK_AND_COPY) {
      result.notImplemented();
      return;
    }
    const targetDirectory = call.argument('targetDirectory') as string;
    if (targetDirectory == null || targetDirectory.length === 0) {
      result.error('invalid_target_directory', '缺少 GP-Next 导入暂存目录', null);
      return;
    }
    if (this.busy) {
      result.error('gp_next_import_busy', '已有 GP-Next 文件选择正在进行', null);
      return;
    }
    this.busy = true;
    this.pickAndCopy(targetDirectory)
      .then((paths: string[] | null) => {
        this.busy = false;
        result.success(paths);
      })
      .catch((error: Error) => {
        this.busy = false;
        result.error(
          'gp_next_import_failed',
          `无法导入选择的 GP-Next 文件：${error.message ?? error.toString()}`,
          null,
        );
      });
  }

  private async pickAndCopy(targetDirectory: string): Promise<string[] | null> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 32;
    options.fileSuffixFilters = ['.zip', '.json', '.json5'];
    const selected = await new picker.DocumentViewPicker().select(options);
    if (selected == null || selected.length === 0) {
      return null;
    }
    this.ensureDirectory(targetDirectory);
    const copied: string[] = [];
    for (const uri of selected) {
      const rawName = decodeURIComponent(this.basename(uri));
      const safeName = this.safeFileName(rawName);
      const destination = this.uniqueDestination(targetDirectory, safeName);
      this.copyUri(uri, destination);
      copied.push(destination);
    }
    return copied;
  }

  private copyUri(uri: string, destination: string): void {
    let input: fs.File | null = null;
    try {
      input = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      fs.copyFileSync(input.fd, destination);
    } finally {
      if (input != null) {
        fs.closeSync(input.fd);
      }
    }
  }

  private uniqueDestination(directory: string, fileName: string): string {
    let destination = this.joinPath(directory, fileName);
    let suffix = 1;
    const dot = fileName.lastIndexOf('.');
    const stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    const extension = dot > 0 ? fileName.substring(dot) : '';
    while (this.exists(destination)) {
      destination = this.joinPath(directory, `${stem}-${suffix}${extension}`);
      suffix++;
    }
    return destination;
  }

  private safeFileName(value: string): string {
    const cleaned = value.replace(/[\\/:*?"<>|\u0000-\u001f]/g, '_').trim();
    return cleaned.length === 0 || cleaned === '.' || cleaned === '..'
      ? 'gp-next-file'
      : cleaned;
  }

  private ensureDirectory(path: string): void {
    if (path.length === 0 || this.exists(path)) {
      return;
    }
    this.ensureDirectory(this.dirname(path));
    fs.mkdirSync(path);
  }

  private exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (_) {
      return false;
    }
  }

  private joinPath(parent: string, child: string): string {
    return parent.endsWith('/') ? `${parent}${child}` : `${parent}/${child}`;
  }

  private dirname(path: string): string {
    const normalized = path.replace(/\\/g, '/');
    const index = normalized.lastIndexOf('/');
    return index <= 0 ? '' : normalized.substring(0, index);
  }

  private basename(path: string): string {
    const normalized = path.replace(/\\/g, '/');
    const index = normalized.lastIndexOf('/');
    return index === -1 ? normalized : normalized.substring(index + 1);
  }
}
