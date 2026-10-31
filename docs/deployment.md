# GardendlessLoader iOS 部署说明

## 1. 构建

```bash
flutter pub get
cd ios/GardendlessKit && swift test
cd ../..
flutter build ios --release --no-codesign
```

产物：`build/ios/iphoneos/Runner.app`。

打包无签名 IPA（CI 同流程）：

```bash
mkdir -p build/ios/ipa/Payload
cp -R build/ios/iphoneos/Runner.app build/ios/ipa/Payload/Runner.app
cd build/ios/ipa
zip -r GardendlessLoader-unsigned.ipa Payload
```

## 2. CI

`.github/workflows/build-mobile.yml` 的 iOS job：

1. 在 `xcode-27` Runner 上选择 Xcode 27.2 RC（`27B48`），校验 iOS SDK 为 `27.2`；不自动回退。
2. 安装 Flutter 3.41.9 依赖并运行 `swift test`（GardendlessKit）。
3. 执行 `pod install`，再运行 `flutter build ios --release --no-codesign`。
4. 校验版本、iOS 15.0 最低版本与 arm64 架构，打包并上传未签名 IPA；构建摘要记录工具链、Git SHA 和 IPA SHA-256。

## 3. 分发

- 侧载：用户自行签名（free provisioning / 企业证书 / AltStore 等）。
- 正式分发：需要开发者账号与签名配置；仓库不包含签名文件。
- 本仓库不自动部署到生产环境。

## 4. 已知事项

- Flutter 的 Swift Package Manager 插件集成在 `pubspec.yaml` 中关闭；iOS 构建继续使用仓库现有的 CocoaPods 配置。
- WebKit 高刷新率调整使用私有 SPI，仅适合侧载构建（详见 ADR-0002 与风险登记表）。
