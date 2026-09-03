import assert from 'node:assert/strict';
import test from 'node:test';

import {
  parseJSONL,
  projectGoldEntities,
  renderMarkdownReport,
  scoreEvaluation,
} from '../score-sms-device-eval.mjs';

function row(msg_id, domain, entities = [], text = `${domain}-${msg_id}`) {
  return { msg_id, text, domain, entities };
}

function prediction(msg_id, domain, entities = [], status = 'ok') {
  return { msg_id, status, domain, entities };
}

function entity(label, start, end, text) {
  return { label, start, end, text };
}

test('computes exact domain accuracy and one-vs-rest macro/micro F1', () => {
  const fixture = [row(1, 'a'), row(2, 'a'), row(3, 'b')];
  const predictions = [prediction(1, 'a'), prediction(2, 'b'), prediction(3, 'b')];

  const report = scoreEvaluation(fixture, predictions);

  assert.equal(report.domain.total, 3);
  assert.equal(report.domain.correct, 2);
  assert.equal(report.domain.accuracy, 2 / 3);
  assert.deepEqual(report.domain.perDomain.a, { tp: 1, fp: 0, fn: 1, precision: 1, recall: 0.5, f1: 2 / 3 });
  assert.deepEqual(report.domain.perDomain.b, { tp: 1, fp: 1, fn: 0, precision: 0.5, recall: 1, f1: 2 / 3 });
  assert.equal(report.domain.macro.f1, 2 / 3);
  assert.equal(report.domain.micro.f1, 2 / 3);
});

test('reports deterministic top confusion pairs for misclassifications', () => {
  const fixture = [row(1, 'a'), row(2, 'a'), row(3, 'b')];
  const predictions = [prediction(1, 'b'), prediction(2, 'b'), prediction(3, 'a')];

  const report = scoreEvaluation(fixture, predictions);

  assert.deepEqual(report.domain.topConfusions, [
    { gold: 'a', predicted: 'b', count: 2 },
    { gold: 'b', predicted: 'a', count: 1 },
  ]);
});

test('keeps missing and terminal error statuses in denominator as domain FN', () => {
  const fixture = [row(1, 'a'), row(2, 'a'), row(3, 'b'), row(4, 'b'), row(5, 'b')];
  const predictions = [
    prediction(1, 'a'),
    { msg_id: 2, status: 'error', error: 'model failed' },
    { msg_id: 3, status: 'timeout' },
    { msg_id: 4, status: 'unavailable' },
    { msg_id: 5, status: 'cancelled' },
  ];

  const report = scoreEvaluation(fixture, predictions);

  assert.equal(report.coverage.predictedRows, 5);
  assert.equal(report.coverage.terminalRows, 5);
  assert.equal(report.coverage.missingRows, 0);
  assert.deepEqual(report.statusCounts, { ok: 1, error: 1, timeout: 1, unavailable: 1, cancelled: 1 });
  assert.equal(report.domain.perDomain.a.fn, 1);
  assert.equal(report.domain.perDomain.b.fn, 3);
});

test('counts an actually missing prediction row in coverage and domain/entity denominators', () => {
  const fixture = [
    row(1, 'a'),
    row(2, 'b', [entity('org', 0, 2, 'AB')], 'AB'),
  ];
  const report = scoreEvaluation(fixture, [prediction(1, 'a')]);

  assert.equal(report.coverage.predictedRows, 1);
  assert.equal(report.coverage.terminalRows, 1);
  assert.equal(report.coverage.missingRows, 1);
  assert.equal(report.coverage.rate, 0.5);
  assert.equal(report.domain.perDomain.b.fn, 1);
  assert.equal(report.entities.rawGold.perDomain.b.fn, 1);
});

test('scores exact entity tuples independently of domain correctness', () => {
  const fixture = [row(1, 'delivery', [entity('pickup_code', 2, 5, '123')], '码123')];
  const predictions = [prediction(1, 'ignored', [entity('pickup_code', 2, 5, '123')])];

  const report = scoreEvaluation(fixture, predictions);

  assert.deepEqual(report.entities.rawGold.perDomain.delivery, {
    tp: 1, fp: 0, fn: 0, precision: 1, recall: 1, f1: 1,
  });
  assert.equal(report.jointExact.rawGold.correct, 0);
  assert.equal(report.jointExact.productionProjected.correct, 0);
});

test('deduplicates predicted tuples for matching and counts duplicate diagnostics', () => {
  const fixture = [row(1, 'delivery', [entity('pickup_code', 2, 5, '123')], '码123')];
  const tuple = entity('pickup_code', 2, 5, '123');
  const report = scoreEvaluation(fixture, [prediction(1, 'delivery', [tuple, tuple])]);

  assert.equal(report.entities.rawGold.perDomain.delivery.tp, 1);
  assert.equal(report.entities.rawGold.perDomain.delivery.fp, 0);
  assert.equal(report.entities.duplicatePredictions, 1);
});

test('handles empty gold and prediction entity sets without fake support', () => {
  const fixture = [
    row(1, 'empty'),
    row(2, 'empty', [entity('org', 0, 2, 'AB')], 'AB'),
    row(3, 'empty'),
  ];
  const predictions = [
    prediction(1, 'empty'),
    prediction(2, 'empty'),
    prediction(3, 'empty', [entity('org', 0, 2, 'AB')]),
  ];

  const report = scoreEvaluation(fixture, predictions);

  assert.equal(report.entities.rawGold.perDomain.empty.tp, 0);
  assert.equal(report.entities.rawGold.perDomain.empty.fp, 1);
  assert.equal(report.entities.rawGold.perDomain.empty.fn, 1);
  assert.equal(report.entities.rawGold.perDomain.empty.f1, 0);
});

test('marks a zero-gold-entity domain as null and excludes it from entity macro', () => {
  const fixture = [row(1, 'no_entities'), row(2, 'with_entities', [entity('org', 0, 2, 'AB')], 'AB')];
  const report = scoreEvaluation(fixture, [prediction(1, 'no_entities'), prediction(2, 'with_entities')]);

  assert.equal(report.entities.rawGold.perDomain.no_entities.f1, null);
  assert.equal(report.entities.rawGold.macro.supportedDomains, 1);
  assert.equal(report.entities.rawGold.macro.f1, 0);
});

test('excludes zero-gold entity domains with prediction FP from all entity macro aggregates', () => {
  const fixture = [
    row(1, 'empty', [], 'AB'),
    row(2, 'with_entities', [entity('org', 0, 2, 'AB')], 'AB'),
  ];
  const report = scoreEvaluation(fixture, [
    prediction(1, 'empty', [entity('org', 0, 2, 'AB')]),
    prediction(2, 'with_entities', [entity('org', 0, 2, 'AB')]),
  ]);

  assert.equal(report.entities.rawGold.perDomain.empty.f1, null);
  assert.equal(report.entities.rawGold.macro.precision, 1);
  assert.equal(report.entities.rawGold.macro.recall, 1);
  assert.equal(report.entities.rawGold.macro.f1, 1);
  assert.deepEqual(report.entities.rawGold.micro, {
    tp: 1, fp: 1, fn: 0, precision: 0.5, recall: 1, f1: 2 / 3,
  });
});

test('projects gold entities with unsupported-label filtering and deterministic longest non-overlap', () => {
  const fixtureRow = row(1, 'delivery', [
    entity('org', 0, 4, 'ABCD'),
    entity('pickup_code', 0, 2, 'AB'),
    entity('not_allowed', 5, 7, 'XY'),
  ], 'ABCD XY');
  const projection = projectGoldEntities(fixtureRow);

  assert.deepEqual(projection.entities, [entity('org', 0, 4, 'ABCD')]);
  assert.equal(projection.exclusions.unsupportedLabel, 1);
  assert.equal(projection.exclusions.overlap, 1);
  assert.equal(projection.overlapSpans, 2);
});

test('uses the latest terminal result for duplicate msg_id rows', () => {
  const fixture = [row(1, 'a')];
  const predictions = [
    prediction(1, 'b'),
    { msg_id: 1, status: 'error', error: 'retrying' },
    prediction(1, 'a'),
  ];
  const report = scoreEvaluation(fixture, predictions);

  assert.equal(report.domain.correct, 1);
  assert.equal(report.statusCounts.ok, 1);
  assert.equal(report.coverage.duplicateResultRows, 2);
});

test('parses JSONL while preserving terminal error rows and rejecting malformed lines', () => {
  const rows = parseJSONL('{"msg_id":1,"status":"error"}\n{"msg_id":2,"status":"ok","domain":"a","entities":[]}\n');
  assert.equal(rows.length, 2);
  assert.equal(rows[0].status, 'error');
  assert.throws(() => parseJSONL('{bad json}\n'), /line 1|malformed/i);
});

test('renders complete aggregate domain/entity PRF and both joint exact metrics in Markdown', () => {
  const report = scoreEvaluation(
    [row(1, 'delivery', [entity('pickup_code', 0, 3, '123')], '123')],
    [prediction(1, 'delivery', [entity('pickup_code', 0, 3, '123')])],
  );
  const markdown = renderMarkdownReport(report);

  assert.match(markdown, /Domain macro precision:/);
  assert.match(markdown, /Domain macro recall:/);
  assert.match(markdown, /Domain micro precision:/);
  assert.match(markdown, /Domain micro recall:/);
  assert.match(markdown, /Raw-gold entity macro precision:/);
  assert.match(markdown, /Raw-gold entity macro recall:/);
  assert.match(markdown, /Raw-gold entity macro F1:/);
  assert.match(markdown, /Raw-gold entity micro precision:/);
  assert.match(markdown, /Raw-gold entity micro recall:/);
  assert.match(markdown, /Production-projected entity macro F1:/);
  assert.match(markdown, /Production-projected entity micro precision:/);
  assert.match(markdown, /Joint exact \(raw-gold\):/);
  assert.match(markdown, /Joint exact \(production-projected\):/);
});
