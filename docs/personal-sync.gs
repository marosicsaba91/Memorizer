// Paste into Extensions > Apps Script and keep your spreadsheet ID.
const SPREADSHEET_ID = 'PASTE_YOUR_SPREADSHEET_ID_HERE';
const TAB_NAME = 'Results';
const HEADERS = ['Table', 'Entry', 'Appeared Count', 'Failed Count', 'Almost Count', 'Success Count', 'Importance'];

function jsonResponse(value) {
  return ContentService.createTextOutput(JSON.stringify(value)).setMimeType(ContentService.MimeType.JSON);
}

function count(value) {
  if (value === '' || value == null) return 0;
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number < 0) throw new Error('Counts must be nonnegative integers.');
  return number;
}

function importance(value) {
  if (value === '' || value == null) return null;
  const number = Number(value);
  if (!Number.isInteger(number) || number < 0 || number > 10) throw new Error('Importance must be an integer from 0 to 10.');
  return number;
}

function writeEntries(sheet, entries) {
  const oldLastRow = sheet.getLastRow();
  const literal = text => "'" + text;
  const rows = [HEADERS, ...entries.map(item => [
    literal(item.table), literal(item.entry), item.appearedCount,
    item.failedCount, item.almostCount, item.successCount, item.importance ?? '',
  ])];
  if (sheet.getMaxRows() < rows.length) sheet.insertRowsAfter(sheet.getMaxRows(), rows.length - sheet.getMaxRows());
  sheet.getRange(1, 1, rows.length, HEADERS.length).setValues(rows);
  if (oldLastRow > rows.length) sheet.getRange(rows.length + 1, 1, oldLastRow - rows.length, HEADERS.length).clearContent();
  sheet.setFrozenRows(1);
  SpreadsheetApp.flush();
}

function ratingsSheet() {
  const spreadsheet = SpreadsheetApp.openById(SPREADSHEET_ID);
  const sheet = spreadsheet.getSheetByName(TAB_NAME) || spreadsheet.insertSheet(TAB_NAME);
  if (sheet.getMaxColumns() < HEADERS.length) sheet.insertColumnsAfter(sheet.getMaxColumns(), HEADERS.length - sheet.getMaxColumns());
  if (sheet.getLastRow() === 0) {
    writeEntries(sheet, []);
    return sheet;
  }
  const actual = sheet.getRange(1, 1, 1, HEADERS.length).getDisplayValues()[0];
  if (HEADERS.every((header, index) => actual[index] === header)) return sheet;
  const legacy = ['Table', 'Entry', 'Importance', 'Success'];
  if (!legacy.every((header, index) => actual[index] === header)) {
    throw new Error('The Ratings tab has unexpected headers.');
  }
  // The old Success rating and shown count cannot reconstruct graded outcomes.
  // Retain Importance overrides and start the outcome counters at zero.
  const entries = sheet.getLastRow() < 2 ? [] : sheet.getRange(2, 1, sheet.getLastRow() - 1, 4).getDisplayValues()
    .filter(row => row[0] !== '' && row[1] !== '' && row[2] !== '')
    .map(row => ({table: row[0], entry: row[1], importance: importance(row[2]),
      appearedCount: 0, failedCount: 0, almostCount: 0, successCount: 0}));
  writeEntries(sheet, entries);
  return sheet;
}

function readEntries(sheet) {
  if (sheet.getLastRow() < 2) return [];
  return sheet.getRange(2, 1, sheet.getLastRow() - 1, HEADERS.length).getDisplayValues()
    .filter(row => row[0] !== '' && row[1] !== '')
    .map(row => {
      const failedCount = count(row[3]);
      const almostCount = count(row[4]);
      const successCount = count(row[5]);
      return {table: row[0], entry: row[1], importance: importance(row[6]),
        appearedCount: failedCount + almostCount + successCount, failedCount, almostCount, successCount};
    }).filter(item => item.importance != null || item.appearedCount > 0);
}

function doGet() {
  const lock = LockService.getScriptLock();
  let locked = false;
  try {
    lock.waitLock(30000);
    locked = true;
    return jsonResponse({ok: true, version: 3, entries: readEntries(ratingsSheet())});
  } catch (error) {
    return jsonResponse({ok: false, error: String(error.message || error)});
  } finally {
    if (locked) lock.releaseLock();
  }
}

function doPost(event) {
  const lock = LockService.getScriptLock();
  let locked = false;
  try {
    const body = JSON.parse(event.postData.contents);
    if (body.version !== 3 || body.mode !== 'replace' || !Array.isArray(body.entries)) {
      throw new Error('Update the app and script to version 3 for question result counters.');
    }
    const incoming = body.entries.map(item => {
      if (typeof item.table !== 'string' || !item.table.trim() || typeof item.entry !== 'string' || !item.entry.trim()) {
        throw new Error('Each result needs a table and entry.');
      }
      const failedCount = count(item.failedCount);
      const almostCount = count(item.almostCount);
      const successCount = count(item.successCount);
      const appearedCount = failedCount + almostCount + successCount;
      if (count(item.appearedCount) !== appearedCount) throw new Error('Appeared Count must equal the sum of outcome counts.');
      return {table: item.table, entry: item.entry, importance: importance(item.importance),
        appearedCount, failedCount, almostCount, successCount};
    });
    const unique = new Map();
    incoming.forEach(item => {
      if (item.importance != null || item.appearedCount > 0) unique.set(JSON.stringify([item.table, item.entry]), item);
    });
    lock.waitLock(30000);
    locked = true;
    writeEntries(ratingsSheet(), Array.from(unique.values()));
    return jsonResponse({ok: true, version: 3, total: unique.size});
  } catch (error) {
    return jsonResponse({ok: false, error: String(error.message || error)});
  } finally {
    if (locked) lock.releaseLock();
  }
}
