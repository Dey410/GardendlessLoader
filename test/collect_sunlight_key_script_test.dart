import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/web/collect_sunlight_key_press.dart';

void main() {
  test('one collection cycle bubbles one A key press through the document',
      () async {
    final process = await Process.run('node', [
      '-e',
      '''
const source = ${jsonEncode(gardendlessCollectSunlightKeyPressScript)};
$_nodeKeyboardHarness
eval(source);
flushTasks();
process.stdout.write(JSON.stringify(receivedEvents));
''',
    ]);

    expect(process.exitCode, 0, reason: process.stderr.toString());
    final events = (jsonDecode(process.stdout as String) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(
      events.map((event) => event['type']),
      ['keydown', 'keyup'],
    );
    expect(events.every((event) => event['key'] == 'a'), isTrue);
    expect(events.every((event) => event['code'] == 'KeyA'), isTrue);
  });
}

const _nodeKeyboardHarness = r'''
const scheduledTasks = [];
const receivedEvents = [];

function flushTasks() {
  while (scheduledTasks.length > 0) {
    const tasks = scheduledTasks.splice(0);
    for (const task of tasks) {
      task();
    }
  }
}

class SyntheticKeyboardEvent {
  constructor(type, init) {
    this.type = type;
    Object.assign(this, init);
  }
}

function makeTarget(name, parent) {
  const listeners = new Map();
  return {
    name,
    parent,
    addEventListener(type, listener) {
      const current = listeners.get(type) || [];
      current.push(listener);
      listeners.set(type, current);
    },
    dispatchEvent(event) {
      let target = this;
      while (target) {
        const targetListeners = target.__listeners?.get(event.type) || [];
        for (const listener of targetListeners) {
          listener(event);
        }
        target = event.bubbles ? target.parent : null;
      }
      return true;
    },
    __listeners: listeners
  };
}

const window = makeTarget('window', null);
const document = makeTarget('document', window);
const canvas = makeTarget('canvas', document);
document.activeElement = canvas;
document.getElementById = function (id) {
  return id === 'GameCanvas' ? canvas : null;
};
window.addEventListener('keydown', function (event) {
  receivedEvents.push({type: event.type, key: event.key, code: event.code});
});
window.addEventListener('keyup', function (event) {
  receivedEvents.push({type: event.type, key: event.key, code: event.code});
});

globalThis.KeyboardEvent = SyntheticKeyboardEvent;
globalThis.document = document;
globalThis.window = window;
globalThis.setTimeout = function (callback) {
  scheduledTasks.push(callback);
  return scheduledTasks.length;
};
''';
