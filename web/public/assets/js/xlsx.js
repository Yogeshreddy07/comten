// Dependency-free .xlsx writer. Builds a minimal OOXML spreadsheet (one
// worksheet per sheet spec, inline strings, numbers as numbers) inside an
// uncompressed ("stored") ZIP - no vendored library needed, works fully
// offline like the rest of this site.
//
// Usage: window.xlsxExport.download('report.xlsx', [
//   { name: 'Sheet name', headers: ['A', 'B'], rows: [[1, 'x'], [2, 'y']] },
// ]);
(function () {
  'use strict';

  // --- ZIP (stored entries only) ---

  const CRC_TABLE = (() => {
    const table = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
      table[n] = c >>> 0;
    }
    return table;
  })();

  function crc32(bytes) {
    let crc = 0xffffffff;
    for (let i = 0; i < bytes.length; i++) {
      crc = CRC_TABLE[(crc ^ bytes[i]) & 0xff] ^ (crc >>> 8);
    }
    return (crc ^ 0xffffffff) >>> 0;
  }

  function u16(value) { return [value & 0xff, (value >>> 8) & 0xff]; }
  function u32(value) { return [value & 0xff, (value >>> 8) & 0xff, (value >>> 16) & 0xff, (value >>> 24) & 0xff]; }

  /** files: [{ name, content (string) }] -> Uint8Array of a stored ZIP. */
  function buildZip(files) {
    const encoder = new TextEncoder();
    const chunks = [];
    const central = [];
    let offset = 0;

    for (const file of files) {
      const nameBytes = encoder.encode(file.name);
      const dataBytes = encoder.encode(file.content);
      const crc = crc32(dataBytes);

      const local = [].concat(
        u32(0x04034b50), u16(20), u16(0x0800), u16(0), u16(0), u16(0),
        u32(crc), u32(dataBytes.length), u32(dataBytes.length),
        u16(nameBytes.length), u16(0));
      chunks.push(new Uint8Array(local), nameBytes, dataBytes);

      central.push({ nameBytes: nameBytes, crc: crc, size: dataBytes.length, offset: offset });
      offset += local.length + nameBytes.length + dataBytes.length;
    }

    const centralStart = offset;
    for (const entry of central) {
      const header = [].concat(
        u32(0x02014b50), u16(20), u16(20), u16(0x0800), u16(0), u16(0), u16(0),
        u32(entry.crc), u32(entry.size), u32(entry.size),
        u16(entry.nameBytes.length), u16(0), u16(0), u16(0), u16(0),
        u32(0), u32(entry.offset));
      chunks.push(new Uint8Array(header), entry.nameBytes);
      offset += header.length + entry.nameBytes.length;
    }

    const eocd = [].concat(
      u32(0x06054b50), u16(0), u16(0), u16(central.length), u16(central.length),
      u32(offset - centralStart), u32(centralStart), u16(0));
    chunks.push(new Uint8Array(eocd));

    let total = 0;
    for (const chunk of chunks) total += chunk.length;
    const out = new Uint8Array(total);
    let pos = 0;
    for (const chunk of chunks) { out.set(chunk, pos); pos += chunk.length; }
    return out;
  }

  // --- SpreadsheetML ---

  function xmlEscape(value) {
    return String(value)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&apos;');
  }

  function colRef(index) {
    let ref = '';
    let n = index;
    do {
      ref = String.fromCharCode(65 + (n % 26)) + ref;
      n = Math.floor(n / 26) - 1;
    } while (n >= 0);
    return ref;
  }

  function cellXml(value, rowNum, colIndex) {
    const ref = colRef(colIndex) + rowNum;
    if (value == null || value === '') return '<c r="' + ref + '"/>';
    if (typeof value === 'number' && isFinite(value)) {
      return '<c r="' + ref + '"><v>' + value + '</v></c>';
    }
    return '<c r="' + ref + '" t="inlineStr"><is><t xml:space="preserve">'
      + xmlEscape(value) + '</t></is></c>';
  }

  function sheetXml(sheet) {
    const allRows = [sheet.headers || []].concat(sheet.rows || []);
    const rowsXml = allRows.map((row, rowIndex) => {
      const rowNum = rowIndex + 1;
      return '<row r="' + rowNum + '">'
        + row.map((cell, colIndex) => cellXml(cell, rowNum, colIndex)).join('')
        + '</row>';
    }).join('');
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      + '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      + '<sheetData>' + rowsXml + '</sheetData></worksheet>';
  }

  /** Excel restricts sheet names to 31 chars with no []:*?/\ characters. */
  function sheetName(raw, index) {
    const cleaned = String(raw || ('Sheet' + (index + 1))).replace(/[\[\]:*?\/\\]/g, ' ').trim();
    return (cleaned || 'Sheet' + (index + 1)).slice(0, 31);
  }

  function buildWorkbook(sheets) {
    const files = [];

    const contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      + '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      + '<Default Extension="xml" ContentType="application/xml"/>'
      + '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      + sheets.map((s, i) => '<Override PartName="/xl/worksheets/sheet' + (i + 1)
        + '.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>').join('')
      + '</Types>';
    files.push({ name: '[Content_Types].xml', content: contentTypes });

    files.push({
      name: '_rels/.rels',
      content: '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        + '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        + '</Relationships>',
    });

    files.push({
      name: 'xl/workbook.xml',
      content: '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        + '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
        + ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
        + sheets.map((s, i) => '<sheet name="' + xmlEscape(sheetName(s.name, i))
          + '" sheetId="' + (i + 1) + '" r:id="rId' + (i + 1) + '"/>').join('')
        + '</sheets></workbook>',
    });

    files.push({
      name: 'xl/_rels/workbook.xml.rels',
      content: '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        + sheets.map((s, i) => '<Relationship Id="rId' + (i + 1)
          + '" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"'
          + ' Target="worksheets/sheet' + (i + 1) + '.xml"/>').join('')
        + '</Relationships>',
    });

    sheets.forEach((sheet, i) => {
      files.push({ name: 'xl/worksheets/sheet' + (i + 1) + '.xml', content: sheetXml(sheet) });
    });

    return buildZip(files);
  }

  function download(filename, sheets) {
    if (!sheets || !sheets.length) throw new Error('Nothing to export yet.');
    const bytes = buildWorkbook(sheets);
    const blob = new Blob([bytes], {
      type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = filename.endsWith('.xlsx') ? filename : filename + '.xlsx';
    document.body.appendChild(anchor);
    anchor.click();
    document.body.removeChild(anchor);
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  window.xlsxExport = { download: download };
})();
