import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/models.dart';
import 'package:gardendless_loader/src/services/import_progress_meter.dart';

void main() {
  test('exposes user-facing step and determinate progress metadata', () {
    const extracting = ImportProgress(
      phase: ImportPhase.extracting,
      copiedBytes: 512,
      totalBytes: 1024,
    );
    const validating = ImportProgress(phase: ImportPhase.validating);

    expect(extracting.stepIndex, 2);
    expect(extracting.stepCount, 4);
    expect(extracting.value, 0.5);
    expect(validating.stepIndex, 3);
    expect(validating.value, isNull);
  });

  test('measures elapsed time and smooths byte throughput', () {
    var now = DateTime.utc(2026, 7, 17, 12);
    final meter = ImportProgressMeter(clock: () => now);

    meter.measure(const ImportProgress(
      phase: ImportPhase.extracting,
      copiedBytes: 100,
      totalBytes: 1000,
    ));
    now = now.add(const Duration(seconds: 1));
    final second = meter.measure(const ImportProgress(
      phase: ImportPhase.extracting,
      copiedBytes: 300,
      totalBytes: 1000,
    ));
    now = now.add(const Duration(seconds: 1));
    final third = meter.measure(const ImportProgress(
      phase: ImportPhase.extracting,
      copiedBytes: 700,
      totalBytes: 1000,
    ));

    expect(second.elapsed, const Duration(seconds: 1));
    expect(second.bytesPerSecond, 200);
    expect(third.elapsed, const Duration(seconds: 2));
    expect(third.bytesPerSecond, 250);
  });
}
