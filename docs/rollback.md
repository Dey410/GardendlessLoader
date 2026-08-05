# GardendlessLoader iOS 回滚说明

## 1. 何时需要回滚

- 新 iOS 原生层（GardendlessKit）在真机上出现旧版本没有的问题。
- 构建/CI 门禁发现回归且无法立即修复。

## 2. 回滚方式

旧实现仍保留在当前分支的 Git 历史提交中（磁盘文件已按确认删除），回滚不需要恢复备份：

```bash
# 以当前分支回滚点（Phase 5 切换前）新建回滚分支
git checkout -b rollback-ios-legacy <切换前提交>
```

切换前提交：`6f78a53^`（即 GardendlessKit 各能力已提交、Runner 尚未切换前的状态）。

若只想在工作树临时恢复旧 iOS 工程而不切分支：

```bash
git restore --source=<切换前提交> -- ios/Runner ios/Runner.xcodeproj ios/RunnerTests
```

> 注意：`git restore` 会覆盖当前工作树中的 iOS 文件；执行前请确认无未提交改动。

## 3. 回滚影响

- 用户数据：无影响（路径与格式未变）。
- Flutter 启动器：无影响（通道契约未变）。
- Android / OHOS：无影响。
- CI：iOS job 的 `swift test`（GardendlessKit）步骤可保留或一并回退。

## 4. 回滚后验证

```bash
flutter pub get
flutter analyze
flutter test
flutter build ios --release --no-codesign
```
