// Pure helpers for monthly (OBHS) contract bills. No I/O so they can be unit-tested.
import { computeContractDays, overlappingDays, monthRange, daysInMonth, parseDate } from './period.js';

const num = (v, d = 0) => {
  const n = Number(v);
  return Number.isFinite(n) ? n : d;
};
const round2 = (v) => Math.round(v * 100) / 100;

/** Contract statuses are stored in mixed case ('Active' / 'ACTIVE'); treat them the same. */
export const isActiveStatus = (status) => String(status || '').trim().toUpperCase() === 'ACTIVE';

/** Contracts without a type (legacy) are OBHS; station cleaning and MCC have their own billing. */
export const isObhsContract = (contract) => {
  const t = String(contract?.contractType || '').toLowerCase();
  return t !== 'station_cleaning' && t !== 'mcc';
};

/**
 * Billable base for one calendar month: the contract value spread over its real
 * start/end dates (same convention as the estimation engine) and limited to the
 * days of this month that fall inside the contract.
 */
export function monthlyBase(contract, month, year) {
  const contractValue = num(contract?.contractValue);
  const contractDays = num(contract?.contractDays) || computeContractDays(contract?.startDate, contract?.endDate);
  const { start, end } = monthRange(month, year);
  if (!contractDays) {
    // No usable dates: fall back to the whole value for the month (previous behaviour).
    return { base: round2(contractValue), daysInPeriod: daysInMonth(month, year), contractDays: 0, prorated: false };
  }
  const days = overlappingDays({ periodStart: start, periodEnd: end, itemStart: contract.startDate, itemEnd: contract.endDate });
  return {
    base: round2((contractValue * days) / contractDays),
    daysInPeriod: days,
    contractDays,
    prorated: true,
  };
}

/** Deduction % for an overall score, using the bands the billing screen saves. */
export function deductionPctForScore(rule, score) {
  const has = (k) => rule && rule[k] !== undefined && rule[k] !== null;
  const bands = ['penaltyScore90Plus', 'penaltyScore80To89', 'penaltyScore70To79', 'penaltyScoreBelow70'];
  if (!bands.some(has)) return num(rule?.deductionRate); // legacy single-rate rules
  if (score >= 90) return num(rule.penaltyScore90Plus);
  if (score >= 80) return num(rule.penaltyScore80To89);
  if (score >= 70) return num(rule.penaltyScore70To79);
  return num(rule.penaltyScoreBelow70);
}

export const gradeForScore = (s) => (s >= 90 ? 'A' : s >= 80 ? 'B' : s >= 70 ? 'C' : 'D');

/** Amounts for a bill. Performance deduction is a % of the month's base; extras are flat amounts. */
export function computeBillAmounts({ rule, base, overallScore, counts = {}, otherPenalties = 0 }) {
  const score = num(overallScore, 100);
  const pct = deductionPctForScore(rule, score);
  const performanceDeduction = round2((base * pct) / 100);

  const extras = [
    { type: 'Manpower Shortage', count: num(counts.manpowerShortageCount), rate: num(rule?.manpowerShortagePenalty) },
    { type: 'Machine Shortage', count: num(counts.machineShortageCount), rate: num(rule?.machineShortagePenalty) },
    { type: 'Missed OBHS Complaint', count: num(counts.missedObhsCount), rate: num(rule?.missedObhsComplaintPenalty) },
  ]
    .filter((e) => e.count > 0 && e.rate > 0)
    .map((e) => ({ type: e.type, description: `${e.count} x ${e.rate}`, count: e.count, rate: e.rate, amount: round2(e.count * e.rate) }));
  if (num(otherPenalties) > 0) {
    extras.push({ type: 'Other', description: 'Other penalties', count: 1, rate: num(otherPenalties), amount: round2(num(otherPenalties)) });
  }

  const deductions = [
    { type: 'Performance', description: `Score ${score}% -> ${pct}% of monthly value`, count: 1, rate: pct, amount: performanceDeduction },
    ...extras,
  ];
  const totalDeduction = round2(deductions.reduce((s, d) => s + d.amount, 0));
  return {
    overallScore: score,
    grade: gradeForScore(score),
    performanceDeductionPct: pct,
    deductions,
    totalDeduction,
    finalPayable: Math.max(0, round2(base - totalDeduction)),
  };
}

/** Parses "87.5%" / 87.5 / undefined into a number (or null). */
export function parsePct(v) {
  if (v === undefined || v === null || v === '') return null;
  const n = parseFloat(String(v));
  return Number.isFinite(n) ? n : null;
}

/** Average of the form scores that fall in the month. `forms` = [{ formDateTime, pct }]. */
export function averageForMonth(forms, month, year) {
  const m = parseInt(month, 10);
  const y = parseInt(year, 10);
  const scores = [];
  for (const f of forms || []) {
    const d = parseDate(f.formDateTime);
    if (!d || d.getUTCFullYear() !== y || d.getUTCMonth() + 1 !== m) continue;
    if (f.pct === null || f.pct === undefined) continue;
    scores.push(f.pct);
  }
  if (!scores.length) return null;
  return round2(scores.reduce((a, b) => a + b, 0) / scores.length);
}

/**
 * Weighted overall score from per-category averages. Only categories that actually have
 * data take part (weights are re-normalised), so a month with no premises forms is not
 * dragged to zero. Returns null when there is no data at all.
 */
export function weightedOverallScore(categoryScores, rule) {
  const weights = {
    Coach: num(rule?.coachWeightage, 35),
    Premise: num(rule?.premiseWeightage, 35),
    OBHS: num(rule?.obhsWeightage, 15),
  };
  let totalWeight = 0;
  let sum = 0;
  const breakdown = {};
  for (const [name, score] of Object.entries(categoryScores)) {
    if (score === null || score === undefined) continue;
    const w = weights[name] ?? 0;
    breakdown[name] = score;
    if (w <= 0) continue;
    totalWeight += w;
    sum += score * w;
  }
  if (!Object.keys(breakdown).length) return null;
  const overall = totalWeight > 0
    ? round2(sum / totalWeight)
    : round2(Object.values(breakdown).reduce((a, b) => a + b, 0) / Object.keys(breakdown).length);
  return { overallScore: overall, breakdown };
}

/** Completed calendar months (oldest first) that overlap the contract, looking back at most `maxBack` months. */
export function completedMonthsToBill(contract, now = new Date(), maxBack = 12) {
  const out = [];
  const start = parseDate(contract?.startDate);
  const end = parseDate(contract?.endDate);
  for (let i = maxBack; i >= 1; i--) {
    const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - i, 1));
    const month = d.getUTCMonth() + 1;
    const year = d.getUTCFullYear();
    if (start || end) {
      const { start: ms, end: me } = monthRange(month, year);
      if (overlappingDays({
        periodStart: ms, periodEnd: me,
        itemStart: contract.startDate || ms, itemEnd: contract.endDate || me,
      }) <= 0) continue;
    }
    out.push({ month, year });
  }
  return out;
}
