export class ExportDocumentSpec {
  static fileSuffixChoices(fileName: string, mimeType: string): Array<string> {
    const dotIndex = fileName.lastIndexOf('.');
    const extension = dotIndex > 0 && dotIndex < fileName.length - 1
      ? fileName.substring(dotIndex + 1).toLowerCase()
      : '';
    switch (extension) {
      case 'json':
        return ['JSON 文件|.json'];
      case 'json5':
        return ['JSON5 文件|.json5'];
      case 'zip':
        return ['ZIP 文件|.zip'];
      default:
        if (extension.length > 0) {
          return new Array<string>();
        }
    }
    if (mimeType === 'application/json' || mimeType === 'text/json') {
      return ['JSON 文件|.json'];
    }
    if (mimeType === 'application/zip' || mimeType === 'application/x-zip-compressed') {
      return ['ZIP 文件|.zip'];
    }
    return new Array<string>();
  }
}
