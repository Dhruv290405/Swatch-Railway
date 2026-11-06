import { describe, it, expect } from 'vitest';
import { assignedTrainIds, visibleTrainFilter } from '../src/utils/assignedTrains.js';

const contracts = {
  c1: { entityId: 'e1', status: 'Active', contractType: 'obhs', trainIds: ['t1', 't2'] },
  c2: { entityId: 'e1', status: 'Active', contractType: 'obhs', trainIds: ['t3'] },
  c3: { entityId: 'e1', status: 'Active', contractType: 'station_cleaning', trainIds: ['t9'] },
  c4: { entityId: 'e1', status: 'Inactive', contractType: 'obhs', trainIds: ['t8'] },
  c5: { entityId: 'e2', status: 'Active', contractType: 'obhs', trainIds: ['t7'] },
};
const members = { u1: { entityId: 'e1' }, u2: { entityId: 'e1' }, u9: { entityId: 'e2' } };
const database = {
  collection: () => ({
    doc: (id) => ({ get: async () => ({ exists: !!contracts[id], data: () => contracts[id] }) }),
    where: (_f, _o, v) => ({
      limit: () => ({ get: async () => ({ forEach: (fn) => Object.entries(members).filter(([, m]) => m.entityId === v).forEach(([id, m]) => fn({ id, data: () => m })) }) }),
      get: async () => ({ forEach: (fn) => Object.values(contracts).filter((c) => c.entityId === v).forEach((c) => fn({ data: () => c })) }),
    }),
  }),
};
const ids = async (u) => { const s = await assignedTrainIds(u, database); return s && [...s].sort(); };

describe('visibleTrainFilter', () => {
  const trains = [
    { uid: 't1', createdBy: 'other' }, { uid: 'tNew', createdBy: 'u2' },
    { uid: 'tForeign', createdBy: 'u9' }, { uid: 't4', createdBy: 'x' },
  ];
  it('shows contract trains plus trains created by anyone in the same company', async () => {
    const f = await visibleTrainFilter({ uid: 'u1', userType: 'contractor', role: 'Contractor Master', entityId: 'e1' }, database);
    expect(trains.filter(f).map((t) => t.uid)).toEqual(['t1', 'tNew']);
  });
  it('does not filter railway users or contractor accounts with no entity and no assigned trains', async () => {
    expect(await visibleTrainFilter({ userType: 'railway', role: 'Railway Admin', entityId: 'e1' }, database)).toBeNull();
    expect(await visibleTrainFilter({ userType: 'contractor', role: 'Contractor Admin' }, database)).toBeNull();
  });
});

describe('assignedTrainIds', () => {
  it('a Contractor Admin gets the trains of their own contract', async () => {
    expect(await ids({ userType: 'contractor', role: 'Contractor Admin', contractId: 'c1' })).toEqual(['t1', 't2']);
  });
  it('a Contractor Master gets the trains of their company active OBHS contracts only', async () => {
    expect(await ids({ userType: 'contractor', role: 'CONTRACTOR_MASTER', entityId: 'e1' })).toEqual(['t1', 't2', 't3']);
  });
  it('adds trains stored on the user itself', async () => {
    expect(await ids({ userType: 'contractor', role: 'Contractor Admin', contractId: 'c1', trainIds: ['t5'] })).toEqual(['t1', 't2', 't5']);
  });
  it('returns null (no filtering) for other roles, railway users and legacy accounts with nothing to go on', async () => {
    expect(await ids({ userType: 'railway', role: 'Railway Admin', entityId: 'e1' })).toBeNull();
    expect(await ids({ userType: 'contractor', role: 'Contractor Supervisor', contractId: 'c1' })).toBeNull();
    expect(await ids({ userType: 'contractor', role: 'Contractor Admin' })).toBeNull();
  });
});
