import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(
  new URL('../assets/game_bridge/render_scale.js', import.meta.url),
  'utf8',
);

function createWindow(realRatio) {
  const display = {ratio: realRatio};
  const window = {};
  Object.defineProperty(window, 'devicePixelRatio', {
    configurable: true,
    enumerable: true,
    get: () => display.ratio,
  });
  return {window, display};
}

function inject(window, renderScale) {
  window.__gardendlessHost = {config: {renderScale}};
  vm.runInNewContext(source, {window});
}

function run(renderScale, realRatio = 2) {
  const {window, display} = createWindow(realRatio);
  inject(window, renderScale);
  return {window, display};
}

{
  const {window, display} = run(0.75);
  assert.equal(window.devicePixelRatio, 1.5);
  display.ratio = 3;
  assert.equal(window.devicePixelRatio, 2.25, 'the scale follows ratio changes');
}

for (const scale of [null, undefined, 0, -1, '1']) {
  const {window} = run(scale);
  assert.equal(window.devicePixelRatio, 2, `scale ${String(scale)} leaves the ratio`);
}

{
  const {window, display} = run(0.75);
  inject(window, 0.75);
  assert.equal(
    window.devicePixelRatio,
    1.5,
    're-injecting the same scale must not multiply it',
  );
  inject(window, 0.5);
  assert.equal(
    window.devicePixelRatio,
    1,
    're-injecting a new scale must apply it exactly once',
  );
  display.ratio = 3;
  assert.equal(
    window.devicePixelRatio,
    1.5,
    'the wrapper still follows the live device ratio after re-injection',
  );
  inject(window, null);
  assert.equal(
    window.devicePixelRatio,
    1.5,
    'an invalid scale must not drop the installed wrapper',
  );
}

console.log('render_scale.js checks passed');
