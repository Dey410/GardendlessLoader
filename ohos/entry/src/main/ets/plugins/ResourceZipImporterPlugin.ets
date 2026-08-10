import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import zlib from '@ohos.zlib';
import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import AbilityAware from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityAware';
import {
  AbilityPluginBinding,
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityPluginBinding';
import { withDocumentPickerOrientation } from '../picker/DocumentPickerOrientation';

const CHANNEL_NAME = 'io.github.dey410.gardendlessloader/resource_zip_importer';
const METHOD_PICK_AND_EXTRACT = 'pickAndExtractDocsZip';
const ZIP_COPY_NAME = 'gardendless-resource.zip';
const PROGRESS_REPORT_INTERVAL_MS = 100;

interface ImportProgressPayload {
  phase: string;
  processedBytes: number;
  totalBytes: number;
  processedFiles: number;
  totalFiles: number;
}

export class ResourceZipImporterPlugin implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext | null = null;
  private busy: boolean = false;
  private lastProgressReportAt: number = 0;

  getUniqueClassName(): string {
    return 'ResourceZipImporterPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context;
  }

  onDetachedFromAbility(): void {
    this.context = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== METHOD_PICK_AND_EXTRACT) {
      result.notImplemented();
      return;
    }

    const targetDirectory = call.argument('targetDirectory') as string;
    if (targetDirectory == null || targetDirectory.length === 0) {
      result.error('invalid_target_directory', '缺少导入目标目录', null);
      return;
    }

    if (this.busy) {
      result.error('zip_import_busy', '已有 ZIP 导入选择正在进行', null);
      return;
    }

    this.busy = true;
    this.pickAndExtractDocsZip(targetDirectory)
      .then((path: string | null) => {
        this.busy = false;
        result.success(path);
      })
      .catch((error: Error) => {
        this.busy = false;
        result.error(
          'zip_import_failed',
          `无法导入选择的 ZIP：${error.message ?? error.toString()}`,
          null,
        );
      });
  }

  private async pickAndExtractDocsZip(targetDirectory: string): Promise<string | null> {
    const context = this.context;
    if (context == null) {
      throw new Error('无法获取鸿蒙应用上下文');
    }

    const selectedUri = await this.pickZipUri(context);
    if (selectedUri == null) {
      return null;
    }

    const workRoot = this.joinPath(context.cacheDir, `resource_zip_import_${Date.now()}`);
    const zipPath = this.joinPath(workRoot, ZIP_COPY_NAME);

    try {
      this.ensureDirectory(workRoot);
      this.reportProgress({
        phase: 'receiving',
        processedBytes: 0,
        totalBytes: 0,
        processedFiles: 0,
        totalFiles: 0,
      }, true);
      this.copyPickerUriToFile(selectedUri, zipPath);
      const zipBytes = fs.statSync(zipPath).size;
      this.reportProgress({
        phase: 'receiving',
        processedBytes: zipBytes,
        totalBytes: zipBytes,
        processedFiles: 0,
        totalFiles: 0,
      }, true);
      this.reportProgress({
        phase: 'extracting',
        processedBytes: 0,
        totalBytes: 0,
        processedFiles: 0,
        totalFiles: 0,
      }, true);
      this.resetDirectory(targetDirectory);
      await zlib.decompressFile(zipPath, targetDirectory);

      const docsDirectory = this.findDocsDirectory(targetDirectory);
      if (docsDirectory == null) {
        throw new Error('选择的 ZIP 中没有找到有效的 docs 资源目录');
      }

      this.reportExtractedFiles(docsDirectory);
      this.promoteDocsDirectory(docsDirectory, targetDirectory);
      return targetDirectory;
    } finally {
      this.deleteIfExists(workRoot);
    }
  }

  private async pickZipUri(context: common.UIAbilityContext): Promise<string | null> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['.zip'];

    const documentViewPicker = new picker.DocumentViewPicker();
    const selected = await withDocumentPickerOrientation(
      context,
      (): Promise<string[]> => documentViewPicker.select(options),
    );
    if (selected == null || selected.length === 0) {
      return null;
    }
    return selected[0];
  }

  private copyPickerUriToFile(uri: string, targetPath: string): void {
    let input: fs.File | null = null;
    try {
      input = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      fs.copyFileSync(input.fd, targetPath);
    } finally {
      if (input != null) {
        fs.closeSync(input.fd);
      }
    }
  }

  private findDocsDirectory(root: string): string | null {
    const indexFiles = this.collectFiles(root)
      .filter((filePath: string) => this.basename(filePath).toLowerCase() === 'index.html');

    const candidates = indexFiles
      .map((filePath: string) => this.dirname(filePath))
      .filter((directory: string) => this.isValidDocsDirectory(directory));

    candidates.sort((a: string, b: string): number => {
      const aIsDocs = this.basename(a) === 'docs';
      const bIsDocs = this.basename(b) === 'docs';
      if (aIsDocs !== bIsDocs) {
        return aIsDocs ? -1 : 1;
      }
      return a.length - b.length;
    });

    return candidates.length === 0 ? null : candidates[0];
  }

  private isValidDocsDirectory(directory: string): boolean {
    return this.isFile(this.joinPath(directory, 'index.html')) &&
      this.isFile(this.joinPath(directory, 'src/settings.json')) &&
      this.isFile(this.joinPath(directory, 'src/import-map.json')) &&
      this.isDirectory(this.joinPath(directory, 'assets')) &&
      this.isDirectory(this.joinPath(directory, 'cocos-js')) &&
      this.isDirectory(this.joinPath(directory, 'src'));
  }

  private reportExtractedFiles(directory: string): void {
    const files = this.collectFiles(directory);
    const totalFiles = files.length;
    let totalBytes = 0;
    for (const filePath of files) {
      totalBytes += fs.statSync(filePath).size;
    }

    this.reportProgress({
      phase: 'extracting',
      processedBytes: totalBytes,
      totalBytes: totalBytes,
      processedFiles: totalFiles,
      totalFiles: totalFiles,
    }, true);
  }

  private promoteDocsDirectory(docsDirectory: string, targetDirectory: string): void {
    if (docsDirectory === targetDirectory) {
      return;
    }

    const promotedName = `.promoted-docs-${Date.now()}`;
    const promotedDirectory = this.joinPath(targetDirectory, promotedName);
    fs.renameSync(docsDirectory, promotedDirectory);

    for (const name of this.listFileNames(targetDirectory)) {
      if (name !== promotedName) {
        this.deleteIfExists(this.joinPath(targetDirectory, name));
      }
    }
    for (const name of this.listFileNames(promotedDirectory)) {
      fs.renameSync(
        this.joinPath(promotedDirectory, name),
        this.joinPath(targetDirectory, name),
      );
    }
    fs.rmdirSync(promotedDirectory);
  }

  private reportProgress(progress: ImportProgressPayload, force: boolean = false): void {
    const now = Date.now();
    if (!force && now - this.lastProgressReportAt < PROGRESS_REPORT_INTERVAL_MS) {
      return;
    }
    this.lastProgressReportAt = now;

    const argumentsMap = new Map<string, Object>();
    argumentsMap.set('phase', progress.phase);
    argumentsMap.set('processedBytes', progress.processedBytes);
    argumentsMap.set('totalBytes', progress.totalBytes);
    argumentsMap.set('processedFiles', progress.processedFiles);
    argumentsMap.set('totalFiles', progress.totalFiles);
    this.channel?.invokeMethod('progress', argumentsMap);
  }

  private resetDirectory(directory: string): void {
    this.deleteIfExists(directory);
    this.ensureDirectory(directory);
  }

  private deleteIfExists(path: string): void {
    if (!this.exists(path)) {
      return;
    }

    if (this.isDirectory(path)) {
      for (const name of this.listFileNames(path)) {
        this.deleteIfExists(this.joinPath(path, name));
      }
      fs.rmdirSync(path);
      return;
    }

    fs.unlinkSync(path);
  }

  private collectFiles(directory: string): Array<string> {
    const files = new Array<string>();
    for (const name of this.listFileNames(directory)) {
      const child = this.joinPath(directory, name);
      if (this.isDirectory(child)) {
        files.push(...this.collectFiles(child));
      } else {
        files.push(child);
      }
    }
    return files;
  }

  private ensureDirectory(directory: string): void {
    if (directory.length === 0 || this.exists(directory)) {
      return;
    }
    this.ensureDirectory(this.dirname(directory));
    fs.mkdirSync(directory);
  }

  private listFileNames(directory: string): Array<string> {
    if (!this.exists(directory)) {
      return new Array<string>();
    }
    return fs.listFileSync(directory);
  }

  private exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (_) {
      return false;
    }
  }

  private isFile(path: string): boolean {
    return this.exists(path) && !this.isDirectory(path);
  }

  private isDirectory(path: string): boolean {
    try {
      return fs.statSync(path).isDirectory();
    } catch (_) {
      return false;
    }
  }

  private joinPath(parent: string, child: string): string {
    if (child.length === 0) {
      return parent;
    }
    return parent.endsWith('/') ? `${parent}${child}` : `${parent}/${child}`;
  }

  private dirname(path: string): string {
    const index = path.lastIndexOf('/');
    return index <= 0 ? '' : path.substring(0, index);
  }

  private basename(path: string): string {
    const index = path.lastIndexOf('/');
    return index === -1 ? path : path.substring(index + 1);
  }
}
