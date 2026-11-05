import { describe, it, expect } from 'vitest';
import { resolveContractType, backfillContractType } from '../src/utils/contractTypeResolver.js';

const dbWith = (contracts) => ({
  collection: () => ({
    doc: (id) => ({ get: async () => ({ exists: !!contracts[id], data: () => contracts[id] }) }),
  }),
});

describe('resolveContractType', () => {
  it('keeps a stored value', async () => {
    expect(await resolveContractType({ userType: 'contractor', contractType: 'obhs' }, dbWith({}))).toBe('obhs');
  });
  it("uses the user's contract when the stored value is empty", async () => {
    const db = dbWith({ c1: { contractType: 'station_cleaning' } });
    expect(await resolveContractType({ userType: 'contractor', contractId: 'c1' }, db)).toBe('station_cleaning');
  });
  it('falls back to domain, then to station assignment', async () => {
    expect(await resolveContractType({ userType: 'contractor', domain: 'mcc' }, dbWith({}))).toBe('mcc');
    expect(await resolveContractType({ userType: 'contractor', stations: ['s1'] }, dbWith({}))).toBe('station_cleaning');
    expect(await resolveContractType({ userType: 'contractor', stationId: 's1' }, dbWith({}))).toBe('station_cleaning');
  });
  it('does not guess for railway users or for admins/masters with no signal', async () => {
    expect(await resolveContractType({ userType: 'railway', stations: ['s1'] }, dbWith({}))).toBeNull();
    expect(await resolveContractType({ userType: 'contractor', role: 'CONTRACTOR_ADMIN' }, dbWith({}))).toBeNull();
    expect(await resolveContractType({ userType: 'contractor' }, dbWith({}))).toBeNull();
  });
  it('a Contractor Supervisor defaults to station cleaning, unless tied to a train (OBHS)', async () => {
    expect(await resolveContractType({ userType: 'contractor', role: 'Contractor Supervisor' }, dbWith({}))).toBe('station_cleaning');
    expect(await resolveContractType({ userType: 'contractor', role: 'CONTRACTOR_SUPERVISOR', trainId: 't1' }, dbWith({}))).toBe('obhs');
    expect(await resolveContractType({ userType: 'contractor', role: 'CONTRACTOR_SUPERVISOR', trainIds: ['t1'], stations: ['s1'] }, dbWith({}))).toBe('station_cleaning');
  });
});

describe('backfillContractType', () => {
  it('fills the response object and never overwrites an existing value', async () => {
    const a = await backfillContractType({ userType: 'contractor', stations: ['s1'] }, dbWith({}));
    expect(a.contractType).toBe('station_cleaning');
    const b = await backfillContractType({ userType: 'contractor', contractType: 'obhs', stations: ['s1'] }, dbWith({}));
    expect(b.contractType).toBe('obhs');
  });
});
