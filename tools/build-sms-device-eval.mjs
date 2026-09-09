import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, relative, resolve } from 'node:path';

function sha256(value) {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

function compareStrings(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function fail(source, message) {
  throw new Error(`${source}: ${message}`);
}

function validateRecord(record, source) {
  if (!record || typeof record !== 'object' || Array.isArray(record)) {
    fail(source, 'required record object is missing');
  }

  const validMessageId = (typeof record.msg_id === 'number' && Number.isFinite(record.msg_id))
    || (typeof record.msg_id === 'string' && record.msg_id.trim() !== '');
  if (!validMessageId) fail(source, 'required msg_id is missing or invalid');
  if (typeof record.text !== 'string' || record.text.trim() === '') {
    fail(source, 'required text is missing or invalid');
  }
  if (typeof record.domain !== 'string' || record.domain.trim() === '') {
    fail(source, 'required domain is missing or invalid');
  }
  if (!Array.isArray(record.entities)) fail(source, 'required entities array is missing or invalid');

  const entities = record.entities.map((entity, index) => {
    const entitySource = `${source} entity ${index}`;
    if (!entity || typeof entity !== 'object' || Array.isArray(entity)) {
      fail(entitySource, 'entity object is invalid');
    }
    if (typeof entity.label !== 'string' || entity.label.trim() === '') {
      fail(entitySource, 'entity label is missing or invalid');
    }
    if (!Number.isInteger(entity.start) || !Number.isInteger(entity.end)
      || entity.start < 0 || entity.end <= entity.start || entity.end > record.text.length) {
      fail(entitySource, 'entity span is invalid');
    }
    if (typeof entity.text !== 'string' || entity.text === '') {
      fail(entitySource, 'entity text is missing or invalid');
    }
    if (record.text.slice(entity.start, entity.end) !== entity.text) {
      fail(entitySource, 'entity text does not match entity span');
    }
    return {
      label: entity.label,
      start: entity.start,
      end: entity.end,
      text: entity.text,
    };
  });

  return {
    msg_id: record.msg_id,
    text: record.text,
    domain: record.domain,
    entities,
  };
}

function allJSONLFiles(root) {
  const files = [];
  function visit(directory) {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) visit(path);
      else if (entry.isFile() && entry.name.endsWith('_all.jsonl')) files.push(path);
    }
  }
  visit(root);
  return files.sort((left, right) => compareStrings(relative(root, left), relative(root, right)));
}

function compareRecords(left, right) {
  return compareStrings(left.hash, right.hash)
    || compareStrings(left.row.text, right.row.text)
    || compareStrings(String(left.row.msg_id), String(right.row.msg_id))
    || compareStrings(left.source, right.source)
    || left.line - right.line;
}

export function buildEvaluationSet(root, countPerDomain) {
  if (typeof root !== 'string' || root.trim() === '' || !existsSync(root) || !statSync(root).isDirectory()) {
    throw new Error(`dataset root is missing or invalid: ${root}`);
  }
  if (!Number.isInteger(countPerDomain) || countPerDomain <= 0) {
    throw new Error(`countPerDomain must be a positive integer: ${countPerDomain}`);
  }

  const records = [];
  for (const file of allJSONLFiles(root)) {
    const lines = readFileSync(file, 'utf8').split(/\r?\n/);
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index].trim();
      if (!line) continue;
      const source = `${file}:${index + 1}`;
      let parsed;
      try {
        parsed = JSON.parse(line);
      } catch (error) {
        fail(source, `malformed JSON (${error.message})`);
      }
      const row = validateRecord(parsed, source);
      records.push({ row, hash: sha256(row.text), source: relative(root, file), line: index + 1 });
    }
  }

  const byDomain = new Map();
  for (const record of records) {
    const domainRows = byDomain.get(record.row.domain) ?? [];
    domainRows.push(record);
    byDomain.set(record.row.domain, domainRows);
  }

  return [...byDomain.keys()].sort().flatMap((domain) => {
    const seenText = new Set();
    const candidates = byDomain.get(domain).sort(compareRecords)
      .filter(({ row }) => {
        if (seenText.has(row.text)) return false;
        seenText.add(row.text);
        return true;
      });
    if (candidates.length < countPerDomain) {
      throw new Error(`domain ${domain} has only ${candidates.length} unique texts; requires at least ${countPerDomain}`);
    }
    return candidates.slice(0, countPerDomain).map(({ row }) => row);
  });
}

function main() {
  const root = process.argv[2] ?? '/Users/rain/project/ai_sms/dataset/domains';
  const count = Number(process.argv[3] ?? 30);
  const output = process.argv[4] ?? resolve(dirname(fileURLToPath(import.meta.url)), '../AppleOnDeviceModelDemoTests/Resources/sms_device_eval_30.jsonl');
  const rows = buildEvaluationSet(root, count);
  mkdirSync(dirname(output), { recursive: true });
  writeFileSync(output, `${rows.map((row) => JSON.stringify(row)).join('\n')}\n`);
  console.log(`wrote ${rows.length} rows across ${new Set(rows.map((row) => row.domain)).size} domains to ${output}`);
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url))) main();
