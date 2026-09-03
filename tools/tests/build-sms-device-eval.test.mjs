import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { buildEvaluationSet } from '../build-sms-device-eval.mjs';

function makeRecord({ msg_id = 1, text = '短信', domain = 'delivery', entities = [] } = {}) {
  return { msg_id, text, domain, entities };
}

function writeJSONL(root, relativePath, records) {
  const path = join(root, relativePath);
  mkdirSync(join(path, '..'), { recursive: true });
  writeFileSync(path, records.map((record) => JSON.stringify(record)).join('\n') + '\n');
}

function withTempRoot(callback) {
  const root = mkdtempSync(join(tmpdir(), 'sms-device-eval-'));
  try {
    return callback(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test('reads nested _all files and ignores real and ai_generated files', () => {
  withTempRoot((root) => {
    writeJSONL(root, 'delivery/delivery_all.jsonl', [makeRecord({ msg_id: 1, text: '正式样本', domain: 'delivery' })]);
    writeJSONL(root, 'delivery/delivery_real.jsonl', [makeRecord({ msg_id: 2, text: '不应读取', domain: 'delivery' })]);
    writeJSONL(root, 'delivery/delivery_ai_generated.jsonl', [makeRecord({ msg_id: 3, text: '也不应读取', domain: 'delivery' })]);

    const rows = buildEvaluationSet(root, 1);

    assert.deepEqual(rows.map(({ msg_id, text, domain }) => ({ msg_id, text, domain })), [
      { msg_id: 1, text: '正式样本', domain: 'delivery' },
    ]);
  });
});

test('deduplicates text within each domain and orders by SHA-256 deterministically', () => {
  withTempRoot((root) => {
    writeJSONL(root, 'b/domain_b_all.jsonl', [
      makeRecord({ msg_id: 4, text: '乙', domain: 'domain_b' }),
      makeRecord({ msg_id: 3, text: '甲', domain: 'domain_b' }),
      makeRecord({ msg_id: 2, text: '甲', domain: 'domain_b', entities: [{ label: 'org', start: 0, end: 1, text: '甲' }] }),
    ]);
    writeJSONL(root, 'a/domain_a_all.jsonl', [
      makeRecord({ msg_id: 6, text: '同文', domain: 'domain_a' }),
      makeRecord({ msg_id: 7, text: '同文二', domain: 'domain_a' }),
    ]);

    const first = buildEvaluationSet(root, 2);
    const second = buildEvaluationSet(root, 2);
    const expected = ['甲', '乙'].sort((left, right) =>
      createHash('sha256').update(left, 'utf8').digest('hex').localeCompare(
        createHash('sha256').update(right, 'utf8').digest('hex'),
      ),
    );

    assert.deepEqual(first, second);
    assert.deepEqual(first.filter((row) => row.domain === 'domain_b').map((row) => row.text), expected);
    assert.equal(first.filter((row) => row.domain === 'domain_b' && row.text === '甲').length, 1);
    assert.deepEqual(Object.keys(first[0]).sort(), ['domain', 'entities', 'msg_id', 'text']);
    const rowWithEntity = first.find((row) => row.entities.length > 0);
    assert.deepEqual(Object.keys(rowWithEntity.entities[0]).sort(), ['end', 'label', 'start', 'text']);
  });
});

test('caps every domain at countPerDomain', () => {
  withTempRoot((root) => {
    writeJSONL(root, 'one/one_all.jsonl', Array.from({ length: 4 }, (_, i) => makeRecord({ msg_id: i + 1, text: `one-${i}`, domain: 'one' })));
    writeJSONL(root, 'two/two_all.jsonl', Array.from({ length: 2 }, (_, i) => makeRecord({ msg_id: i + 10, text: `two-${i}`, domain: 'two' })));

    const rows = buildEvaluationSet(root, 2);

    assert.deepEqual(Object.fromEntries([...new Set(rows.map((row) => row.domain))].map((domain) => [
      domain,
      rows.filter((row) => row.domain === domain).length,
    ])), { one: 2, two: 2 });
  });
});

test('fails when a domain has fewer unique texts than countPerDomain', () => {
  withTempRoot((root) => {
    writeJSONL(root, 'sparse/sparse_all.jsonl', [makeRecord({ msg_id: 1, text: '唯一文本', domain: 'sparse' })]);

    assert.throws(() => buildEvaluationSet(root, 2), /fewer|at least|countPerDomain/i);
  });
});

test('produces identical bytes when _all file and line order is rearranged', () => {
  withTempRoot((root) => {
    const baselineRoot = join(root, 'baseline');
    const reorderedRoot = join(root, 'reordered');
    const aRows = [
      makeRecord({ msg_id: 10, text: '文本 A', domain: 'stable' }),
      makeRecord({ msg_id: 3, text: '重复文本', domain: 'stable' }),
    ];
    const bRows = [
      makeRecord({ msg_id: 20, text: '文本 B', domain: 'stable' }),
      makeRecord({ msg_id: 2, text: '重复文本', domain: 'stable' }),
    ];
    writeJSONL(baselineRoot, 'a/stable_all.jsonl', aRows);
    writeJSONL(baselineRoot, 'b/stable_all.jsonl', bRows);
    writeJSONL(reorderedRoot, 'a/stable_all.jsonl', [...aRows].reverse());
    writeJSONL(reorderedRoot, 'b/stable_all.jsonl', [...bRows].reverse());

    assert.equal(JSON.stringify(buildEvaluationSet(baselineRoot, 3)), JSON.stringify(buildEvaluationSet(reorderedRoot, 3)));
  });
});

test('accepts entity spans expressed as UTF-16 code-unit offsets around emoji', () => {
  withTempRoot((root) => {
    const text = '😀短信';
    const rows = buildEvaluationSet(root, 1);
    assert.deepEqual(rows, []);
    writeJSONL(root, 'emoji/emoji_all.jsonl', [makeRecord({
      msg_id: 1,
      text,
      domain: 'emoji',
      entities: [
        { label: 'emoji', start: 0, end: 2, text: '😀' },
        { label: 'org', start: 2, end: 4, text: '短信' },
      ],
    })]);

    assert.deepEqual(buildEvaluationSet(root, 1)[0].entities, [
      { label: 'emoji', start: 0, end: 2, text: '😀' },
      { label: 'org', start: 2, end: 4, text: '短信' },
    ]);
  });
});

test('rejects malformed required record fields', () => {
  withTempRoot((root) => {
    const malformed = [
      { text: '缺 msg_id', domain: 'delivery', entities: [] },
      { msg_id: 2, text: '', domain: 'delivery', entities: [] },
      { msg_id: 3, text: '缺 domain', entities: [] },
      { msg_id: 4, text: '缺 entities', domain: 'delivery' },
      { msg_id: 5, text: '实体缺字段', domain: 'delivery', entities: [{ label: 'org', start: 0, end: 1 }] },
    ];

    for (const record of malformed) {
      writeJSONL(root, 'delivery/delivery_all.jsonl', [record]);
      assert.throws(() => buildEvaluationSet(root, 1), /invalid|missing|required/i);
    }
  });
});

test('rejects invalid entity spans and mismatched entity text', () => {
  withTempRoot((root) => {
    const invalidRecords = [
      makeRecord({ entities: [{ label: 'org', start: -1, end: 1, text: '短' }] }),
      makeRecord({ entities: [{ label: 'org', start: 0, end: 4, text: '短信' }] }),
      makeRecord({ entities: [{ label: 'org', start: 0, end: 1, text: '错' }] }),
    ];

    for (const record of invalidRecords) {
      writeJSONL(root, 'delivery/delivery_all.jsonl', [record]);
      assert.throws(() => buildEvaluationSet(root, 1), /span|entity|invalid/i);
    }
  });
});

test('generated fixture contains 32 domains, 30 rows per domain, and 960 rows', () => {
  const fixture = new URL('../../AppleOnDeviceModelDemoTests/Resources/sms_device_eval_30.jsonl', import.meta.url);
  const rows = readFileSync(fixture, 'utf8').trim().split('\n').filter(Boolean).map((line) => JSON.parse(line));
  const counts = new Map();
  for (const row of rows) counts.set(row.domain, (counts.get(row.domain) ?? 0) + 1);

  assert.equal(counts.size, 32);
  assert.equal(rows.length, 960);
  assert.deepEqual([...counts.values()], Array(32).fill(30));
});
