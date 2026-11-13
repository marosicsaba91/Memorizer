// Paste this into Extensions > Apps Script in your personal spreadsheet.
const SPREADSHEET_ID = 'PASTE_YOUR_SPREADSHEET_ID_HERE';
const TAB_NAME = 'Ratings';
const HEADERS = ['Table', 'Entry', 'Importance', 'Success'];

function jsonResponse(value) {
  return ContentService.createTextOutput(JSON.stringify(value))
    .setMimeType(ContentService.MimeType.JSON);
}

function ratingsSheet() {
  const spreadsheet = SpreadsheetApp.openById(SPREADSHEET_ID);
  const sheet = spreadsheet.getSheetByName(TAB_NAME) ||
    spreadsheet.insertSheet(TAB_NAME);
  if (sheet.getMaxColumns() < HEADERS.length) {
    sheet.insertColumnsAfter(sheet.getMaxColumns(),
      HEADERS.length - sheet.getMaxColumns());
  }
  if (sheet.getLastRow() === 0) {
    sheet.getRange(1, 1, 1, HEADERS.length).setValues([HEADERS]);
    sheet.setFrozenRows(1);
    SpreadsheetApp.flush();
  } else {
    const actual = sheet.getRange(1, 1, 1, HEADERS.length)
      .getDisplayValues()[0];
    if (!HEADERS.every((header, index) => actual[index] === header)) {
      throw new Error('The existing Ratings tab has unexpected headers. ' +
        'Rename that tab so a new Ratings tab can be created automatically.');
    }
  }
  return sheet;
}

function rating(value) {
  if (value === '' || value === undefined || value === null) return null;
  const number = Number(value);
  if (!Number.isInteger(number) || number < 1 || number > 10) {
    throw new Error('Importance and Success must be integers from 1 to 10.');
  }
  return number;
}

function readEntries(sheet) {
  if (sheet.getLastRow() < 2) return [];
  return sheet.getRange(2, 1, sheet.getLastRow() - 1, 4)
    .getDisplayValues()
    .filter(row => row[0] !== '' && row[1] !== '')
    .map(row => ({
      table: row[0], entry: row[1],
      importance: rating(row[2]), success: rating(row[3]),
    }))
    .filter(item => item.importance != null || item.success != null);
}

function doGet() {
  const lock = LockService.getScriptLock();
  let locked = false;
  try {
    lock.waitLock(30000);
    locked = true;
    return jsonResponse({ok: true, version: 2,
      entries: readEntries(ratingsSheet())});
  } catch (error) {
    return jsonResponse({ok: false, error: String(error.message || error)});
  } finally {
    if (locked) lock.releaseLock();
  }
}

// Replaces the personal-results snapshot. Missing entries are removed.
function doPost(event) {
  const lock = LockService.getScriptLock();
  let locked = false;
  try {
    const body = JSON.parse(event.postData.contents);
    if (body.version !== 2 || body.mode !== 'replace' || !Array.isArray(body.entries)) {
      throw new Error('Update the app and script: expected {version: 2, mode: "replace", entries: [...]}');
    }
    const incoming = body.entries.map(item => {
      if (typeof item.table !== 'string' || !item.table.trim() ||
          typeof item.entry !== 'string' || !item.entry.trim()) {
        throw new Error('Each entry needs nonempty table and entry strings.');
      }
      return {table: item.table, entry: item.entry,
        importance: rating(item.importance), success: rating(item.success)};
    });
    lock.waitLock(30000);
    locked = true;
    const sheet = ratingsSheet();
    const key = item => JSON.stringify([item.table, item.entry]);
    const merged = new Map();
    incoming.forEach(item => {
      if (item.importance != null || item.success != null) merged.set(key(item), item);
    });
    // The leading apostrophe keeps text literal, including entries starting '='.
    const literal = text => "'" + text;
    const rows = [HEADERS,
      ...Array.from(merged.values(), item => [
        literal(item.table), literal(item.entry), item.importance ?? '', item.success ?? '',
      ])];
    if (sheet.getMaxRows() < rows.length) {
      sheet.insertRowsAfter(sheet.getMaxRows(), rows.length - sheet.getMaxRows());
    }
    sheet.getRange(1, 1, rows.length, 4).setValues(rows);
    const oldLastRow = sheet.getLastRow();
    if (oldLastRow > rows.length) {
      sheet.getRange(rows.length + 1, 1, oldLastRow - rows.length, 4)
        .clearContent();
    }
    SpreadsheetApp.flush();
    return jsonResponse({ok: true, version: 2, updated: incoming.length, total: merged.size});
  } catch (error) {
    return jsonResponse({ok: false, error: String(error.message || error)});
  } finally {
    if (locked) lock.releaseLock();
  }
}
