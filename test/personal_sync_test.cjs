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
    postData: { contents: JSON.stringify({ version: 2, mode: 'replace', entries }) },
  }) };
}

test('creates columns and keeps unset ratings blank', () => {
  const api = endpoint();
  assert.deepEqual(api.get(), { ok: true, version: 2, entries: [] });
  assert.deepEqual(api.rows[0], ['Table', 'Entry', 'Importance', 'Success']);
  assert.equal(api.post([{ table: 'Words', entry: '=one', success: 8 }]).ok, true);
  assert.deepEqual(api.rows[1], ['Words', '=one', '', 8]);
  assert.deepEqual(api.get().entries, [{ table: 'Words', entry: '=one', importance: null, success: 8 }]);
});

test('resetting both fields and replacing with an empty snapshot removes rows', () => {
  const api = endpoint();
  api.post([{ table: 'Words', entry: 'one', importance: 3, success: 8 },
    { table: 'Words', entry: 'two', importance: 9 }]);
  api.post([{ table: 'Words', entry: 'one', importance: null, success: 8 },
    { table: 'Words', entry: 'two', importance: null, success: null }]);
  assert.deepEqual(api.get().entries, [{ table: 'Words', entry: 'one', importance: null, success: 8 }]);
  api.post([]);
  assert.deepEqual(api.get().entries, []);
  assert.equal(api.rows.slice(1).every(row => row.every(value => value === '')), true);
});

test('invalid uploads preserve the previous snapshot', () => {
  const api = endpoint();
  api.post([{ table: 'Words', entry: 'one', success: 8 }]);
  assert.equal(api.post([{ table: 'Words', entry: 'one', success: 11 }]).ok, false);
  assert.equal(api.get().entries[0].success, 8);
});
