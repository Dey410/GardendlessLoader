import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(
  new URL('../assets/game_bridge/js_modding.js', import.meta.url),
  'utf8',
);

function run({config, stored}) {
  let value = stored;
  let writeCount = 0;
  const warnings = [];
  const window = {
    __gardendlessHost: {config},
    localStorage: {
      getItem(key) {
        assert.equal(key, 'gp-next-settings');
        return value;
      },
      setItem(key, next) {
        assert.equal(key, 'gp-next-settings');
        value = next;
        writeCount += 1;
      },
    },
  };
  const context = {
    JSON,
    Object,
    console: {warn: (...args) => warnings.push(args)},
    window,
  };
  vm.createContext(context);
  vm.runInContext(source, context);
  return {value, warnings, writeCount};
}

const enabled = run({
  config: {
    hasGpNext: true,
    gpNextCompatible: true,
    jsModdingEnabled: true,
  },
  stored: JSON.stringify({
    version: 2,
    locale: 'zh-CN',
    experimental: {jsModding: false, worldMapJson: true},
  }),
});
assert.equal(enabled.writeCount, 1);
assert.deepEqual(JSON.parse(enabled.value), {
  version: 2,
  locale: 'zh-CN',
  experimental: {jsModding: true, worldMapJson: true},
});

const disabled = run({
  config: {
    hasGpNext: true,
    gpNextCompatible: true,
    jsModdingEnabled: false,
  },
  stored: JSON.stringify({experimental: {jsModding: true}}),
});
assert.equal(JSON.parse(disabled.value).experimental.jsModding, false);

const repaired = run({
  config: {
    hasGpNext: true,
    gpNextCompatible: true,
    jsModdingEnabled: true,
  },
  stored: '{not-json',
});
assert.deepEqual(JSON.parse(repaired.value), {
  experimental: {jsModding: true},
});

for (const config of [
  {hasGpNext: false, gpNextCompatible: false, jsModdingEnabled: true},
  {hasGpNext: true, gpNextCompatible: false, jsModdingEnabled: true},
]) {
  const skipped = run({config, stored: '{"untouched":true}'});
  assert.equal(skipped.writeCount, 0);
  assert.equal(skipped.value, '{"untouched":true}');
}

console.log('JS Modding settings contract passes');
