import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Lets a game controller move the launcher's focus the way a keyboard
/// does: the D-pad and left stick step between controls, A presses the
/// focused one and B closes the open dialog, like Escape.
///
/// Each platform hands the controller to Flutter differently:
/// - Android sends the D-pad and A as keys, and turns the stick into D-pad
///   keys, so only B needs a shortcut here.
/// - HarmonyOS sends the D-pad as arrow keys, but A and B only in its own
///   key plane, and the stick not at all: from API 15 the host sends its
///   held direction over [_channel].
/// - Flutter on iOS receives no controller input, so the host reads the
///   controllers and sends the held direction and A and B over [_channel].
///
/// Selectable text sits inside [ExcludeFocusTraversal]: focused, it shows
/// nothing, so a step onto it would look like a lost focus.
class GamepadNavigation extends StatefulWidget {
  const GamepadNavigation({super.key, required this.child});

  final Widget child;

  @override
  State<GamepadNavigation> createState() => _GamepadNavigationState();
}

class _GamepadNavigationState extends State<GamepadNavigation> {
  static const _channel = MethodChannel(
    'io.github.dey410.gardendlessloader/gamepad',
  );

  // KEYCODE_BUTTON_A and KEYCODE_BUTTON_B, which HarmonyOS's Flutter
  // embedding has no Flutter key for.
  static const _ohosPlane = 0x01900000000;
  static const _shortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.gameButtonB): DismissIntent(),
    SingleActivator(LogicalKeyboardKey(_ohosPlane | 2301)): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey(_ohosPlane | 2302)): DismissIntent(),
  };

  static const _repeatDelay = Duration(milliseconds: 400);
  static const _repeatInterval = Duration(milliseconds: 120);

  Timer? _repeat;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_onInput);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _repeat?.cancel();
    super.dispose();
  }

  Future<void> _onInput(MethodCall call) async {
    // Channel input is not a key event, so it shows the focus highlight
    // itself until the next touch.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    switch (call.arguments) {
      case 'a':
        _invoke(const ActivateIntent());
      case 'b':
        _invoke(const DismissIntent());
      case final String direction:
        _hold(TraversalDirection.values.asNameMap()[direction]);
    }
  }

  /// Moves once, then keeps moving while [direction] stays held; null lets
  /// go.
  void _hold(TraversalDirection? direction) {
    _repeat?.cancel();
    if (direction == null) return;
    void move() =>
        _invoke(DirectionalFocusIntent(direction, ignoreTextFields: false));
    move();
    _repeat = Timer(_repeatDelay, () {
      _repeat = Timer.periodic(_repeatInterval, (_) => move());
    });
  }

  void _invoke(Intent intent) {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context != null) Actions.maybeInvoke(context, intent);
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(shortcuts: _shortcuts, child: widget.child);
  }
}
