import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(
  new URL('../assets/game_bridge/render_scale.js', import.meta.url),
  'utf8',
);

function run(renderPixelRatioCap, realRatio = 2) {
  const display = {ratio: realRatio};
  const window = {};
  Object.defineProperty(window, 'devicePixelRatio', {
    configurable: true,
    enumerable: true,
    get: () => display.ratio,
  });
  window.__gardendlessHost = {config: {renderPixelRatioCap}};
  vm.runInNewContext(source, {window});
  return {window, display};
}

{
  const {window, display} = run(1.5);
  assert.equal(window.devicePixelRatio, 1.5);
  display.ratio = 1;
  assert.equal(window.devicePixelRatio, 1, 'a lower real ratio is kept');
  display.ratio = 3;
  assert.equal(window.devicePixelRatio, 1.5, 'the cap follows ratio changes');
}

for (const cap of [null, undefined, 0, -1, '1']) {
  const {window} = run(cap);
  assert.equal(window.devicePixelRatio, 2, `cap ${String(cap)} leaves the ratio`);
}

console.log('render_scale.js checks passed');
