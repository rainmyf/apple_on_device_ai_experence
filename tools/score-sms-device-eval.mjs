import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const TERMINAL_STATUSES = new Set(['ok', 'error', 'timeout', 'unavailable', 'cancelled']);

const COMMON_LABELS = new Set([
  'money', 'date', 'time', 'url', 'loc', 'org', 'phone_number', 'person_name',
]);

const DOMAIN_LABELS = {
  electric_vehicle_charging: ['overtime_duration', 'overtime_fee', 'car_moving_action', 'charging_station'],
  traffic_police_attention: ['police_org', 'vehicle_number', 'violation_reason', 'parking_location', 'car_moving_action', 'violation_date', 'violation_time', 'verify_code', 'business_type'],
  train_ticket: ['standby_order_id', 'train_number', 'departure_station', 'arrival_station', 'seat_info', 'delay_info', 'cancel_info'],
  'train_ticket/standby_success': ['departure_date', 'arrival_date', 'departure_time', 'arrival_time'],
  delivery: ['pickup_code', 'pickup_location'],
  plane_ticket: ['order_id', 'flight_number', 'departure_station', 'arrival_station', 'seat_info'],
  'plane_ticket/plane_cancel': ['cancel_info'],
  assessment_arrangement_notice: ['sponsoring_org', 'assessment_type', 'assessment_round', 'position', 'assessment_time', 'reply_time', 'reply_requirement'],
  electricity_balance: ['account_number', 'balance'],
  mobile_account_balance: ['account_number', 'balance'],
  repayment_information: ['loan_account', 'due_amount', 'minimum_payment', 'remaining_amount', 'due_date', 'payment_account'],
};

function key(value) {
  return typeof value === 'string' ? value : JSON.stringify(value);
}

function tupleKey(entity) {
  return `${entity.label}\u0000${entity.start}\u0000${entity.end}`;
}

function compareStrings(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function average(values) {
  return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : null;
}

function prf(tp, fp, fn, zeroGoldIsNull = false) {
  const precision = tp + fp === 0 ? null : tp / (tp + fp);
  const recall = tp + fn === 0 ? null : tp / (tp + fn);
  const f1 = zeroGoldIsNull && tp + fn === 0
    ? null
    : precision === null || recall === null || precision + recall === 0
      ? (precision === 0 || recall === 0 ? 0 : null)
      : (2 * precision * recall) / (precision + recall);
  return { tp, fp, fn, precision, recall, f1 };
}

function validateFixtureRow(row, index) {
  if (!row || typeof row !== 'object' || Array.isArray(row)) throw new Error(`fixture row ${index + 1}: object required`);
  if (row.msg_id === undefined || row.msg_id === null) throw new Error(`fixture row ${index + 1}: msg_id required`);
  if (typeof row.text !== 'string') throw new Error(`fixture row ${index + 1}: text required`);
  if (typeof row.domain !== 'string' || !row.domain) throw new Error(`fixture row ${index + 1}: domain required`);
  if (!Array.isArray(row.entities)) throw new Error(`fixture row ${index + 1}: entities array required`);
  return {
    msg_id: row.msg_id,
    text: row.text,
    domain: row.domain,
    entities: row.entities.map((entity, entityIndex) => {
      if (!entity || typeof entity !== 'object' || typeof entity.label !== 'string'
        || !Number.isInteger(entity.start) || !Number.isInteger(entity.end)) {
        throw new Error(`fixture row ${index + 1} entity ${entityIndex + 1}: invalid tuple`);
      }
      return { label: entity.label, start: entity.start, end: entity.end, text: entity.text ?? '' };
    }),
  };
}

function normalizePrediction(row, index) {
  if (!row || typeof row !== 'object' || Array.isArray(row)) throw new Error(`prediction row ${index + 1}: object required`);
  if (row.msg_id === undefined || row.msg_id === null) throw new Error(`prediction row ${index + 1}: msg_id required`);
  const status = row.status ?? 'ok';
  if (!TERMINAL_STATUSES.has(status)) throw new Error(`prediction row ${index + 1}: invalid terminal status ${status}`);
  const result = row.result && typeof row.result === 'object' ? row.result : row;
  if (status === 'ok' && typeof result.domain !== 'string') {
    throw new Error(`prediction row ${index + 1}: ok prediction domain required`);
  }
  const entities = status === 'ok' && Array.isArray(result.entities) ? result.entities : [];
  return {
    msg_id: row.msg_id,
    status,
    domain: status === 'ok' ? result.domain : null,
    entities: entities.map((entity, entityIndex) => {
      if (!entity || typeof entity !== 'object' || typeof entity.label !== 'string'
        || !Number.isInteger(entity.start) || !Number.isInteger(entity.end)) {
        throw new Error(`prediction row ${index + 1} entity ${entityIndex + 1}: invalid tuple`);
      }
      return { label: entity.label, start: entity.start, end: entity.end, text: entity.text ?? '' };
    }),
  };
}

export function parseJSONL(input, source = 'JSONL') {
  if (typeof input !== 'string') throw new Error(`${source}: expected string input`);
  const rows = [];
  for (const [index, raw] of input.split(/\r?\n/).entries()) {
    if (!raw.trim()) continue;
    try {
      rows.push(JSON.parse(raw));
    } catch (error) {
      throw new Error(`${source} line ${index + 1}: malformed JSON (${error.message})`);
    }
  }
  return rows;
}

export function allowedEntityLabels(domain) {
  const labels = new Set(COMMON_LABELS);
  if (domain !== 'ignored') {
    const parent = domain.split('/', 1)[0];
    for (const label of DOMAIN_LABELS[parent] ?? []) labels.add(label);
    for (const label of DOMAIN_LABELS[domain] ?? []) labels.add(label);
  }
  return labels;
}

function isUTF16Boundary(source, offset) {
  if (!Number.isInteger(offset) || offset < 0 || offset > source.length) return false;
  if (offset === 0 || offset === source.length) return true;
  const previous = source.charCodeAt(offset - 1);
  const next = source.charCodeAt(offset);
  return !(previous >= 0xd800 && previous <= 0xdbff && next >= 0xdc00 && next <= 0xdfff);
}

function validEntityFormat(entity) {
  const text = entity.text;
  if (typeof text !== 'string' || !text) return false;
  switch (entity.label) {
    case 'train_number': return /^[GCDZTSPKLX1-9]\d{1,4}$/.test(text);
    case 'flight_number': return /^[A-Za-z]{2,3}\s?\d{1,4}[A-Za-z]?$/.test(text);
    case 'loan_account':
    case 'payment_account':
    case 'account_number': return /^\d+$/.test(text);
    case 'balance': return /^-?(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d+)?$/.test(text);
    default: return true;
  }
}

function overlaps(left, right) {
  return left.start < right.end && right.start < left.end;
}

export function projectGoldEntities(row) {
  const candidates = [];
  const exclusions = { unsupportedLabel: 0, invalidSpan: 0, invalidText: 0, invalidFormat: 0, overlap: 0 };
  const labels = allowedEntityLabels(row.domain);
  const overlapIndexes = new Set();
  for (let left = 0; left < row.entities.length; left += 1) {
    for (let right = left + 1; right < row.entities.length; right += 1) {
      if (overlaps(row.entities[left], row.entities[right])) {
        overlapIndexes.add(left);
        overlapIndexes.add(right);
      }
    }
  }
  row.entities.forEach((entity, inputOrder) => {
    if (!labels.has(entity.label)) {
      exclusions.unsupportedLabel += 1;
      return;
    }
    if (entity.start < 0 || entity.end <= entity.start || entity.end > row.text.length
      || !isUTF16Boundary(row.text, entity.start) || !isUTF16Boundary(row.text, entity.end)) {
      exclusions.invalidSpan += 1;
      return;
    }
    if (row.text.slice(entity.start, entity.end) !== entity.text || !entity.text) {
      exclusions.invalidText += 1;
      return;
    }
    if (!validEntityFormat(entity)) {
      exclusions.invalidFormat += 1;
      return;
    }
    candidates.push({ entity, inputOrder });
  });
  candidates.sort((left, right) => {
    if (left.entity.start !== right.entity.start) return left.entity.start - right.entity.start;
    const leftLength = left.entity.end - left.entity.start;
    const rightLength = right.entity.end - right.entity.start;
    if (leftLength !== rightLength) return rightLength - leftLength;
    if (left.entity.end !== right.entity.end) return right.entity.end - left.entity.end;
    return compareStrings(left.entity.label, right.entity.label)
      || compareStrings(left.entity.text, right.entity.text)
      || left.inputOrder - right.inputOrder;
  });
  const accepted = [];
  for (const candidate of candidates) {
    if (accepted.some(({ entity }) => overlaps(entity, candidate.entity))) {
      exclusions.overlap += 1;
      continue;
    }
    accepted.push(candidate);
  }
  accepted.sort((left, right) => left.entity.start - right.entity.start || left.entity.end - right.entity.end);
  return {
    entities: accepted.map(({ entity }) => ({ ...entity })),
    exclusions,
    overlapSpans: overlapIndexes.size,
    overlapPairs: [...row.entities].reduce((count, left, leftIndex) => count + row.entities
      .slice(leftIndex + 1).filter((right) => overlaps(left, right)).length, 0),
  };
}

function deduplicateEntities(entities) {
  const unique = new Map();
  let duplicates = 0;
  for (const entity of entities) {
    const tuple = tupleKey(entity);
    if (unique.has(tuple)) duplicates += 1;
    else unique.set(tuple, entity);
  }
  return { unique, duplicates };
}

function metricForDomain(fixture, latest, domain, goldSelector) {
  let tp = 0;
  let fp = 0;
  let fn = 0;
  let goldSupport = 0;
  for (const row of fixture) {
    if (row.domain !== domain) continue;
    const gold = deduplicateEntities(goldSelector(row));
    const pred = latest.get(key(row.msg_id));
    const predicted = deduplicateEntities(pred?.status === 'ok' ? pred.entities : []).unique;
    goldSupport += gold.unique.size;
    for (const tuple of gold.unique.keys()) {
      if (predicted.has(tuple)) tp += 1;
      else fn += 1;
    }
    for (const tuple of predicted.keys()) if (!gold.unique.has(tuple)) fp += 1;
  }
  return { ...prf(tp, fp, fn, true), goldSupport };
}

function aggregateEntityMetrics(fixture, latest, domains, goldSelector) {
  const perDomain = {};
  const all = [];
  const supportedMetrics = [];
  for (const domain of domains) {
    const metric = metricForDomain(fixture, latest, domain, goldSelector);
    const { goldSupport, ...publicMetric } = metric;
    perDomain[domain] = publicMetric;
    if (goldSupport > 0) {
      all.push(publicMetric.f1);
      supportedMetrics.push(publicMetric);
    }
  }
  const totals = Object.values(perDomain).reduce((sum, metric) => ({
    tp: sum.tp + metric.tp,
    fp: sum.fp + metric.fp,
    fn: sum.fn + metric.fn,
  }), { tp: 0, fp: 0, fn: 0 });
  return {
    perDomain,
    macro: {
      precision: average(supportedMetrics.filter((metric) => metric.precision !== null).map((metric) => metric.precision)),
      recall: average(supportedMetrics.filter((metric) => metric.recall !== null).map((metric) => metric.recall)),
      f1: average(all),
      supportedDomains: all.length,
    },
    micro: prf(totals.tp, totals.fp, totals.fn),
  };
}

function sumLabelCounts(rows, entitySelector) {
  const counts = {};
  for (const row of rows) {
    for (const entity of entitySelector(row)) counts[entity.label] = (counts[entity.label] ?? 0) + 1;
  }
  return Object.fromEntries(Object.entries(counts).sort(([left], [right]) => compareStrings(left, right)));
}

export function scoreEvaluation(fixtureRows, predictionRows) {
  const fixture = fixtureRows.map(validateFixtureRow);
  const predictions = predictionRows.map(normalizePrediction);
  const fixtureIds = new Set(fixture.map((row) => key(row.msg_id)));
  const latest = new Map();
  let duplicateResultRows = 0;
  for (const prediction of predictions) {
    if (!fixtureIds.has(key(prediction.msg_id))) continue;
    if (latest.has(key(prediction.msg_id))) duplicateResultRows += 1;
    latest.set(key(prediction.msg_id), prediction);
  }
  const domains = [...new Set(fixture.map((row) => row.domain))].sort(compareStrings);
  const perDomain = {};
  let correct = 0;
  const confusion = new Map();
  for (const domain of domains) {
    let tp = 0; let fp = 0; let fn = 0;
    for (const row of fixture) {
      const pred = latest.get(key(row.msg_id));
      const predictedDomain = pred?.status === 'ok' ? pred.domain : null;
      if (row.domain === domain && predictedDomain === domain) tp += 1;
      else if (row.domain === domain) fn += 1;
      else if (predictedDomain === domain) fp += 1;
    }
    perDomain[domain] = prf(tp, fp, fn);
  }
  for (const row of fixture) {
    const pred = latest.get(key(row.msg_id));
    const predictedDomain = pred?.status === 'ok' ? pred.domain : null;
    if (predictedDomain === row.domain) correct += 1;
    if (predictedDomain && predictedDomain !== row.domain) {
      const confusionKey = `${row.domain}\u0000${predictedDomain}`;
      confusion.set(confusionKey, (confusion.get(confusionKey) ?? 0) + 1);
    }
  }
  const domainTotals = Object.values(perDomain).reduce((sum, metric) => ({
    tp: sum.tp + metric.tp,
    fp: sum.fp + metric.fp,
    fn: sum.fn + metric.fn,
  }), { tp: 0, fp: 0, fn: 0 });
  const statusCounts = Object.fromEntries([...TERMINAL_STATUSES].map((status) => [status, 0]));
  for (const prediction of latest.values()) statusCounts[prediction.status] += 1;
  const projected = new Map();
  let goldUnsupportedEntities = 0;
  let goldOverlapRows = 0;
  let goldOverlapSpans = 0;
  let goldOverlapPairs = 0;
  const projectionExclusions = { unsupportedLabel: 0, invalidSpan: 0, invalidText: 0, invalidFormat: 0, overlap: 0 };
  for (const row of fixture) {
    const result = projectGoldEntities(row);
    projected.set(key(row.msg_id), result.entities);
    goldUnsupportedEntities += result.exclusions.unsupportedLabel;
    goldOverlapSpans += result.overlapSpans;
    goldOverlapPairs += result.overlapPairs;
    if (result.overlapSpans > 0) goldOverlapRows += 1;
    for (const name of Object.keys(projectionExclusions)) projectionExclusions[name] += result.exclusions[name];
  }
  const rawEntityMetrics = aggregateEntityMetrics(fixture, latest, domains, (row) => row.entities);
  const projectedEntityMetrics = aggregateEntityMetrics(fixture, latest, domains, (row) => projected.get(key(row.msg_id)) ?? []);
  let duplicatePredictions = 0;
  for (const prediction of latest.values()) duplicatePredictions += deduplicateEntities(prediction.entities).duplicates;
  const joint = (goldSelector) => {
    let jointCorrect = 0;
    for (const row of fixture) {
      const pred = latest.get(key(row.msg_id));
      if (!pred || pred.status !== 'ok' || pred.domain !== row.domain) continue;
      const gold = deduplicateEntities(goldSelector(row)).unique;
      const entities = deduplicateEntities(pred.entities).unique;
      if (gold.size === entities.size && [...gold.keys()].every((tuple) => entities.has(tuple))) jointCorrect += 1;
    }
    return { correct: jointCorrect, total: fixture.length, accuracy: fixture.length ? jointCorrect / fixture.length : null };
  };
  const representativeFailedMsgIds = [];
  for (const row of fixture) {
    const pred = latest.get(key(row.msg_id));
    const rawGold = deduplicateEntities(row.entities).unique;
    const predEntities = deduplicateEntities(pred?.status === 'ok' ? pred.entities : []).unique;
    const failed = !pred || pred.status !== 'ok' || pred.domain !== row.domain
      || rawGold.size !== predEntities.size || [...rawGold.keys()].some((tuple) => !predEntities.has(tuple));
    if (failed && representativeFailedMsgIds.length < 20) representativeFailedMsgIds.push(row.msg_id);
  }
  const predictionCoverage = fixture.length ? latest.size / fixture.length : null;
  return {
    domain: {
      domains,
      total: fixture.length,
      correct,
      accuracy: fixture.length ? correct / fixture.length : null,
      perDomain,
      macro: {
        precision: average(Object.values(perDomain).map((metric) => metric.precision).filter((value) => value !== null)),
        recall: average(Object.values(perDomain).map((metric) => metric.recall).filter((value) => value !== null)),
        f1: average(Object.values(perDomain).map((metric) => metric.f1).filter((value) => value !== null)),
      },
      micro: prf(domainTotals.tp, domainTotals.fp, domainTotals.fn),
      topConfusions: [...confusion.entries()]
        .map(([encoded, count]) => { const [gold, predicted] = encoded.split('\u0000'); return { gold, predicted, count }; })
        .sort((left, right) => right.count - left.count || compareStrings(left.gold, right.gold) || compareStrings(left.predicted, right.predicted)),
    },
    coverage: {
      fixtureRows: fixture.length,
      predictedRows: latest.size,
      terminalRows: latest.size,
      missingRows: fixture.length - latest.size,
      rate: predictionCoverage,
      predictionCoverage,
      duplicateResultRows,
    },
    statusCounts,
    entities: {
      duplicatePredictions,
      rawGold: rawEntityMetrics,
      productionProjected: projectedEntityMetrics,
    },
    entityF1: {
      rawGoldEntityF1: rawEntityMetrics.micro.f1,
      productionProjectedEntityF1: projectedEntityMetrics.micro.f1,
    },
    raw_gold_entity_f1: rawEntityMetrics.micro.f1,
    production_projected_entity_f1: projectedEntityMetrics.micro.f1,
    jointExact: {
      rawGold: joint((row) => row.entities),
      productionProjected: joint((row) => projected.get(key(row.msg_id)) ?? []),
    },
    gold_unsupported_entities: goldUnsupportedEntities,
    gold_overlap_rows: goldOverlapRows,
    gold_overlap_spans: goldOverlapSpans,
    gold_overlap_pairs: goldOverlapPairs,
    projectionExclusions,
    labelDistributions: {
      goldRaw: sumLabelCounts(fixture, (row) => row.entities),
      goldProductionProjected: sumLabelCounts(fixture, (row) => projected.get(key(row.msg_id)) ?? []),
      predicted: sumLabelCounts([...latest.values()], (prediction) => prediction.entities),
    },
    representativeFailedMsgIds,
  };
}

export function renderJSONReport(report) {
  return `${JSON.stringify(report, null, 2)}\n`;
}

function renderMetricTable(title, perDomain) {
  const lines = [`### ${title}`, '', '| Domain | TP | FP | FN | Precision | Recall | F1 |', '|---|---:|---:|---:|---:|---:|---:|'];
  for (const [domain, metric] of Object.entries(perDomain)) {
    const value = (number) => number === null ? 'N/A' : number.toFixed(4);
    lines.push(`| ${domain} | ${metric.tp} | ${metric.fp} | ${metric.fn} | ${value(metric.precision)} | ${value(metric.recall)} | ${value(metric.f1)} |`);
  }
  return lines.join('\n');
}

export function renderMarkdownReport(report) {
  const value = (number) => number === null ? 'N/A' : number.toFixed(4);
  const aggregateLines = (name, aggregate) => [
    `${name} precision: ${value(aggregate.precision)}`,
    `${name} recall: ${value(aggregate.recall)}`,
    `${name} F1: ${value(aggregate.f1)}`,
  ];
  const microLines = (name, aggregate) => [
    `${name} precision: ${value(aggregate.precision)}`,
    `${name} recall: ${value(aggregate.recall)}`,
    `${name} F1: ${value(aggregate.f1)}`,
    `${name} TP/FP/FN: ${aggregate.tp}/${aggregate.fp}/${aggregate.fn}`,
  ];
  const lines = [
    '# SMS device evaluation report', '',
    `- Fixture rows: ${report.coverage.fixtureRows}`, `- Prediction coverage: ${value(report.coverage.rate)} (${report.coverage.predictedRows}/${report.coverage.fixtureRows})`,
    `- Missing rows: ${report.coverage.missingRows}`, `- Status counts: ${JSON.stringify(report.statusCounts)}`, '',
    '## Domain metrics', '',
    `Accuracy: ${value(report.domain.accuracy)}`,
    ...aggregateLines('Domain macro', report.domain.macro),
    ...microLines('Domain micro', report.domain.micro), '',
    renderMetricTable('Per-domain domain metrics', report.domain.perDomain), '',
    '### Top confusion pairs', '',
    ...(report.domain.topConfusions.length ? report.domain.topConfusions.map((item) => `- ${item.gold} → ${item.predicted}: ${item.count}`) : ['- None']), '',
    '## Entity metrics', '',
    ...aggregateLines('Raw-gold entity macro', report.entities.rawGold.macro),
    ...microLines('Raw-gold entity micro', report.entities.rawGold.micro),
    ...aggregateLines('Production-projected entity macro', report.entities.productionProjected.macro),
    ...microLines('Production-projected entity micro', report.entities.productionProjected.micro),
    `Joint exact (raw-gold): ${report.jointExact.rawGold.correct}/${report.jointExact.rawGold.total} (accuracy ${value(report.jointExact.rawGold.accuracy)})`,
    `Joint exact (production-projected): ${report.jointExact.productionProjected.correct}/${report.jointExact.productionProjected.total} (accuracy ${value(report.jointExact.productionProjected.accuracy)})`, '',
    renderMetricTable('Raw-gold per-domain entity metrics', report.entities.rawGold.perDomain), '',
    renderMetricTable('Production-projected per-domain entity metrics', report.entities.productionProjected.perDomain), '',
    `Duplicate predicted tuples: ${report.entities.duplicatePredictions}`, `Gold unsupported entities: ${report.gold_unsupported_entities}`,
    `Gold overlap rows/spans: ${report.gold_overlap_rows}/${report.gold_overlap_spans}`, `Projection exclusions: ${JSON.stringify(report.projectionExclusions)}`, '',
    '## Label distributions', '',
    `- Raw gold: ${JSON.stringify(report.labelDistributions.goldRaw)}`, `- Production projection: ${JSON.stringify(report.labelDistributions.goldProductionProjected)}`, `- Predictions: ${JSON.stringify(report.labelDistributions.predicted)}`, '',
    '## Representative failed msg_id values', '',
    ...(report.representativeFailedMsgIds.length ? report.representativeFailedMsgIds.map((msgId) => `- ${String(msgId)}`) : ['- None']), '',
  ];
  return `${lines.join('\n')}\n`;
}

function readJSONLFile(path) {
  if (!existsSync(path)) throw new Error(`input file does not exist: ${path}`);
  return parseJSONL(readFileSync(path, 'utf8'), path);
}

function outputPaths(base) {
  if (base.endsWith('.json')) return { json: base, markdown: base.slice(0, -5) + '.md' };
  if (base.endsWith('.md')) return { json: base.slice(0, -3) + '.json', markdown: base };
  return { json: `${base}.json`, markdown: `${base}.md` };
}

function main() {
  const fixturePath = process.argv[2];
  const predictionPath = process.argv[3];
  if (!fixturePath || !predictionPath) {
    console.error('Usage: node tools/score-sms-device-eval.mjs <fixture.jsonl> <predictions.jsonl> [output-stem|report.json|report.md]');
    process.exitCode = 2;
    return;
  }
  const fixture = readJSONLFile(fixturePath);
  const predictions = readJSONLFile(predictionPath);
  const report = scoreEvaluation(fixture, predictions);
  const paths = outputPaths(process.argv[4] ?? resolve(dirname(predictionPath), 'sms-device-eval-report'));
  mkdirSync(dirname(paths.json), { recursive: true });
  writeFileSync(paths.json, renderJSONReport(report));
  writeFileSync(paths.markdown, renderMarkdownReport(report));
  console.log(`wrote JSON report to ${paths.json}`);
  console.log(`wrote Markdown report to ${paths.markdown}`);
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url))) main();
