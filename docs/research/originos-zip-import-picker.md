# OriginOS 6 ZIP 导入选择器兼容性调研

日期：2026-07-31

## 问题范围

用户报告 GardendlessLoader 0.6.2 在以下设备点击 ZIP 导入按钮后没有可见反应：

- vivo X Fold 3 Pro，OriginOS 6，Android 16
- iQOO Pad5，OriginOS 6，Android 15

由于没有设备日志、录屏或可配合测试的终端，本记录只区分可由源码和一手资料证实的事实与尚待真机验证的推断。

## 已证实事实

### 1. 项目的多 MIME Intent 不符合 Android 官方约定

`android/app/src/main/kotlin/io/github/dey410/gardendlessloader/MainActivity.kt`
中的 ZIP 选择器使用 `ACTION_OPEN_DOCUMENT`，同时：

- 将主 MIME 类型设置为 `application/zip`；
- 通过 `EXTRA_MIME_TYPES` 传入
  `application/zip`、`application/x-zip-compressed` 和
  `application/octet-stream`。

Android 官方文档明确要求：使用 `EXTRA_MIME_TYPES` 指定多个 MIME 类型时，
主 MIME 类型必须设置为 `*/*`。

来源：

- [Android Common intents：Open a specific type of file](https://developer.android.com/guide/components/intents-common#OpenFile)
- [Android storage use cases：Open a document file](https://developer.android.com/training/data-storage/use-cases#open-document)

v0.6.2 与当前分支在这段关键 Intent 配置上相同，因此当前代码仍包含该偏差。

### 2. SAF 文件选择不需要传统存储权限

Android Storage Access Framework 由用户在系统选择器中明确选择文件，官方说明该机制不需要系统存储权限。因此，添加
`READ_EXTERNAL_STORAGE`、`WRITE_EXTERNAL_STORAGE` 或
`MANAGE_EXTERNAL_STORAGE` 不是这个问题的正确修复。

来源：

- [Android：Access documents and other files from shared storage](https://developer.android.com/training/data-storage/shared/documents-files)

### 3. 定制 ROM 可能不可靠地实现 MIME 筛选

`file_picker` 维护方的 FAQ 说明，部分 Android 定制系统的原生文件浏览器不存在或不会可靠遵守 MIME 限制；其兼容性建议是允许选择任意文件，再由应用自行校验文件。

本项目没有使用 `file_picker`，但它调用的是同一类 Android 系统文件选择 Intent，因此这条经验可以作为兼容性旁证。

来源：

- [flutter_file_picker FAQ](https://github.com/miguelpruivo/flutter_file_picker/wiki/FAQ)

### 4. 没有找到 OriginOS 6 专属的已确诊公开记录

本次检索没有找到 vivo、Android、Flutter 或相关文件选择插件维护方发布的
“OriginOS 6 点击 `ACTION_OPEN_DOCUMENT` 完全不弹出”确诊记录。
也没有一手资料表明该问题由 Android 15/16、平板或折叠屏形态直接导致。

因此，OriginOS 对当前非标准 MIME 组合处理更严格，是符合现象的高可信推断，
但不是已由真机日志证实的根因。

## 建议方案

### P0：规范化 ZIP 选择 Intent

保留 MIME 数组时，将主类型改为：

```kotlin
val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
    addCategory(Intent.CATEGORY_OPENABLE)
    type = "*/*"
    putExtra(
        Intent.EXTRA_MIME_TYPES,
        arrayOf(
            "application/zip",
            "application/x-zip-compressed",
            "application/octet-stream",
        ),
    )
}
```

现有代码已在选择后扫描和校验 ZIP 内容，所以即使某个系统忽略 MIME 筛选，
应用仍可以拒绝无效文件。

### P1：增加兼容回退与可见错误

- 当系统无法处理 `ACTION_OPEN_DOCUMENT` 时，回退到
  `ACTION_GET_CONTENT`，仍使用 `*/*` 并在应用内校验。
- 点击后立即显示“正在打开文件选择器”，并把启动失败、取消和超时区分为可见状态，
  避免任何异常继续表现为“按钮没反应”。

### P2：补回归测试

Android 配置测试至少应断言：

- 使用 `ACTION_OPEN_DOCUMENT`；
- 使用 `CATEGORY_OPENABLE`；
- 存在 `EXTRA_MIME_TYPES` 时主类型为 `*/*`；
- 无选择器时会返回明确错误或进入兼容回退。

## 验证建议

在没有粉丝真机配合的情况下，可使用 vivo 官方云测服务的远程真机调试功能复现，
该服务提供 vivo 真机操作、日志和截图能力。

来源：

- [vivo 云测服务介绍](https://developers.vivo.com/doc/d/0668af0141fb458ca254a80602da43e0)
- [vivo 云测平台](https://developers.vivo.com/product/d/cloud)

只有在规范化 Intent 后仍能在 OriginOS 云真机复现，才应把调查重点转向
OriginOS 系统文件选择器本身。
