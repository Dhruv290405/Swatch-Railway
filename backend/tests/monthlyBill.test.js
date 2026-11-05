import { describe, it, expect } from 'vitest';
import {
  monthlyBase, deductionPctForScore, computeBillAmounts, averageForMonth, weightedOverallScore,
  completedMonthsToBill, isActiveStatus, isObhsContract, parsePct,
} from '../src/utils/monthlyBill.js';

const contract = { contractValue: 365000, startDate: '2026-01-01', endDate: '2026-12-31', contractDays: 365 };
const rule = {
  penaltyScore90Plus: 0, penaltyScore80To89: 2, penaltyScore70To79: 5, penaltyScoreBelow70: 10,
  manpowerShortagePenalty: 500, machineShortagePenalty: 1000, missedObhsComplaintPenalty: 2000,
  coachWeightage: 35, premiseWeightage: 35, obhsWeightage: 15,
};

describe('monthlyBase', () => {
  it('spreads the contract value over its real days', () => {
    expect(monthlyBase(contract, 1, 2026).base).toBe(31000);   // 31 / 365 of 365000
    expect(monthlyBase(contract, 2, 2026).base).toBe(28000);
  });
  it('only counts the days of the month that are inside the contract', () => {
    const c = { ...contract, startDate: '2026-01-16' };
    const r = monthlyBase(c, 1, 2026);
    expect(r.daysInPeriod).toBe(16);
  });
  it('reports zero days for a month outside the contract', () => {
    expect(monthlyBase(contract, 3, 2027).daysInPeriod).toBe(0);
  });
  it('falls back to the whole value when the contract has no usable dates (legacy)', () => {
    const r = monthlyBase({ contractValue: 5000 }, 4, 2026);
    expect(r.base).toBe(5000);
    expect(r.prorated).toBe(false);
  });
});

describe('deductions', () => {
  it('uses the score bands the billing screen saves', () => {
    expect(deductionPctForScore(rule, 95)).toBe(0);
    expect(deductionPctForScore(rule, 85)).toBe(2);
    expect(deductionPctForScore(rule, 75)).toBe(5);
    expect(deductionPctForScore(rule, 40)).toBe(10);
  });
  it('still honours a legacy single deductionRate', () => {
    expect(deductionPctForScore({ deductionRate: 7 }, 50)).toBe(7);
  });
  it('applies performance % plus flat penalties and never goes below zero', () => {
    const a = computeBillAmounts({ rule, base: 100000, overallScore: 85, counts: { manpowerShortageCount: 2, missedObhsCount: 1 }, otherPenalties: 300 });
    expect(a.grade).toBe('B');
    expect(a.deductions.find((d) => d.type === 'Performance').amount).toBe(2000);
    expect(a.totalDeduction).toBe(2000 + 1000 + 2000 + 300);
    expect(a.finalPayable).toBe(100000 - a.totalDeduction);
    expect(computeBillAmounts({ rule, base: 100, overallScore: 10, otherPenalties: 99999 }).finalPayable).toBe(0);
  });
});

describe('scores from forms', () => {
  it('parses percentage strings', () => {
    expect(parsePct('87.5%')).toBe(87.5);
    expect(parsePct(undefined)).toBeNull();
  });
  it('averages only the forms inside the month', () => {
    const forms = [
      { formDateTime: '2026-05-03T10:00:00Z', pct: 80 },
      { formDateTime: '2026-05-20T10:00:00Z', pct: 90 },
      { formDateTime: '2026-06-01T10:00:00Z', pct: 10 },
      { formDateTime: '2026-05-21T10:00:00Z', pct: null },
    ];
    expect(averageForMonth(forms, 5, 2026)).toBe(85);
    expect(averageForMonth(forms, 7, 2026)).toBeNull();
  });
  it('re-normalises weights over the categories that have data', () => {
    const r = weightedOverallScore({ Coach: 90, Premise: null, OBHS: 60 }, rule);
    // (90*35 + 60*15) / 50 = 81
    expect(r.overallScore).toBe(81);
    expect(r.breakdown).toEqual({ Coach: 90, OBHS: 60 });
  });
  it('returns null when no category has data', () => {
    expect(weightedOverallScore({ Coach: null, Premise: null, OBHS: null }, rule)).toBeNull();
  });
});

describe('which months to bill', () => {
  it('lists completed months that overlap the contract, oldest first', () => {
    const now = new Date(Date.UTC(2026, 5, 15)); // 15 Jun 2026
    const months = completedMonthsToBill({ ...contract, startDate: '2026-03-10' }, now, 12);
    expect(months).toEqual([{ month: 3, year: 2026 }, { month: 4, year: 2026 }, { month: 5, year: 2026 }]);
  });
  it('never includes the current month', () => {
    const now = new Date(Date.UTC(2026, 5, 15));
    expect(completedMonthsToBill(contract, now, 3).map((m) => m.month)).toEqual([3, 4, 5]);
  });
});

describe('contract filters', () => {
  it('treats Active / ACTIVE the same', () => {
    expect(isActiveStatus('Active')).toBe(true);
    expect(isActiveStatus('ACTIVE')).toBe(true);
    expect(isActiveStatus('Expired')).toBe(false);
  });
  it('only OBHS (or untyped legacy) contracts get OBHS bills', () => {
    expect(isObhsContract({ contractType: 'obhs' })).toBe(true);
    expect(isObhsContract({})).toBe(true);
    expect(isObhsContract({ contractType: 'station_cleaning' })).toBe(false);
    expect(isObhsContract({ contractType: 'mcc' })).toBe(false);
  });
});
