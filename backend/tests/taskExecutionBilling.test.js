import { describe, it, expect } from 'vitest';

/* ==========================================================================
   Task Execution billing engine (50% component): AREA -> SQFT -> RATE ->
   EXECUTION daily billing, task-execution score, penalty slabs & edge cases.
   Area weightage is removed from this module.
   ========================================================================== */

const {
  computeDailyTaskBilling,
  aggregateTaskAreaRows,
  applyPenaltyRules,
  taskExecutionBillingService,
} = await import('../src/services/taskExecutionBillingService.js');
const { computeContractDays, daysInMonth, overlappingDays, monthRange } = await import('../src/utils/period.js');

describe('computeContractDays - date-based contract periods', () => {
  it('computes the reference 1461 days for a 4-year contract', () => {
    expect(computeContractDays('2023-01-01', '2026-12-31')).toBe(1461);
  });
  it('computes inclusive days for the reference 11-Feb-2023 → 14-May-2026 scope', () => {
    expect(computeContractDays('2023-02-11', '2026-05-14')).toBe(1189);
  });
  it('handles leap years and single-day contracts', () => {
    expect(computeContractDays('2024-01-01', '2024-12-31')).toBe(366);
    expect(computeContractDays('2026-09-13', '2026-09-13')).toBe(1);
  });
  it('returns 0 for invalid or reversed ranges', () => {
    expect(computeContractDays('bad', '2026-09-13')).toBe(0);
    expect(computeContractDays('2026-09-13', '2026-09-01')).toBe(0);
    expect(computeContractDays(null, '2026-09-13')).toBe(0);
  });
});

describe('overlappingDays - mid-period proration (e.g. 16 applicable days)', () => {
  it('prorates an item active in the middle of a period', () => {
    expect(overlappingDays({ periodStart: '2026-09-01', periodEnd: '2026-09-30', itemStart: '2026-09-10', itemEnd: '2026-09-25' })).toBe(16);
  });
  it('returns the full period when the item spans it completely', () => {
    expect(overlappingDays({ periodStart: '2026-09-01', periodEnd: '2026-09-30', itemStart: '2026-01-01', itemEnd: '2026-12-31' })).toBe(30);
  });
  it('returns 0 when the item is outside the period', () => {
    expect(overlappingDays({ periodStart: '2026-09-01', periodEnd: '2026-09-30', itemStart: '2026-10-01', itemEnd: '2026-10-15' })).toBe(0);
  });
});

describe('daysInMonth / monthRange', () => {
  it('returns correct day counts', () => {
    expect(daysInMonth(2, 2024)).toBe(29);
    expect(daysInMonth(2, 2026)).toBe(28);
    expect(daysInMonth(9, 2026)).toBe(30);
  });
  it('builds month windows', () => {
    expect(monthRange(9, 2026)).toEqual({ start: '2026-09-01', end: '2026-09-30' });
    expect(monthRange(1, 2026)).toEqual({ start: '2026-01-01', end: '2026-01-31' });
  });
});

describe('aggregateTaskAreaRows - tasks into per-area execution rows', () => {
  const meta = {
    pf1: { areaName: 'PF-01', basicAreaSqFt: 25000, cleaningFrequency: 'daily' },
    pf2: { areaName: 'PF-02 & 03', basicAreaSqFt: 20000 },
  };
  const config = { ratePerSqft: 0.75, areaRateOverrides: {} };
  const task = (areaId, status) => ({ areaId, areaName: meta[areaId].areaName, status });
  // Approved shift summaries are the execution source (there is no task-approval
  // step). Build a single approved summary whose area entries carry `times`
  // mirroring the old "approved" task counts so expectations stay stable.
  const approvedSummariesFor = (tasks) => {
    const byArea = {};
    tasks.forEach((t) => {
      if (String(t.status || '').toLowerCase() === 'approved') byArea[t.areaId] = (byArea[t.areaId] || 0) + 1;
    });
    return [{
      date: '2026-09-17', shift: 'night', status: 'approved',
      areas: Object.entries(byArea).map(([areaId, times]) => ({ areaId, times })),
    }];
  };

  it('values each area by sqft x rate x executions', () => {
    const tasks = [
      task('pf1', 'approved'), task('pf1', 'approved'), task('pf1', 'approved'), task('pf1', 'missed'),
      task('pf2', 'approved'), task('pf2', 'completed'),
    ];
    const rows = aggregateTaskAreaRows(tasks, meta, config, approvedSummariesFor(tasks));
    const pf1 = rows.find(r => r.areaId === 'pf1');
    expect(pf1.required).toBe(4);
    expect(pf1.completed).toBe(3);
    expect(pf1.expectedSqft).toBe(100000);
    expect(pf1.executedSqft).toBe(75000);
    expect(pf1.expectedValue).toBe(75000);      // 25000 x 0.75 x 4
    expect(pf1.actualExecutionValue).toBe(56250); // 25000 x 0.75 x 3
    expect(pf1.achievement).toBe(75);
  });

  it('counts completed executions only from approved shift summaries (not task status)', () => {
    const tasks = [task('pf2', 'completed'), task('pf2', 'approved'), task('pf2', 'rejected')];
    const rows = aggregateTaskAreaRows(tasks, meta, config, approvedSummariesFor(tasks));
    const pf2 = rows.find(r => r.areaId === 'pf2');
    expect(pf2.required).toBe(3);
    expect(pf2.completed).toBe(1); // only the approved-summary execution counts
  });

  it('caps completed executions at the tasks required for the area', () => {
    const tasks = [task('pf1', 'completed'), task('pf1', 'completed')];
    const summaries = [{
      date: '2026-09-17', shift: 'night', status: 'approved',
      areas: [{ areaId: 'pf1', times: 5 }],
    }];
    const rows = aggregateTaskAreaRows(tasks, meta, config, summaries);
    const pf1 = rows.find(r => r.areaId === 'pf1');
    expect(pf1.required).toBe(2);
    expect(pf1.completed).toBe(2); // capped at required, never above
    expect(pf1.achievement).toBe(100);
  });

  it('skips tasks on unknown areas (inactive filtering is the caller\'s job)', () => {
    const tasks = [task('pf1', 'approved'), { areaId: 'ghost', status: 'approved' }];
    const rows = aggregateTaskAreaRows(tasks, meta, config, approvedSummariesFor(tasks));
    expect(rows).toHaveLength(1);
    expect(rows[0].areaId).toBe('pf1');
  });

  it('uses per-area rate overrides when present', () => {
    const cfg2 = { ...config, areaRateOverrides: { pf1: 0.45 } };
    const tasks = [task('pf1', 'approved')];
    const rows = aggregateTaskAreaRows(tasks, meta, cfg2, approvedSummariesFor(tasks));
    expect(rows[0].ratePerSqft).toBe(0.45);
    expect(rows[0].actualExecutionValue).toBe(11250); // 25000 x 0.45
  });

  it('returns empty rows for no tasks', () => {
    expect(aggregateTaskAreaRows([], meta, config)).toEqual([]);
  });
});

describe('computeDailyTaskBilling - AREA -> SQFT -> RATE -> EXECUTION daily billing', () => {
  const venusConfig = {
    ratePerSqft: 0.75,
    areaRateOverrides: {},
    gstRate: 18,
    categories: [
      { code: 'EXECUTION', name: 'Task Execution', maxMarks: 50, dataSource: 'execution', enabled: true, order: 1 },
      { code: 'INSPECTION', name: 'Railway Inspection', maxMarks: 20, dataSource: 'inspection', enabled: true, order: 2 },
      { code: 'FEEDBACK', name: 'Passenger Feedback', maxMarks: 30, dataSource: 'feedback', enabled: true, order: 3 },
    ],
    penaltyRules: [
      { uid: 'r1', name: '>=85 none', fromScore: 85, toScore: 101, action: 'NONE', value: 0, maxAmount: null, enabled: true },
      { uid: 'r2', name: '60-85 2%', fromScore: 60, toScore: 85, action: 'PERCENT_OF_ELIGIBLE', value: 2, maxAmount: null, enabled: true },
      { uid: 'r3', name: '<60 5%', fromScore: 0, toScore: 60, action: 'PERCENT_OF_ELIGIBLE', value: 5, maxAmount: null, enabled: true },
    ],
  };

  // Approved shift summaries are the execution source (no task-approval step).
  const approvedSummariesFor = (tasks) => {
    const byArea = {};
    tasks.forEach((t) => {
      if (String(t.status || '').toLowerCase() === 'approved') byArea[t.areaId] = (byArea[t.areaId] || 0) + 1;
    });
    return [{
      date: '2026-09-17', shift: 'night', status: 'approved',
      areas: Object.entries(byArea).map(([areaId, times]) => ({ areaId, times })),
    }];
  };

  it('computes the reference multi-area example exactly', () => {
    const tasks = [
      { areaId: 'pf1', status: 'approved' }, { areaId: 'pf1', status: 'approved' }, { areaId: 'pf1', status: 'approved' }, { areaId: 'pf1', status: 'missed' },
      { areaId: 'pf2', status: 'approved' }, { areaId: 'pf2', status: 'approved' },
      { areaId: 'pf4', status: 'approved' }, { areaId: 'pf4', status: 'approved' }, { areaId: 'pf4', status: 'approved' }, { areaId: 'pf4', status: 'missed' },
    ];
    const r = computeDailyTaskBilling({
      areaRows: aggregateTaskAreaRows(tasks, {
        pf1: { areaName: 'PF-01', basicAreaSqFt: 25000 },
        pf2: { areaName: 'PF-02 & 03', basicAreaSqFt: 20000 },
        pf4: { areaName: 'PF-04 & 05', basicAreaSqFt: 47261 },
      }, { ratePerSqft: 0.75, areaRateOverrides: { pf4: 0.45 } }, approvedSummariesFor(tasks)),
      config: venusConfig,
      inspection: { count: 2, achievement: 80 },
      feedback: { count: 5, achievement: 90 },
    });
    expect(r.expectedWorkValue).toBeCloseTo(190069.80, 2);   // 75000 + 30000 + 85069.80
    expect(r.actualExecutionValue).toBeCloseTo(150052.35, 2); // 56250 + 30000 + 63802.35
    expect(r.grossAmount).toBe(r.actualExecutionValue);
    expect(r.expectedSqFt).toBeCloseTo(329044, 0);
    expect(r.executedSqFt).toBeCloseTo(256783, 0);
    // Score is value-weighted (actual / expected work value), not raw sq.ft.
    expect(r.taskExecutionScore).toBeCloseTo(78.95, 1);      // 150052.35 / 190069.80
  });

  it('weights categories 50/20/30 and caps eligible at actual execution', () => {
    const tasks = [{ areaId: 'pf1', status: 'approved' }, { areaId: 'pf1', status: 'missed' }];
    const r = computeDailyTaskBilling({
      areaRows: aggregateTaskAreaRows(
        tasks,
        { pf1: { areaName: 'PF-01', basicAreaSqFt: 1000 } },
        { ratePerSqft: 1.00, areaRateOverrides: {} }, approvedSummariesFor(tasks),
      ),
      config: venusConfig,
      inspection: { count: 1, achievement: 80 },
      feedback: { count: 1, achievement: 100 },
    });
    // exec 50/100 x50%=25, insp 80/100 x20%=16, fb 100/100 x30%=30 -> 71
    expect(r.categories.find(c => c.dataSource === 'execution').marks).toBe(25);
    expect(r.categories.find(c => c.dataSource === 'inspection').marks).toBe(16);
    expect(r.categories.find(c => c.dataSource === 'feedback').marks).toBe(30);
    expect(r.overallScore).toBe(71);
    // Work value stays the executed value; the score only selects the penalty slab.
    expect(r.grossEligibleWorkValue).toBeCloseTo(1000, 2);
    expect(r.penalty.totalPenalty).toBe(20);                // slab 60-85 -> 2% of eligible
    expect(r.netAmount).toBeCloseTo(980, 2);
  });

  it('treats missing inspection/feedback on a day as fully achieved (neutral)', () => {
    const tasks = [{ areaId: 'pf1', status: 'approved' }];
    const r = computeDailyTaskBilling({
      areaRows: aggregateTaskAreaRows(
        tasks,
        { pf1: { areaName: 'PF-01', basicAreaSqFt: 1000 } },
        { ratePerSqft: 1.00, areaRateOverrides: {} }, approvedSummariesFor(tasks),
      ),
      config: venusConfig,
    });
    const insp = r.categories.find(c => c.dataSource === 'inspection');
    const fb = r.categories.find(c => c.dataSource === 'feedback');
    expect(insp.notApplicable).toBe(true);
    expect(insp.achievement).toBe(100);
    expect(insp.marks).toBe(20);
    expect(fb.marks).toBe(30);
    expect(r.overallScore).toBe(100); // 50 + 20 + 30 (all full)
    expect(r.incompleteExecutionPenaltyAmount).toBe(0);
    expect(r.grossEligibleWorkValue).toBe(1000);
  });

  it('never pays for unexecuted passes (eligible capped at actual value)', () => {
    const tasks = [{ areaId: 'pf1', status: 'approved' }, { areaId: 'pf1', status: 'missed' }];
    const r = computeDailyTaskBilling({
      areaRows: aggregateTaskAreaRows(
        tasks,
        { pf1: { areaName: 'PF-01', basicAreaSqFt: 1000 } },
        { ratePerSqft: 1.00, areaRateOverrides: {} }, approvedSummariesFor(tasks),
      ),
      config: venusConfig,
      inspection: { count: 1, achievement: 50 },
      feedback: { count: 1, achievement: 50 },
    });
    expect(r.expectedWorkValue).toBe(2000);
    expect(r.actualExecutionValue).toBe(1000);
    // exec 1000/2000 x50%=25, insp 10, fb 15 -> 50; eligible work value is the executed value only
    expect(r.overallScore).toBe(50);
    expect(r.grossEligibleWorkValue).toBe(1000);
    expect(r.grossEligibleWorkValue).toBeLessThanOrEqual(r.actualExecutionValue);
  });

  it('applies the configured penalty slab keyed off the final score', () => {
    const tasks = [{ areaId: 'pf1', status: 'approved' }, { areaId: 'pf1', status: 'missed' }];
    const r = computeDailyTaskBilling({
      areaRows: aggregateTaskAreaRows(
        tasks,
        { pf1: { areaName: 'PF-01', basicAreaSqFt: 1000 } },
        { ratePerSqft: 1.00, areaRateOverrides: {} }, approvedSummariesFor(tasks),
      ),
      config: venusConfig,
      inspection: { count: 1, achievement: 50 },
      feedback: { count: 1, achievement: 50 },
    });
    // exec 50 x50%=25, insp 50 x20%=10, fb 50 x30%=15 -> overall 50 -> slab <60: 5% of eligible (1000) = 50
    expect(r.overallScore).toBe(50);
    expect(r.penalty.applied).toBe(true);
    expect(r.penalty.totalPenalty).toBe(50);
    expect(r.netAmount).toBe(950);
    expect(r.gstAmount).toBeCloseTo(171, 2);
    expect(r.totalPayable).toBeCloseTo(1121, 2);
  });

  it('returns zeros / nulls safely when nothing has been executed', () => {
    const r = computeDailyTaskBilling({ areaRows: [], config: venusConfig });
    expect(r.taskExecutionScore).toBeNull();
    expect(r.expectedWorkValue).toBe(0);
    expect(r.actualExecutionValue).toBe(0);
    expect(r.netAmount).toBe(0);
    expect(r.overallScore).toBe(100); // neutral categories keep the day's score full
  });
});

describe('applyPenaltyRules - configurable slabs', () => {
  const rules = [
    { uid: 'r1', action: 'NONE', fromScore: 85, toScore: 101, value: 0, enabled: true },
    { uid: 'r2', action: 'PERCENT_OF_ELIGIBLE', fromScore: 60, toScore: 85, value: 2, enabled: true },
    { uid: 'r3', action: 'FIXED_AMOUNT', fromScore: 0, toScore: 60, value: 500, enabled: true, maxAmount: 100 },
  ];

  it('applies no penalty on a high score', () => {
    const p = applyPenaltyRules(rules, 92, 10000, 8000);
    expect(p.applied).toBe(false);
    expect(p.totalPenalty).toBe(0);
  });

  it('takes the FIRST matching slab', () => {
    const p = applyPenaltyRules(rules, 75, 10000, 8000);
    expect(p.rows[0].uid).toBe('r2');
    expect(p.totalPenalty).toBe(160);
  });

  it('honours maxAmount and FIXED_AMOUNT actions', () => {
    const p = applyPenaltyRules(rules, 40, 10000, 8000);
    expect(p.rows[0].uid).toBe('r3');
    expect(p.totalPenalty).toBe(100); // capped from 500
  });

  it('is safe with no rules', () => {
    expect(applyPenaltyRules([], 50, 10000, 8000)).toEqual({ applied: false, rows: [], totalPenalty: 0 });
  });
});

describe('taskExecutionBillingService - method coverage', () => {
  it('exports the expected DB methods (weightage methods removed)', () => {
    const expected = [
      'prepareDailyBill', 'previewDailyBill', 'generateDailyBill',
      'getDailyBill', 'listDailyBills',
    ];
    for (const m of expected) {
      expect(typeof taskExecutionBillingService[m], `Missing: ${m}`).toBe('function');
    }
    expect(taskExecutionBillingService.getWeightages).toBeUndefined();
    expect(taskExecutionBillingService.upsertWeightage).toBeUndefined();
    expect(taskExecutionBillingService.deleteWeightage).toBeUndefined();
  });
});