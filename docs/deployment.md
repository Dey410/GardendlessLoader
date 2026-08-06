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

1. `flutter pub get`
2. `swift test`（GardendlessKit）
3. `pod install`（保留 CocoaPods 集成；见下文已知事项）
4. `flutter test`
5. `flutter build ios --release --no-codesign` + 打包 IPA + 上传 artifact

## 3. 分发

- 侧载：用户自行签名（free provisioning / 企业证书 / AltStore 等）。
- 正式分发：需要开发者账号与签名配置；仓库不包含签名文件。
- 本仓库不自动部署到生产环境。

## 4. 已知事项

- Flutter 已启用 Swift Package Manager 插件集成；仓库仍保留非标准 Podfile，构建会提示建议迁移到纯 SPM。功能不受影响，后续可执行 `pod deintegrate` 并移除 xcconfig 中的 Pods 引用。
- WebKit 高刷新率调整使用私有 SPI，仅适合侧载构建（详见 ADR-0002 与风险登记表）。
