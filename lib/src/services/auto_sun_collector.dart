import 'dart:async';

typedef PressCollectKey = FutureOr<void> Function();

class AutoSunCollector {
  AutoSunCollector({
    required PressCollectKey onPressCollectKey,
    this.interval = const Duration(milliseconds: 1500), //收集阳光定时器,默认1.5秒一次
  }) : _onPressCollectKey = onPressCollectKey;

  final PressCollectKey _onPressCollectKey;
  final Duration interval;
  Timer? _timer;

  bool get isEnabled => _timer != null;

  void setEnabled(bool enabled) {
    if (enabled == isEnabled) {
      return;
    }

    if (enabled) {
      _timer = Timer.periodic(interval, (_) {
        unawaited(Future<void>.sync(_onPressCollectKey));
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void dispose() {
    setEnabled(false);
  }
}
