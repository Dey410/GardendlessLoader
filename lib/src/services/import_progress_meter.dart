import '../models.dart';

typedef ImportProgressClock = DateTime Function();

class ImportProgressMeter {
  ImportProgressMeter({ImportProgressClock? clock})
      : _clock = clock ?? DateTime.now;

  final ImportProgressClock _clock;

  DateTime? _startedAt;
  DateTime? _lastSampleAt;
  ImportPhase? _lastPhase;
  int _lastBytes = 0;
  double _smoothedBytesPerSecond = 0;

  ImportProgress measure(ImportProgress progress) {
    final now = _clock();
    final startedAt = _startedAt ??= now;
    final phaseChanged = progress.phase != _lastPhase;
    final lastSampleAt = _lastSampleAt;

    if (phaseChanged || progress.copiedBytes < _lastBytes) {
      _smoothedBytesPerSecond = 0;
    } else if (lastSampleAt != null) {
      final sampleSeconds = now.difference(lastSampleAt).inMicroseconds / 1e6;
      final byteDelta = progress.copiedBytes - _lastBytes;
      if (sampleSeconds > 0 && byteDelta > 0) {
        final instantBytesPerSecond = byteDelta / sampleSeconds;
        _smoothedBytesPerSecond = _smoothedBytesPerSecond == 0
            ? instantBytesPerSecond
            : _smoothedBytesPerSecond * 0.75 + instantBytesPerSecond * 0.25;
      }
    }

    _lastPhase = progress.phase;
    _lastSampleAt = now;
    _lastBytes = progress.copiedBytes;

    final elapsed = now.difference(startedAt);
    return progress.copyWith(
      elapsed: elapsed.isNegative ? Duration.zero : elapsed,
      bytesPerSecond: _smoothedBytesPerSecond,
    );
  }
}
