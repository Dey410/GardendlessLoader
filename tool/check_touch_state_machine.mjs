import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(
  new URL('../assets/game_bridge/touch_state_machine.js', import.meta.url),
  'utf8',
);

function point(id, x, y) {
  return {id, screenX: x, screenY: y, clientX: x, clientY: y};
}

function loadMachine({trace} = {}) {
  const window = {};
  const context = {Math, window};
  context.globalThis = context;
  vm.createContext(context);
  vm.runInContext(source, context);
  return window.__gardendlessTouchStateMachine.create({trace});
}

function frame(phase, points, changedPoints = points, options = {}) {
  return {
    phase,
    points,
    changedPoints,
    time: options.time ?? 0,
    physicalPixelRatio: options.physicalPixelRatio ?? 1,
  };
}

function handle(machine, input) {
  return JSON.parse(JSON.stringify(machine.handle(input)));
}

{
  const machine = loadMachine();
  const start = point(1, 40, 30);
  const end = point(1, 180, 90);

  assert.deepEqual(handle(machine, frame('start', [start])), [
    {type: 'primaryDown', point: start},
  ]);
  assert.deepEqual(handle(machine, frame('move', [end])), [
    {type: 'primaryMove', point: end},
  ]);
  assert.deepEqual(handle(machine, frame('end', [], [end])), [
    {type: 'primaryUp', point: end},
  ]);
}

{
  const machine = loadMachine();
  const first = point(1, 80, 100);
  const second = point(2, 120, 100);
  const center = point(-1, 100, 100);

  handle(machine, frame('start', [first]));
  assert.deepEqual(
    handle(machine, frame('start', [first, second], [second])),
    [{type: 'neutralMove', point: center}],
    'the second finger must abandon primary drag without a primary-up',
  );
  assert.deepEqual(handle(machine, frame('end', [second], [first])), []);
  assert.deepEqual(handle(machine, frame('end', [], [second])), [
    {type: 'secondaryDown', point: center},
    {type: 'secondaryUp', point: center},
  ]);
}

{
  const machine = loadMachine();
  const first = point(1, 80, 100);
  const second = point(2, 120, 100);
  handle(machine, frame('start', [first]));
  handle(machine, frame('start', [first, second], [second]));

  const atSlopFirst = point(1, 80, 110);
  const atSlopSecond = point(2, 120, 110);
  assert.deepEqual(
    handle(machine, frame(
      'move',
      [atSlopFirst, atSlopSecond],
      [atSlopFirst, atSlopSecond],
      {physicalPixelRatio: 2},
    )),
    [],
    '20 physical pixels remains a right-click candidate',
  );

  const scrollFirst = point(1, 80, 112);
  const scrollSecond = point(2, 120, 112);
  assert.deepEqual(
    handle(machine, frame(
      'move',
      [scrollFirst, scrollSecond],
      [scrollFirst, scrollSecond],
      {physicalPixelRatio: 2},
    )),
    [{
      type: 'scroll',
      point: point(-1, 100, 112),
      physicalDeltaY: 4,
    }],
  );
  assert.deepEqual(handle(machine, frame('end', [], scrollSecond)), []);
}

{
  const machine = loadMachine();
  const first = point(1, 20, 20);
  const second = point(2, 40, 20);
  const third = point(3, 60, 20);
  handle(machine, frame('start', [first]));
  handle(machine, frame('start', [first, second], [second]));
  assert.deepEqual(
    handle(machine, frame('start', [first, second, third], [third])),
    [],
  );
  assert.deepEqual(handle(machine, frame('end', [first], [second, third])), []);
  assert.deepEqual(handle(machine, frame('end', [], [first])), []);
  assert.deepEqual(handle(machine, frame('start', [first])), [
    {type: 'primaryDown', point: first},
  ], 'three-finger gestures stay blocked until every finger is lifted');
}

{
  const traces = [];
  const machine = loadMachine({trace: (entry) => traces.push(entry)});
  const touch = point(1, 30, 30);
  handle(machine, frame('start', [touch]));
  assert.deepEqual(handle(machine, frame('cancel', [], [touch])), []);
  assert.deepEqual(handle(machine, frame('start', [touch])), [
    {type: 'primaryDown', point: touch},
  ]);
  assert.deepEqual(
    traces.map(({phase, from, to}) => ({phase, from, to})),
    [
      {phase: 'start', from: 'idle', to: 'primary'},
      {phase: 'cancel', from: 'primary', to: 'idle'},
      {phase: 'start', from: 'idle', to: 'primary'},
    ],
    'diagnostic traces expose transitions without inspecting internals',
  );
}

console.log('reference touch state machine contract passes');
