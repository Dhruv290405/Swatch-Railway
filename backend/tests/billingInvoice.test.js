import { describe, it, expect, vi, beforeEach } from 'vitest';

const store = {};
let seq = 0;
const reset = () => {
  for (const k of Object.keys(store)) delete store[k];
  Object.assign(store, {
    billingRules: [{ uid: 'r1', contractId: 'c1', penaltyScore90Plus: 0, penaltyScore80To89: 2, penaltyScore70To79: 5, penaltyScoreBelow70: 10, coachWeightage: 35, premiseWeightage: 35, obhsWeightage: 15 }],
    contracts: [
      { uid: 'c1', contractNumber: 'OBHS-1', contractValue: 365000, contractDays: 365, startDate: '2026-01-01', endDate: '2026-12-31', status: 'Active', contractType: 'obhs', entityId: 'e1', division: 'DELHI', zone: 'NR' },
      { uid: 'c2', contractNumber: 'SC-1', contractValue: 100, startDate: '2026-01-01', endDate: '2026-12-31', status: 'Active', contractType: 'station_cleaning' },
      { uid: 'c3', contractNumber: 'OLD', contractValue: 100, startDate: '2026-01-01', endDate: '2026-12-31', status: 'Expired', contractType: 'obhs' },
    ],
    billingReports: [], coachForms: [], premisesForms: [], ctsForms: [],
  });
};

const query = (name, filters = []) => ({
  where: (f, op, v) => query(name, [...filters, [f, op, v]]),
  limit: () => query(name, filters),
  get: async () => {
    const docs = (store[name] || [])
      .filter((d) => filters.every(([f, op, v]) => (op === '==' ? d[f] === v : op === 'in' ? v.includes(d[f]) : true)))
      .map((d) => ({ id: d.uid, data: () => d }));
    return { empty: docs.length === 0, docs, forEach: (fn) => docs.forEach(fn) };
  },
});

vi.mock('../src/database/index.js', () => ({
  db: {
    collection: (name) => ({
      ...query(name),
      doc: (id) => {
        const docId = id || `gen${++seq}`;
        return {
          id: docId,
          get: async () => {
            const row = (store[name] || []).find((d) => d.uid === docId);
            return { exists: !!row, data: () => row };
          },
          set: async (d) => { (store[name] ||= []).push(d); },
        };
      },
    }),
  },
  admin: {},
}));
vi.mock('../src/services/auditService.js', () => ({ auditService: { logAudit: vi.fn(async () => {}) } }));

const { billingService } = await import('../src/services/billingService.js');
const user = { uid: 'u1', fullName: 'Tester' };

beforeEach(() => { reset(); seq = 0; });

describe('createInvoice', () => {
  it('bills the month share of the contract, not the whole contract value', async () => {
    const res = await billingService.createInvoice(user, { contractId: 'c1', month: 1, year: 2026, overallScore: 100 });
    const bill = store.billingReports[0];
    expect(res.uid).toBe(bill.uid);
    expect(bill.monthlyBase).toBe(31000);
    expect(bill.totalContractValue).toBe(365000);
    expect(bill.finalPayable).toBe(31000);
  });

  it('is idempotent: the same contract + month returns the existing bill', async () => {
    const a = await billingService.createInvoice(user, { contractId: 'c1', month: 2, year: 2026 });
    const b = await billingService.createInvoice(user, { contractId: 'c1', month: 2, year: 2026 });
    expect(b.existing).toBe(true);
    expect(b.uid).toBe(a.uid);
    expect(store.billingReports).toHaveLength(1);
  });

  it('a rejected bill may be generated again', async () => {
    await billingService.createInvoice(user, { contractId: 'c1', month: 3, year: 2026 });
    store.billingReports[0].status = 'REJECTED';
    const again = await billingService.createInvoice(user, { contractId: 'c1', month: 3, year: 2026 });
    expect(again.existing).toBeUndefined();
    expect(store.billingReports).toHaveLength(2);
  });

  it('uses the real form score instead of the score the client sent', async () => {
    store.coachForms.push({ uid: 'f1', contractId: 'c1', status: 'LOCKED', formDateTime: '2026-04-10T10:00:00Z', ratingDetails: { summary: { overallAveragePct: '72%' } } });
    await billingService.createInvoice(user, { contractId: 'c1', month: 4, year: 2026, overallScore: 85 });
    const bill = store.billingReports[0];
    expect(bill.overallScore).toBe(72);
    expect(bill.scoreSource).toBe('forms');
    expect(bill.performanceDeductionPct).toBe(5);        // 70-79 band
    expect(bill.finalPayable).toBe(30000 - 1500);        // 30 days of April, 5%
  });

  it('keeps the client score only when there is no form data (older app versions)', async () => {
    await billingService.createInvoice(user, { contractId: 'c1', month: 5, year: 2026, overallScore: 85 });
    expect(store.billingReports[0].scoreSource).toBe('client');
    expect(store.billingReports[0].overallScore).toBe(85);
  });

  it('rejects a month the contract is not in force and invalid input', async () => {
    await expect(billingService.createInvoice(user, { contractId: 'c1', month: 3, year: 2027 })).rejects.toThrow(/not in force/);
    await expect(billingService.createInvoice(user, { contractId: 'c1', month: 13, year: 2026 })).rejects.toThrow(/valid month/i);
    await expect(billingService.createInvoice(user, { month: 1, year: 2026 })).rejects.toThrow(/contractId/);
  });
});

describe('monthly generation', () => {
  it('bills only active OBHS contracts that have a billing rule', async () => {
    const res = await billingService.generateMonthlyBills({ month: 6, year: 2026, user });
    expect(res.generated).toBe(1);
    expect(store.billingReports.map((b) => b.contractId)).toEqual(['c1']);
  });

  it('catch-up fills every completed month once and never duplicates', async () => {
    const first = await billingService.ensureMonthlyBills(user, { monthsBack: 12 });
    const second = await billingService.ensureMonthlyBills(user, { monthsBack: 12 });
    expect(first.generated).toBeGreaterThan(0);
    expect(second.generated).toBe(0);
    const keys = store.billingReports.map((b) => `${b.contractId}-${b.year}-${b.month}`);
    expect(new Set(keys).size).toBe(keys.length);
  });
});
