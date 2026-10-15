import 'dart:async';
import 'package:gardendless_loader/src/app_controller.dart';
import 'package:gardendless_loader/src/models.dart';
import 'package:gardendless_loader/src/services/update_check_service.dart';

/// Explicit test data, never used by the production entry point.
class VerdantFixtureController extends AppController {
  bool ready = true;
  bool loading = false;
  bool sun = false;
  bool watermark = true;
  bool audio = false;
  int launches = 0;
  int imports = 0;
  int refreshes = 0;
  int deletions = 0;
  int updateChecks = 0;
  Completer<void>? pendingLaunch;
  Object? launchFailure;
  ImportProgress progress = ImportProgress.idle;
  UpdateInfo? update;

  @override
  bool get initialized => true;
  @override
  bool get busy => loading;
  @override
  bool get canStartGame => ready;
  @override
  bool get hasCurrentResource => ready;
  @override
  bool get hasGpNext => false;
  @override
  bool get gpNextCompatible => false;
  @override
  String get detectedTitle => 'PvZ2 Gardendless';
  @override
  String get currentAppVersion => '0.8.2';
  @override
  String? get currentGameVersion => ready ? '0.11.0' : null;
  @override
  String? get latestGameVersion => '0.11.0';
  @override
  String get userVisibleRoot => '/local/GardendlessLoader';
  @override
  ResourceValidationResult get currentValidation => ready
    ? ResourceValidationResult.valid(detectedTitle: detectedTitle)
    : ResourceValidationResult.missing('尚未导入游戏资源');
  @override
  ResourceManifest get manifest => ready ? ResourceManifest.initial().copyWith(
    activeSlot: ResourceSlot.slotA, fileCount: 2846, totalBytes: 482344960,
    detectedTitle: detectedTitle, gameVersion: '0.11.0',
    lastImportAt: DateTime(2026, 10, 15, 9, 41),
    lastSelfCheckAt: DateTime(2026, 10, 15, 9, 42),
    resourceStatus: ResourceStatus.ready,
  ) : ResourceManifest.initial();
  @override
  Announcement? get announcement => const Announcement(
    id: 'ui-fixture', title: '新一轮生长，从这里开始。',
    message: '把熟悉的花园，装进口袋。管理你的本地资源，带上喜欢的植物，在每一次出发时遇见新的可能。',
  );
  @override
  bool get autoCollectSunEnabled => sun;
  @override
  bool get watermarkEnabled => watermark;
  @override
  bool get detailedAudioDiagnosticsEnabled => audio;
  @override
  ImportProgress get importProgress => progress;
  @override
  bool get isImporting => ![ImportPhase.idle, ImportPhase.completed, ImportPhase.failed].contains(progress.phase);
  @override
  UpdateInfo? get availableUpdate => update;
  @override
  Future<void> checkForUpdates({bool silent = false}) async { updateChecks++; }
  @override
  Future<void> importResources() async { imports++; }
  @override
  Future<void> startGame() async {
    launches++;
    if (launchFailure != null) throw launchFailure!;
    await pendingLaunch?.future;
  }
  @override
  Future<void> refresh() async { refreshes++; }
  @override
  Future<void> refreshLogs() async {}
  @override
  Future<void> refreshAnnouncement() async {}
  @override
  Future<void> deleteLogHistory() async { deletions++; }
  @override
  String buildDiagnosticSummary() => 'Verdant diagnostic fixture';
  @override
  Future<void> setAutoCollectSunEnabled(bool enabled) async { sun = enabled; notifyListeners(); }
  @override
  Future<void> setWatermarkEnabled(bool enabled) async { watermark = enabled; notifyListeners(); }
  @override
  Future<void> setDetailedAudioDiagnosticsEnabled(bool enabled) async { audio = enabled; notifyListeners(); }
  @override
  void deferUpdate(UpdateInfo value) { update = null; notifyListeners(); }
  @override
  void dismissImportProgress() { progress = ImportProgress.idle; notifyListeners(); }
}
