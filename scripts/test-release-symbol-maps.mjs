import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { resolve, join, sep } from 'node:path';
import { test } from 'node:test';
import { archiveReleaseSymbolMap } from '../hvigor/release-symbol-maps.ts';

const testParent = resolve('.tmp/release-symbol-map-tests');
mkdirSync(testParent, { recursive: true });

function fixture(t) {
  const root = mkdtempSync(join(testParent, 'case-'));
  t.after(() => {
    assert.ok(root.startsWith(testParent + sep));
    rmSync(root, { recursive: true });
  });
  const ets = join(root, 'ets');
  const mapping = join(root, 'mapping');
  mkdirSync(ets);
  return { ets, mapping };
}

test('符号表移出打包目录，归档保持原始字节且不改变字节码和源码映射', (t) => {
  const f = fixture(t);
  const symbol = Buffer.from('中文符号表\nmodule;symbol;123\n');
  writeFileSync(join(f.ets, 'symbolMap.map'), symbol);
  writeFileSync(join(f.ets, 'modules.abc'), 'bytecode');
  writeFileSync(join(f.ets, 'sourceMaps.map'), 'source-map');
  assert.equal(archiveReleaseSymbolMap(f.ets, f.mapping), true);
  assert.equal(existsSync(join(f.ets, 'symbolMap.map')), false);
  assert.deepEqual(readFileSync(join(f.mapping, 'symbolMap.map')), symbol);
  assert.equal(readFileSync(join(f.ets, 'modules.abc'), 'utf8'), 'bytecode');
  assert.equal(readFileSync(join(f.ets, 'sourceMaps.map'), 'utf8'), 'source-map');
});

test('没有符号表时允许首次构建，不创建空归档', (t) => {
  const f = fixture(t);
  assert.equal(archiveReleaseSymbolMap(f.ets, f.mapping), false);
  assert.equal(existsSync(f.mapping), false);
});

test('下一次编译重新生成符号表时归档更新为本次内容', (t) => {
  const f = fixture(t);
  for (const content of ['old-symbol', 'new-symbol']) {
    writeFileSync(join(f.ets, 'symbolMap.map'), content);
    archiveReleaseSymbolMap(f.ets, f.mapping);
  }
  assert.equal(readFileSync(join(f.mapping, 'symbolMap.map'), 'utf8'), 'new-symbol');
  assert.equal(archiveReleaseSymbolMap(f.ets, f.mapping), false);
});

test('归档失败时保留编译输出并使构建失败', (t) => {
  const f = fixture(t);
  writeFileSync(join(f.ets, 'symbolMap.map'), 'keep-on-failure');
  writeFileSync(f.mapping, 'not-a-directory');
  assert.throws(() => archiveReleaseSymbolMap(f.ets, f.mapping));
  assert.equal(readFileSync(join(f.ets, 'symbolMap.map'), 'utf8'), 'keep-on-failure');
});
