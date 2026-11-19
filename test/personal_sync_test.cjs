const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function endpoint() {
  const rows = [];
  const sheet = {
    getLastRow() {
      let count = rows.length;
      while (count && rows[count - 1].every(value => value === '')) count--;
      return count;
    },
    getMaxRows: () => 100,
    getMaxColumns: () => 26,
    setFrozenRows() {},
    getRange(row, column, height, width) {
      return {
        setValues(values) {
          values.forEach((cells, i) => {
            rows[row - 1 + i] ??= [];
            cells.forEach((value, j) => rows[row - 1 + i][column - 1 + j] =
              typeof value === 'string' && value.startsWith("'") ? value.slice(1) : value);
          });
        },
        getDisplayValues: () => Array.from({ length: height }, (_, i) =>
          Array.from({ length: width }, (_, j) => String(rows[row - 1 + i]?.[column - 1 + j] ?? ''))),
        clearContent() {
          for (let i = 0; i < height; i++) rows[row - 1 + i] = Array(width).fill('');
        },
      };
    },
  };
  let created = false;
  const context = vm.createContext({
    SpreadsheetApp: {
      openById: () => ({ getSheetByName: () => created ? sheet : null,
        insertSheet: () => { created = true; return sheet; } }),
      flush() {},
    },
    LockService: { getScriptLock: () => ({ waitLock() {}, releaseLock() {} }) },
    ContentService: { MimeType: { JSON: 'json' },
      createTextOutput: value => ({ setMimeType: () => JSON.parse(value) }) },
  });
  vm.runInContext(fs.readFileSync('docs/personal-sync.gs', 'utf8'), context);
  return { rows, get: () => context.doGet(), post: entries => context.doPost({
    postData: { contents: JSON.stringify({ version: 4, mode: 'replace', entries }) },
  }) };
}

function result(values = {}) {
  const item = {table: 'Words', entry: 'one', failedCount: 0, almostCount: 0, successCount: 0, ...values};
  return {...item, appearedCount: item.failedCount + item.almostCount + item.successCount};
}

test('creates counter columns and keeps Importance blank when unset', () => {
  const api = endpoint();
  assert.deepEqual(api.get(), {ok: true, version: 4, entries: []});
  assert.deepEqual(api.rows[0], ['Table', 'Entry', 'Appeared Count', 'Failed Count', 'Almost Count', 'Success Count', 'Importance', 'Comment']);
  assert.equal(api.post([result({entry: '=one', failedCount: 2, almostCount: 3, successCount: 4})]).ok, true);
  assert.deepEqual(api.rows[1], ['Words', '=one', 9, 2, 3, 4, '', '']);
  assert.deepEqual(api.get().entries, [result({entry: '=one', importance: null, failedCount: 2, almostCount: 3, successCount: 4})]);
});

test('resetting Importance retains counters and an empty snapshot clears results', () => {
  const api = endpoint();
  api.post([result({importance: 3, successCount: 8}), result({entry: 'two', importance: 0})]);
  api.post([result({importance: null, successCount: 8}), result({entry: 'two', importance: null})]);
  assert.deepEqual(api.get().entries, [result({importance: null, successCount: 8})]);
  api.post([]);
  assert.deepEqual(api.get().entries, []);
  assert.equal(api.rows.slice(1).every(row => row.every(value => value === '')), true);
});

test('negative and inconsistent counts leave the old snapshot intact', () => {
  const api = endpoint();
  api.post([result({successCount: 8})]);
  assert.equal(api.post([result({failedCount: -1})]).ok, false);
  assert.equal(api.post([{...result({successCount: 2}), appearedCount: 20}]).ok, false);
  assert.equal(api.get().entries[0].successCount, 8);
});

test('upgrades an existing results sheet and syncs comments without ratings', () => {
  const api = endpoint();
  api.post([result({successCount: 8})]);
  api.rows[0].pop();
  api.rows[1].pop();
  assert.deepEqual(api.get().entries, [result({importance: null, successCount: 8})]);
  assert.equal(api.rows[0][7], 'Comment');

  const comment = '=1+1\nSecond line';
  const note = result({entry: 'two', comment});
  assert.equal(api.post([result({successCount: 8}), note]).ok, true);
  assert.deepEqual(api.get().entries, [
    result({importance: null, successCount: 8}),
    {...note, importance: null},
  ]);
  assert.equal(api.post([result({successCount: 8}), result({entry: 'two'})]).ok, true);
  assert.deepEqual(api.get().entries, [result({importance: null, successCount: 8})]);
});

test('legacy four and five column sheets migrate Importance without fabricating outcomes', () => {
  for (const headers of [['Table', 'Entry', 'Importance', 'Success'], ['Table', 'Entry', 'Importance', 'Success', 'Appered']]) {
    const api = endpoint();
    api.get();
    api.rows[0] = headers;
    api.rows.push(['Words', 'one', 8, 9, 12]);
    api.rows.push(['Words', 'two', '', 7, 5]);
    assert.deepEqual(api.get().entries, [result({importance: 8})]);
    assert.equal(api.rows[0].length, 8);
  }
});
