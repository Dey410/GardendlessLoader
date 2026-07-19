import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/web/touch_patch.dart';

void main() {
  test('two-finger tap dispatches one right-click at the touch center',
      () async {
    final result = await _runTouchScenario(r'''
const first = touch(20, 30);
const second = touch(40, 50);

dispatchTouch('touchstart', [first], [first]);
flushTasks();
dispatchTouch('touchstart', [first, second], [second]);
flushTasks();
dispatchTouch('touchend', [first], [second]);
dispatchTouch('touchend', [], [first]);
flushTasks();

writeResult();
''');

    final rightEvents = (result['events'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((event) => event['button'] == 2)
        .toList();

    expect(
      rightEvents.map((event) => event['type']),
      ['mousedown', 'mouseup'],
    );
    expect(rightEvents[0], containsPair('buttons', 2));
    expect(rightEvents[1], containsPair('buttons', 0));
    expect(rightEvents[0], containsPair('clientX', 30));
    expect(rightEvents[0], containsPair('clientY', 40));
    expect(
      (result['events'] as List<dynamic>).cast<Map<String, dynamic>>(),
      contains(
        allOf(
          containsPair('type', 'mousemove'),
          containsPair('clientX', 30),
          containsPair('clientY', 40),
        ),
      ),
    );
  });

  test('two-finger slide dispatches wheel events without a right-click',
      () async {
    final result = await _runTouchScenario(r'''
const first = touch(20, 30);
const second = touch(40, 50);
const movedFirst = touch(20, 50);
const movedSecond = touch(40, 70);

dispatchTouch('touchstart', [first], [first]);
flushTasks();
dispatchTouch('touchstart', [first, second], [second]);
flushTasks();
dispatchTouch('touchmove', [movedFirst, movedSecond], [movedFirst, movedSecond]);
dispatchTouch('touchend', [movedFirst], [movedSecond]);
dispatchTouch('touchend', [], [movedFirst]);
flushTasks();

writeResult();
''');

    final events =
        (result['events'] as List<dynamic>).cast<Map<String, dynamic>>();
    final wheelEvents =
        events.where((event) => event['type'] == 'wheel').toList();
    final rightEvents = events.where((event) => event['button'] == 2).toList();

    expect(wheelEvents, hasLength(1));
    expect(wheelEvents.single, containsPair('deltaY', -60));
    expect(wheelEvents.single, containsPair('deltaMode', 0));
    expect(rightEvents, isEmpty);
  });

  test('third touch cancels the gesture without mouse actions', () async {
    final result = await _runTouchScenario(r'''
const first = touch(20, 30);
const second = touch(40, 50);
const third = touch(60, 70);

dispatchTouch('touchstart', [first], [first]);
flushTasks();
dispatchTouch('touchstart', [first, second], [second]);
flushTasks();
dispatchTouch('touchstart', [first, second, third], [third]);
flushTasks();
dispatchTouch('touchend', [first, second], [third]);
dispatchTouch('touchend', [first], [second]);
dispatchTouch('touchend', [], [first]);
flushTasks();

writeResult();
''');

    final events =
        (result['events'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(events.where((event) => event['button'] == 2), isEmpty);
    expect(events.where((event) => event['type'] == 'wheel'), isEmpty);
  });

  test('moving three touches does not dispatch mouse events', () async {
    final result = await _runTouchScenario(r'''
const first = touch(20, 30);
const second = touch(40, 50);
const third = touch(60, 70);

dispatchTouch('touchstart', [first], [first]);
flushTasks();
dispatchTouch('touchstart', [first, second], [second]);
flushTasks();
dispatchTouch('touchstart', [first, second, third], [third]);
flushTasks();
clearEvents();

const movedFirst = touch(25, 35);
const movedSecond = touch(45, 55);
const movedThird = touch(65, 75);
dispatchTouch(
  'touchmove',
  [movedFirst, movedSecond, movedThird],
  [movedFirst, movedSecond, movedThird]
);
flushTasks();

writeResult();
''');

    expect(result['events'], isEmpty);
  });

  test('remaining touch after a two-finger gesture does not move the mouse',
      () async {
    final result = await _runTouchScenario(r'''
const first = touch(20, 30);
const second = touch(40, 50);

dispatchTouch('touchstart', [first], [first]);
flushTasks();
dispatchTouch('touchstart', [first, second], [second]);
flushTasks();
dispatchTouch('touchend', [first], [second]);
clearEvents();

const movedFirst = touch(30, 40);
dispatchTouch('touchmove', [movedFirst], [movedFirst]);
flushTasks();

writeResult();
''');

    expect(result['events'], isEmpty);
  });

  test('second touch immediately releases an active left mouse press',
      () async {
    final result = await _runTouchScenario(r'''
const first = touch(20, 30);
const second = touch(40, 50);

dispatchTouch('touchstart', [first], [first]);
flushTasks();
dispatchTouch('touchstart', [first, second], [second]);

writeResult();
''');

    final leftEvents = (result['events'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((event) => event['button'] == 0)
        .toList();

    expect(
      leftEvents.map((event) => event['type']),
      ['mousemove', 'mousedown', 'mouseup'],
    );
    expect(leftEvents.last, containsPair('buttons', 0));
  });

  test('second touch cancels a pending left press before right-click',
      () async {
    final result = await _runTouchScenario(r'''
const first = touch(20, 30);
const second = touch(40, 50);

dispatchTouch('touchstart', [first], [first]);
dispatchTouch('touchstart', [first, second], [second]);
dispatchTouch('touchend', [first], [second]);
dispatchTouch('touchend', [], [first]);
flushTasks();

writeResult();
''');

    final events =
        (result['events'] as List<dynamic>).cast<Map<String, dynamic>>();
    final leftPressEvents = events
        .where((event) =>
            event['button'] == 0 &&
            (event['type'] == 'mousedown' || event['type'] == 'mouseup'))
        .toList();
    final rightPressEvents = events
        .where((event) =>
            event['button'] == 2 &&
            (event['type'] == 'mousedown' || event['type'] == 'mouseup'))
        .toList();

    expect(leftPressEvents, isEmpty);
    expect(
      rightPressEvents.map((event) => event['type']),
      ['mousedown', 'mouseup'],
    );
  });

  test('touch cancellation clears a two-finger candidate without a right-click',
      () async {
    final result = await _runTouchScenario(r'''
const first = touch(20, 30);
const second = touch(40, 50);

dispatchTouch('touchstart', [first], [first]);
flushTasks();
dispatchTouch('touchstart', [first, second], [second]);
flushTasks();
dispatchTouch('touchcancel', [], [first, second]);
flushTasks();

writeResult();
''');

    final events =
        (result['events'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(events.where((event) => event['button'] == 2), isEmpty);
  });

  test('two-finger hold beyond the tap duration does not right-click',
      () async {
    final result = await _runTouchScenario(r'''
const first = touch(20, 30);
const second = touch(40, 50);

dispatchTouch('touchstart', [first], [first]);
flushTasks();
dispatchTouch('touchstart', [first, second], [second]);
flushTasks();
advanceTime(251);
dispatchTouch('touchend', [first], [second]);
dispatchTouch('touchend', [], [first]);
flushTasks();

writeResult();
''');

    final events =
        (result['events'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(events.where((event) => event['button'] == 2), isEmpty);
  });

  test('single-finger moves are coalesced to the latest animation frame',
      () async {
    final result = await _runTouchScenario(r'''
const start = touch(20, 30);

dispatchTouch('touchstart', [start], [start]);
flushTasks();
clearEvents();

const firstMove = touch(30, 40);
const secondMove = touch(40, 50);
const latestMove = touch(50, 60);
dispatchTouch('touchmove', [firstMove], [firstMove]);
dispatchTouch('touchmove', [secondMove], [secondMove]);
dispatchTouch('touchmove', [latestMove], [latestMove]);
flushTasks();

writeResult();
''');

    final events =
        (result['events'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(events, hasLength(1));
    expect(events.single, containsPair('type', 'mousemove'));
    expect(events.single, containsPair('buttons', 1));
    expect(events.single, containsPair('clientX', 50));
    expect(events.single, containsPair('clientY', 60));
  });

  test('ending a touch cancels a pending mouse move', () async {
    final result = await _runTouchScenario(r'''
const start = touch(20, 30);
const moved = touch(50, 60);

dispatchTouch('touchstart', [start], [start]);
flushTasks();
clearEvents();
dispatchTouch('touchmove', [moved], [moved]);
dispatchTouch('touchend', [], [moved]);
flushTasks();

writeResult();
''');

    final events =
        (result['events'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(events, hasLength(1));
    expect(events.single, containsPair('type', 'mouseup'));
    expect(events.single, containsPair('buttons', 0));
  });

  test('window blur releases an active left mouse press', () async {
    final result = await _runTouchScenario(r'''
const start = touch(20, 30);

dispatchTouch('touchstart', [start], [start]);
flushTasks();
clearEvents();
dispatchWindowEvent('blur');
flushTasks();

writeResult();
''');

    final events =
        (result['events'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(events, hasLength(1));
    expect(events.single, containsPair('type', 'mouseup'));
    expect(events.single, containsPair('buttons', 0));
  });

  test('hiding the document releases an active left mouse press', () async {
    final result = await _runTouchScenario(r'''
const start = touch(20, 30);

dispatchTouch('touchstart', [start], [start]);
flushTasks();
clearEvents();
document.hidden = true;
dispatchDocumentEvent('visibilitychange');
flushTasks();

writeResult();
''');

    final events =
        (result['events'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(events, hasLength(1));
    expect(events.single, containsPair('type', 'mouseup'));
    expect(events.single, containsPair('buttons', 0));
  });

  test('quick single-finger tap dispatches a complete left-click', () async {
    final result = await _runTouchScenario(r'''
const point = touch(20, 30);

dispatchTouch('touchstart', [point], [point]);
dispatchTouch('touchend', [], [point]);
flushTasks();

writeResult();
''');

    final leftEvents = (result['events'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((event) => event['button'] == 0)
        .toList();
    expect(
      leftEvents.map((event) => event['type']),
      ['mousemove', 'mousedown', 'mouseup'],
    );
    expect(leftEvents[1], containsPair('buttons', 1));
    expect(leftEvents[2], containsPair('buttons', 0));
  });

  test('single tap presses after the game consumes the pointer position',
      () async {
    final result = await _runTouchScenario(r'''
enableDeferredGameCursorUpdates();
const point = touch(20, 30);

dispatchTouch('touchstart', [point], [point]);
dispatchTouch('touchend', [], [point]);
flushTasks();

writeResult();
''');

    expect(result['successfulLeftDowns'], 1);
  });

  test('two-finger scrolling stays on the gesture start target', () async {
    final result = await _runTouchScenario(r'''
const first = touch(20, 30);
const second = touch(40, 50);
const movedFirst = touch(20, 50);
const movedSecond = touch(40, 70);

dispatchTouch('touchstart', [first], [first]);
flushTasks();
dispatchTouch('touchstart', [first, second], [second]);
flushTasks();
setHitTarget(overlay);
dispatchTouch('touchmove', [movedFirst, movedSecond], [movedFirst, movedSecond]);

writeResult();
''');

    final wheelEvents = (result['events'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((event) => event['type'] == 'wheel')
        .toList();
    expect(wheelEvents, hasLength(1));
    expect(wheelEvents.single, containsPair('target', 'canvas'));
  });

  test('horizontal two-finger movement cancels right-click without zero wheel',
      () async {
    final result = await _runTouchScenario(r'''
const first = touch(20, 30);
const second = touch(40, 50);
const movedFirst = touch(40, 30);
const movedSecond = touch(60, 50);

dispatchTouch('touchstart', [first], [first]);
flushTasks();
dispatchTouch('touchstart', [first, second], [second]);
flushTasks();
dispatchTouch('touchmove', [movedFirst, movedSecond], [movedFirst, movedSecond]);
dispatchTouch('touchend', [movedFirst], [movedSecond]);
dispatchTouch('touchend', [], [movedFirst]);
flushTasks();

writeResult();
''');

    final events =
        (result['events'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(events.where((event) => event['button'] == 2), isEmpty);
    expect(events.where((event) => event['type'] == 'wheel'), isEmpty);
  });

  test('removing the gesture target releases an active left mouse press',
      () async {
    final result = await _runTouchScenario(r'''
const start = touch(20, 30);

dispatchTouch('touchstart', [start], [start]);
flushTasks();
clearEvents();
canvas.isConnected = false;
triggerMutations();
flushTasks();

writeResult();
''');

    final events =
        (result['events'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(events, hasLength(1));
    expect(events.single, containsPair('type', 'mouseup'));
    expect(events.single, containsPair('buttons', 0));
  });

  test('touching a text input preserves native activation', () async {
    final result = await _runTouchScenario(r'''
const point = touch(20, 30, input);

const startEvent = dispatchTouch('touchstart', [point], [point]);
const endEvent = dispatchTouch('touchend', [], [point]);
flushTasks();

writeResult({
  startDefaultPrevented: startEvent.defaultPrevented,
  endDefaultPrevented: endEvent.defaultPrevented
});
''');

    expect(result['startDefaultPrevented'], isFalse);
    expect(result['endDefaultPrevented'], isFalse);
    expect(result['events'], isEmpty);
  });

  test('touching a GP-Next overlay control preserves native activation',
      () async {
    final result = await _runTouchScenario(r'''
const point = touch(20, 30, gpButton);

const startEvent = dispatchTouch('touchstart', [point], [point]);
const endEvent = dispatchTouch('touchend', [], [point]);
flushTasks();

writeResult({
  startDefaultPrevented: startEvent.defaultPrevented,
  endDefaultPrevented: endEvent.defaultPrevented
});
''');

    expect(result['startDefaultPrevented'], isFalse);
    expect(result['endDefaultPrevented'], isFalse);
    expect(result['events'], isEmpty);
  });

  test('touching the GP-Next hint preserves native activation', () async {
    final result = await _runTouchScenario(r'''
const point = touch(20, 30, gpHint);

const startEvent = dispatchTouch('touchstart', [point], [point]);
const endEvent = dispatchTouch('touchend', [], [point]);
flushTasks();

writeResult({
  startDefaultPrevented: startEvent.defaultPrevented,
  endDefaultPrevented: endEvent.defaultPrevented
});
''');

    expect(result['startDefaultPrevented'], isFalse);
    expect(result['endDefaultPrevented'], isFalse);
    expect(result['events'], isEmpty);
  });

  test('touching a GP-Next toast preserves native activation', () async {
    final result = await _runTouchScenario(r'''
const point = touch(20, 30, gpToast);

const startEvent = dispatchTouch('touchstart', [point], [point]);
const endEvent = dispatchTouch('touchend', [], [point]);
flushTasks();

writeResult({
  startDefaultPrevented: startEvent.defaultPrevented,
  endDefaultPrevented: endEvent.defaultPrevented
});
''');

    expect(result['startDefaultPrevented'], isFalse);
    expect(result['endDefaultPrevented'], isFalse);
    expect(result['events'], isEmpty);
  });

  test('a GP-Next gesture stays native until every finger is lifted', () async {
    final result = await _runTouchScenario(r'''
const first = touch(20, 30, gpButton);
const second = touch(40, 50, canvas);
const third = touch(60, 70, canvas);

const startEvent = dispatchTouch('touchstart', [first], [first]);
const secondStartEvent = dispatchTouch(
  'touchstart',
  [first, second],
  [second]
);
const thirdStartEvent = dispatchTouch(
  'touchstart',
  [first, second, third],
  [third]
);
const moveEvent = dispatchTouch(
  'touchmove',
  [first, second, third],
  [first, second, third]
);
dispatchTouch('touchend', [first, second], [third]);
dispatchTouch('touchend', [first], [second]);
const nativeEndEvent = dispatchTouch('touchend', [], [first]);
flushTasks();

const gamePoint = touch(80, 90, canvas);
dispatchTouch('touchstart', [gamePoint], [gamePoint]);
dispatchTouch('touchend', [], [gamePoint]);
flushTasks();

writeResult({
  nativeEventsPrevented: [
    startEvent,
    secondStartEvent,
    thirdStartEvent,
    moveEvent,
    nativeEndEvent
  ].some((event) => event.defaultPrevented)
});
''');

    expect(result['nativeEventsPrevented'], isFalse);
    final events =
        (result['events'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(
      events.map((event) => event['type']),
      ['mousemove', 'mousedown', 'mouseup'],
    );
  });

  test('the first GP-Next backdrop tap is consumed without closing', () async {
    final result = await _runTouchScenario(r'''
openGpNext();
const point = touch(600, 100, canvas);

const startEvent = dispatchTouch('touchstart', [point], [point]);
const endEvent = dispatchTouch('touchend', [], [point]);
flushTasks();

writeResult({
  startDefaultPrevented: startEvent.defaultPrevented,
  endDefaultPrevented: endEvent.defaultPrevented
});
''');

    expect(result['startDefaultPrevented'], isTrue);
    expect(result['endDefaultPrevented'], isTrue);
    expect(result['gpNextHideCount'], 0);
    expect(result['events'], isEmpty);
  });

  test('double tapping the GP-Next backdrop closes it without game input',
      () async {
    final result = await _runTouchScenario(r'''
openGpNext();
const first = touch(600, 100, canvas);

dispatchTouch('touchstart', [first], [first]);
dispatchTouch('touchend', [], [first]);
advanceTime(100);

const second = touch(600, 100, canvas);
dispatchTouch('touchstart', [second], [second]);
dispatchTouch('touchend', [], [second]);
flushTasks();

writeResult();
''');

    expect(result['gpNextHideCount'], 1);
    expect(result['events'], isEmpty);
  });

  test('dragging the GP-Next backdrop does not complete a double tap',
      () async {
    final result = await _runTouchScenario(r'''
openGpNext();
const first = touch(600, 100, canvas);

dispatchTouch('touchstart', [first], [first]);
dispatchTouch('touchend', [], [first]);
advanceTime(50);

const dragStart = touch(600, 100, canvas);
const dragEnd = touch(620, 100, canvas);
dispatchTouch('touchstart', [dragStart], [dragStart]);
dispatchTouch('touchmove', [dragEnd], [dragEnd]);
dispatchTouch('touchend', [], [dragEnd]);
flushTasks();

writeResult();
''');

    expect(result['gpNextHideCount'], 0);
    expect(result['events'], isEmpty);
  });

  test('a multi-touch backdrop gesture does not complete a double tap',
      () async {
    final result = await _runTouchScenario(r'''
openGpNext();
const firstTap = touch(600, 100, canvas);

dispatchTouch('touchstart', [firstTap], [firstTap]);
dispatchTouch('touchend', [], [firstTap]);
advanceTime(50);

const first = touch(600, 100, canvas);
const second = touch(620, 120, canvas);
dispatchTouch('touchstart', [first], [first]);
dispatchTouch('touchstart', [first, second], [second]);
dispatchTouch('touchend', [first], [second]);
dispatchTouch('touchend', [], [first]);
flushTasks();

writeResult();
''');

    expect(result['gpNextHideCount'], 0);
    expect(result['events'], isEmpty);
  });

  test('a long backdrop press resets the double-tap candidate', () async {
    final result = await _runTouchScenario(r'''
openGpNext();
const point = touch(600, 100, canvas);

dispatchTouch('touchstart', [point], [point]);
dispatchTouch('touchend', [], [point]);
advanceTime(10);

dispatchTouch('touchstart', [point], [point]);
advanceTime(251);
dispatchTouch('touchend', [], [point]);
advanceTime(10);

dispatchTouch('touchstart', [point], [point]);
dispatchTouch('touchend', [], [point]);
flushTasks();

writeResult();
''');

    expect(result['gpNextHideCount'], 0);
    expect(result['events'], isEmpty);
  });

  test('a distant backdrop tap starts a new double-tap candidate', () async {
    final result = await _runTouchScenario(r'''
openGpNext();
const first = touch(600, 100, canvas);
const distant = touch(630, 100, canvas);

dispatchTouch('touchstart', [first], [first]);
dispatchTouch('touchend', [], [first]);
advanceTime(100);
dispatchTouch('touchstart', [distant], [distant]);
dispatchTouch('touchend', [], [distant]);
const hideCountAfterDistantTap = gpNextHideCount;
advanceTime(100);
dispatchTouch('touchstart', [distant], [distant]);
dispatchTouch('touchend', [], [distant]);
flushTasks();

writeResult({hideCountAfterDistantTap});
''');

    expect(result['hideCountAfterDistantTap'], 0);
    expect(result['gpNextHideCount'], 1);
    expect(result['events'], isEmpty);
  });

  test('a GP-Next control touch interrupts backdrop double tapping', () async {
    final result = await _runTouchScenario(r'''
openGpNext();
const backdrop = touch(600, 100, canvas);
const control = touch(100, 100, gpButton);

dispatchTouch('touchstart', [backdrop], [backdrop]);
dispatchTouch('touchend', [], [backdrop]);
advanceTime(50);
dispatchTouch('touchstart', [control], [control]);
dispatchTouch('touchend', [], [control]);
advanceTime(50);
dispatchTouch('touchstart', [backdrop], [backdrop]);
dispatchTouch('touchend', [], [backdrop]);
flushTasks();

writeResult();
''');

    expect(result['gpNextHideCount'], 0);
    expect(result['events'], isEmpty);
  });

  test('a late backdrop tap starts a new double-tap candidate', () async {
    final result = await _runTouchScenario(r'''
openGpNext();
const point = touch(600, 100, canvas);

dispatchTouch('touchstart', [point], [point]);
dispatchTouch('touchend', [], [point]);
advanceTime(301);
dispatchTouch('touchstart', [point], [point]);
dispatchTouch('touchend', [], [point]);
const hideCountAfterLateTap = gpNextHideCount;
advanceTime(100);
dispatchTouch('touchstart', [point], [point]);
dispatchTouch('touchend', [], [point]);
flushTasks();

writeResult({hideCountAfterLateTap});
''');

    expect(result['hideCountAfterLateTap'], 0);
    expect(result['gpNextHideCount'], 1);
    expect(result['events'], isEmpty);
  });

  test('a non-GP-Next button keeps the game mouse mapping', () async {
    final result = await _runTouchScenario(r'''
const point = touch(20, 30, gameButton);

const startEvent = dispatchTouch('touchstart', [point], [point]);
const endEvent = dispatchTouch('touchend', [], [point]);
flushTasks();

writeResult({
  startDefaultPrevented: startEvent.defaultPrevented,
  endDefaultPrevented: endEvent.defaultPrevented
});
''');

    expect(result['startDefaultPrevented'], isTrue);
    expect(result['endDefaultPrevented'], isTrue);
    final events =
        (result['events'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(
      events.map((event) => event['type']),
      ['mousemove', 'mousedown', 'mouseup'],
    );
  });

  test('closing GP-Next mid-gesture does not leak input to the game', () async {
    final result = await _runTouchScenario(r'''
openGpNext();
const start = touch(20, 30, gpButton);

const startEvent = dispatchTouch('touchstart', [start], [start]);
window.gpNext.hide();
const moved = touch(80, 90, canvas);
const moveEvent = dispatchTouch('touchmove', [moved], [moved]);
const endEvent = dispatchTouch('touchend', [], [moved]);
flushTasks();
const eventsBeforeNextGesture = events.length;

const next = touch(100, 110, canvas);
dispatchTouch('touchstart', [next], [next]);
dispatchTouch('touchend', [], [next]);
flushTasks();

writeResult({
  nativeEventsPrevented: [startEvent, moveEvent, endEvent]
    .some((event) => event.defaultPrevented),
  eventsBeforeNextGesture
});
''');

    expect(result['nativeEventsPrevented'], isFalse);
    expect(result['eventsBeforeNextGesture'], 0);
    final events =
        (result['events'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(
      events.map((event) => event['type']),
      ['mousemove', 'mousedown', 'mouseup'],
    );
  });
}

Future<Map<String, dynamic>> _runTouchScenario(String scenario) async {
  final process = await Process.run('node', [
    '-e',
    '''
const source = ${jsonEncode(gardendlessTouchPatchSource)};
$_nodeTouchHarness
eval(source);
$scenario
''',
  ]);

  expect(process.exitCode, 0, reason: process.stderr.toString());
  return jsonDecode(process.stdout as String) as Map<String, dynamic>;
}

const _nodeTouchHarness = r'''
const listeners = new Map();
const events = [];
const scheduledTasks = [];
const cancelledTasks = new Set();
const mutationObservers = [];
let currentTime = 0;
let nextTaskId = 0;
let deferGameCursorUpdates = false;
let gameCursorX = 0;
let gameCursorY = 0;
let successfulLeftDowns = 0;
let gpNextHideCount = 0;

function advanceTime(milliseconds) {
  currentTime += milliseconds;
}

function scheduleTask(callback) {
  nextTaskId += 1;
  scheduledTasks.push({id: nextTaskId, callback});
  return nextTaskId;
}

function cancelTask(taskId) {
  cancelledTasks.add(taskId);
}

function flushTasks() {
  while (scheduledTasks.length > 0) {
    const tasks = scheduledTasks.splice(0);
    for (const task of tasks) {
      if (!cancelledTasks.has(task.id)) {
        task.callback(currentTime);
      }
      cancelledTasks.delete(task.id);
    }
  }
}

function clearEvents() {
  events.length = 0;
}

function enableDeferredGameCursorUpdates() {
  deferGameCursorUpdates = true;
}

class SyntheticMouseEvent {
  constructor(type, init) {
    this.type = type;
    Object.assign(this, init);
  }
}

class SyntheticWheelEvent extends SyntheticMouseEvent {}

function makeTarget(name) {
  return {
    name,
    isConnected: true,
    dispatchEvent(event) {
      if (name === 'canvas' && event.type === 'mousemove') {
        const updateGameCursor = () => {
          gameCursorX = event.clientX;
          gameCursorY = event.clientY;
        };
        if (deferGameCursorUpdates) {
          requestAnimationFrame(updateGameCursor);
        } else {
          updateGameCursor();
        }
      }
      if (name === 'canvas' &&
          event.type === 'mousedown' &&
          event.button === 0 &&
          gameCursorX === event.clientX &&
          gameCursorY === event.clientY) {
        successfulLeftDowns += 1;
      }
      events.push({
        target: name,
        type: event.type,
        button: event.button ?? null,
        buttons: event.buttons ?? null,
        clientX: event.clientX ?? null,
        clientY: event.clientY ?? null,
        deltaY: event.deltaY ?? null,
        deltaMode: event.deltaMode ?? null
      });
      return true;
    }
  };
}

class SyntheticMutationObserver {
  constructor(callback) {
    this.callback = callback;
    mutationObservers.push(this);
  }

  observe() {}
}

function triggerMutations() {
  for (const observer of mutationObservers) {
    observer.callback([]);
  }
}

const canvas = makeTarget('canvas');
const body = makeTarget('body');
const overlay = makeTarget('overlay');
const input = makeTarget('input');
input.tagName = 'INPUT';
const gameButton = makeTarget('game-button');
gameButton.tagName = 'BUTTON';
gameButton.parentElement = body;
const gpOverlay = makeTarget('gp-overlay');
gpOverlay.id = 'gp-overlay';
gpOverlay.parentElement = body;
const gpButton = makeTarget('gp-button');
gpButton.tagName = 'BUTTON';
gpButton.parentElement = gpOverlay;
const gpHint = makeTarget('gp-hint');
gpHint.className = 'gp-f1-hint';
gpHint.parentElement = body;
const gpToastWrap = makeTarget('gp-toast-wrap');
gpToastWrap.id = 'ge-toast-wrap';
gpToastWrap.parentElement = body;
const gpToast = makeTarget('gp-toast');
gpToast.parentElement = gpToastWrap;
const gpOverlayClasses = new Set();
gpOverlay.classList = {
  add(name) {
    gpOverlayClasses.add(name);
  },
  remove(name) {
    gpOverlayClasses.delete(name);
  },
  contains(name) {
    return gpOverlayClasses.has(name);
  }
};
let hitTarget = canvas;
const window = makeTarget('window');
window.gpNext = {
  hide() {
    gpNextHideCount += 1;
    gpOverlay.classList.remove('gp-open');
  }
};
window.addEventListener = function (type, listener) {
  listeners.set(`window:${type}`, listener);
};
const document = {
  activeElement: canvas,
  body,
  hidden: false,
  addEventListener(type, listener) {
    listeners.set(type, listener);
  },
  dispatchEvent: makeTarget('document').dispatchEvent,
  elementFromPoint() {
    return hitTarget;
  },
  getElementById(id) {
    if (id === 'GameCanvas') {
      return canvas;
    }
    if (id === 'gp-overlay') {
      return gpOverlay;
    }
    return null;
  }
};

function openGpNext() {
  gpOverlay.classList.add('gp-open');
}

function setHitTarget(target) {
  hitTarget = target;
}

function touch(clientX, clientY, target = canvas) {
  return {
    identifier: clientX * 1000 + clientY,
    target,
    screenX: clientX,
    screenY: clientY,
    clientX,
    clientY
  };
}

function dispatchTouch(type, touches, changedTouches) {
  const event = {
    type,
    touches,
    changedTouches,
    defaultPrevented: false,
    propagationStopped: false,
    preventDefault() {
      this.defaultPrevented = true;
    },
    stopPropagation() {
      this.propagationStopped = true;
    }
  };
  listeners.get(type)?.(event);
  return event;
}

function dispatchWindowEvent(type) {
  listeners.get(`window:${type}`)?.({type});
}

function dispatchDocumentEvent(type) {
  listeners.get(type)?.({type});
}

function writeResult(extra = {}) {
  process.stdout.write(JSON.stringify({
    events,
    successfulLeftDowns,
    gpNextHideCount,
    ...extra
  }));
}

globalThis.MouseEvent = SyntheticMouseEvent;
globalThis.MutationObserver = SyntheticMutationObserver;
globalThis.WheelEvent = SyntheticWheelEvent;
globalThis.document = document;
globalThis.window = window;
globalThis.setTimeout = scheduleTask;
globalThis.clearTimeout = cancelTask;
globalThis.requestAnimationFrame = scheduleTask;
globalThis.cancelAnimationFrame = cancelTask;
globalThis.performance = {
  now() {
    return currentTime;
  }
};
''';
