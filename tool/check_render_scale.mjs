import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(
  new URL('../assets/game_bridge/render_scale.js', import.meta.url),
  'utf8',
);

function run(renderScale, realRatio = 2) {
  const display = {ratio: realRatio};
  const window = {};
  Object.defineProperty(window, 'devicePixelRatio', {
    configurable: true,
    enumerable: true,
    get: () => display.ratio,
  });
  window.__gardendlessHost = {config: {renderScale}};
  vm.runInNewContext(source, {window});
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

console.log('render_scale.js checks passed');
