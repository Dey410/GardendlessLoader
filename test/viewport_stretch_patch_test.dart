import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/web/viewport_stretch_patch.dart';

void main() {
  test('game page injects and toggles the viewport stretch patch', () async {
    final gamePageSource =
        await File('lib/src/ui/game_page.dart').readAsString();

    expect(gamePageSource, contains('gardendlessViewportStretchPatchSource'));
    expect(gamePageSource, contains('gardendlessViewportStretchToggleScript'));
    expect(gamePageSource, contains('onLoadStop'));
  });

  test('viewport stretch toggle script forwards the requested state', () {
    expect(
      gardendlessViewportStretchToggleScript(enabled: true),
      'window.__gardendlessSetViewportStretch?.(true);',
    );
    expect(
      gardendlessViewportStretchToggleScript(enabled: false),
      'window.__gardendlessSetViewportStretch?.(false);',
    );
  });

  test('viewport stretch patch forces canvas and containers to fill viewport',
      () async {
    final result = await _runViewportStretchScenario(r'''
eval(source);
window.__gardendlessSetViewportStretch(true);

process.stdout.write(JSON.stringify({
  htmlDataset: html.dataset.gardendlessViewportStretch,
  bodyOverflow: body.style.getPropertyValue('overflow'),
  canvasPosition: canvas.style.getPropertyValue('position'),
  canvasInset: canvas.style.getPropertyValue('inset'),
  canvasWidth: canvas.style.getPropertyValue('width'),
  canvasHeight: canvas.style.getPropertyValue('height'),
  canvasObjectFit: canvas.style.getPropertyValue('object-fit'),
  containerWidth: container.style.getPropertyValue('width'),
  containerHeight: container.style.getPropertyValue('height'),
  styleTagText: head.children.map((child) => child.textContent).join('\n'),
  ccCalls: ccCalls
}));
''');

    expect(result['htmlDataset'], 'true');
    expect(result['bodyOverflow'], 'hidden');
    expect(result['canvasPosition'], 'fixed');
    expect(result['canvasInset'], '0px');
    expect(result['canvasWidth'], '100vw');
    expect(result['canvasHeight'], '100vh');
    expect(result['canvasObjectFit'], 'fill');
    expect(result['containerWidth'], '100vw');
    expect(result['containerHeight'], '100vh');
    expect(result['styleTagText'], contains('100vw'));
    expect(result['styleTagText'], contains('100vh'));

    final ccCalls = result['ccCalls'] as List<dynamic>;
    expect(
      ccCalls,
      contains(
        containsPair('policy', 'EXACT_FIT'),
      ),
    );
  });

  test('viewport stretch patch restores inline styles when disabled', () async {
    final result = await _runViewportStretchScenario(r'''
canvas.style.setProperty('width', '720px');
canvas.style.setProperty('height', '405px');
eval(source);

window.__gardendlessSetViewportStretch(true);
window.__gardendlessSetViewportStretch(false);

process.stdout.write(JSON.stringify({
  htmlDataset: html.dataset.gardendlessViewportStretch || null,
  canvasWidth: canvas.style.getPropertyValue('width'),
  canvasHeight: canvas.style.getPropertyValue('height'),
  styleDisabled: head.children[0].disabled === true
}));
''');

    expect(result['htmlDataset'], isNull);
    expect(result['canvasWidth'], '720px');
    expect(result['canvasHeight'], '405px');
    expect(result['styleDisabled'], isTrue);
  });
}

Future<Map<String, dynamic>> _runViewportStretchScenario(
  String scenario,
) async {
  final process = await Process.run('node', [
    '-e',
    '''
const source = ${jsonEncode(gardendlessViewportStretchPatchSource)};
$_nodeDomHarness
$scenario
''',
  ]);

  expect(
    process.exitCode,
    0,
    reason: process.stderr.toString(),
  );
  return jsonDecode(process.stdout as String) as Map<String, dynamic>;
}

const _nodeDomHarness = r'''
function cssNameToJs(name) {
  return name.replace(/-([a-z])/g, function (_, letter) {
    return letter.toUpperCase();
  });
}

function createStyle() {
  const values = new Map();
  const priorities = new Map();
  return {
    setProperty(name, value, priority) {
      values.set(name, value);
      priorities.set(name, priority || '');
      this[cssNameToJs(name)] = value;
    },
    getPropertyValue(name) {
      return values.get(name) || this[cssNameToJs(name)] || '';
    },
    getPropertyPriority(name) {
      return priorities.get(name) || '';
    },
    removeProperty(name) {
      values.delete(name);
      priorities.delete(name);
      this[cssNameToJs(name)] = '';
    }
  };
}

const elementsById = {};

function makeElement(tagName, id) {
  const element = {
    tagName: tagName.toUpperCase(),
    id: id || '',
    style: createStyle(),
    dataset: {},
    children: [],
    parentNode: null,
    textContent: '',
    disabled: false,
    appendChild(child) {
      child.parentNode = this;
      this.children.push(child);
      return child;
    },
    setAttribute(name, value) {
      if (name === 'id') {
        this.id = value;
        elementsById[value] = this;
        return;
      }
      this[name] = value;
    },
    getAttribute(name) {
      if (name === 'id') {
        return this.id;
      }
      return this[name] || null;
    }
  };

  if (id) {
    elementsById[id] = element;
  }
  return element;
}

const html = makeElement('html');
const head = makeElement('head');
const body = makeElement('body');
const gameDiv = makeElement('div', 'GameDiv');
const container = makeElement('div', 'Cocos3dGameContainer');
const canvas = makeElement('canvas', 'GameCanvas');
const secondaryCanvas = makeElement('canvas');
html.appendChild(head);
html.appendChild(body);
body.appendChild(gameDiv);
gameDiv.appendChild(container);
container.appendChild(canvas);
body.appendChild(secondaryCanvas);

const allElements = [
  html,
  head,
  body,
  gameDiv,
  container,
  canvas,
  secondaryCanvas
];
const listeners = {};
const ccCalls = [];

const document = {
  documentElement: html,
  head: head,
  body: body,
  createElement(tagName) {
    return makeElement(tagName);
  },
  getElementById(id) {
    return elementsById[id] || null;
  },
  querySelectorAll(selectorText) {
    const selectors = selectorText.split(',').map((selector) => selector.trim());
    return allElements.filter((element) => {
      return selectors.some((selector) => {
        if (selector === 'html') {
          return element === html;
        }
        if (selector === 'body') {
          return element === body;
        }
        if (selector === 'canvas') {
          return element.tagName === 'CANVAS';
        }
        if (selector.startsWith('#')) {
          return element.id === selector.slice(1);
        }
        return false;
      });
    });
  },
  addEventListener(type, callback) {
    listeners[type] = callback;
  }
};

const window = {
  innerWidth: 1024,
  innerHeight: 768,
  devicePixelRatio: 2,
  cc: {
    ResolutionPolicy: {
      EXACT_FIT: 'EXACT_FIT'
    },
    view: {
      getDesignResolutionSize() {
        return { width: 1280, height: 720 };
      },
      setDesignResolutionSize(width, height, policy) {
        ccCalls.push({ width: width, height: height, policy: policy });
      },
      resizeWithBrowserSize(enabled) {
        ccCalls.push({ resizeWithBrowserSize: enabled });
      }
    }
  },
  addEventListener(type, callback) {
    listeners[type] = callback;
  },
  requestAnimationFrame(callback) {
    callback();
    return 1;
  },
  setTimeout(callback) {
    callback();
    return 1;
  },
  clearTimeout() {}
};

class MutationObserver {
  constructor(callback) {
    this.callback = callback;
  }

  observe() {}
  disconnect() {}
}

global.window = window;
global.document = document;
global.MutationObserver = MutationObserver;
global.requestAnimationFrame = window.requestAnimationFrame;
global.setTimeout = window.setTimeout;
global.clearTimeout = window.clearTimeout;
''';
