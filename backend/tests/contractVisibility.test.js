import { describe, it, expect, vi } from 'vitest';

const rows = [
  { uid: 'd1', division: 'DELHI', entityId: 'e1', status: 'Active' },
  { uid: 'm1', division: 'MUMBAI', entityId: 'e2', status: 'Active' },
  { uid: 'legacy', entityId: 'e1', status: 'Active' }, // no division on record
];
const query = { where: () => query, limit: () => query, get: async () => ({ empty: false, forEach: (fn) => rows.forEach((r) => fn({ id: r.uid, data: () => r })) }) };
vi.mock('../src/database/index.js', () => ({ db: { collection: () => query, Timestamp: () => 'ts' }, admin: {} }));

const { contractService } = await import('../src/services/contractService.js');
const ids = async (user) => (await contractService.getContracts(user, {})).contracts.map((c) => c.uid).sort();

describe('contract list scoping', () => {
  it('a division-level railway admin only sees their own division (and un-divisioned legacy contracts)', async () => {
    expect(await ids({ userType: 'railway', role: 'RAILWAY_ADMIN', division: 'Delhi' })).toEqual(['d1', 'legacy']);
    expect(await ids({ userType: 'railway', role: 'Railway Supervisor', division: 'MUMBAI' })).toEqual(['legacy', 'm1']);
    expect(await ids({ userType: 'railway', role: 'RAILWAY_INSPECTOR', division: 'DELHI' })).toEqual(['d1', 'legacy']);
  });
  it('masters and admins without a division keep the full view', async () => {
    expect(await ids({ userType: 'railway', role: 'RAILWAY_MASTER', division: 'DELHI' })).toEqual(['d1', 'legacy', 'm1']);
    expect(await ids({ userType: 'railway', role: 'SUPER_ADMIN' })).toEqual(['d1', 'legacy', 'm1']);
    expect(await ids({ userType: 'railway', role: 'RAILWAY_ADMIN' })).toEqual(['d1', 'legacy', 'm1']);
  });
});
