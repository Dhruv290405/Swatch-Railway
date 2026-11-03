import { describe, it, expect } from 'vitest';
import { runAccessError, filterRunsByEntity, isFieldWorker } from '../src/utils/runAccess.js';

const run = {
  division: 'DELHI',
  entityId: 'ent1',
  coaches: [{ janitorId: 'j1', workerId: 'j1' }, { attendantId: 'a1' }],
};

describe('runAccessError', () => {
  it('lets an assigned janitor / attendant in, blocks an unassigned one', () => {
    expect(runAccessError({ role: 'JANITOR', uid: 'j1' }, run)).toBeNull();
    expect(runAccessError({ role: 'Attendant', uid: 'a1' }, run)).toBeNull();
    expect(runAccessError({ role: 'JANITOR', uid: 'j2' }, run)).toMatch(/not assigned/);
  });

  it('blocks another division but allows legacy users without a division', () => {
    expect(runAccessError({ role: 'RAILWAY_ADMIN', division: 'MUMBAI' }, run)).toMatch(/another division/);
    expect(runAccessError({ role: 'RAILWAY_ADMIN' }, run)).toBeNull();
    expect(runAccessError({ role: 'RAILWAY_ADMIN', division: 'DELHI' }, { ...run, division: undefined })).toBeNull();
  });

  it('blocks a different contractor company only when both sides have an entityId', () => {
    const other = { role: 'CONTRACTOR_ADMIN', userType: 'contractor', division: 'DELHI', entityId: 'ent2' };
    expect(runAccessError(other, run)).toMatch(/another contractor/);
    expect(runAccessError({ ...other, entityId: 'ent1' }, run)).toBeNull();
    expect(runAccessError(other, { ...run, entityId: undefined })).toBeNull(); // legacy run
    expect(runAccessError({ ...other, entityId: undefined }, run)).toBeNull(); // legacy user
  });

  it('never restricts platform-wide roles', () => {
    expect(runAccessError({ role: 'SUPER_ADMIN', division: 'MUMBAI', entityId: 'x', userType: 'contractor' }, run)).toBeNull();
  });
});

describe('filterRunsByEntity', () => {
  const runs = [{ id: 'a', entityId: 'ent1' }, { id: 'b', entityId: 'ent2' }, { id: 'legacy' }];
  it('keeps own and legacy runs for a contractor', () => {
    const out = filterRunsByEntity({ role: 'CONTRACTOR_ADMIN', userType: 'contractor', entityId: 'ent1' }, runs);
    expect(out.map((r) => r.id)).toEqual(['a', 'legacy']);
  });
  it('does not filter railway users or platform roles', () => {
    expect(filterRunsByEntity({ role: 'RAILWAY_ADMIN', userType: 'railway' }, runs)).toHaveLength(3);
    expect(filterRunsByEntity({ role: 'SUPER_ADMIN', userType: 'contractor', entityId: 'ent1' }, runs)).toHaveLength(3);
  });
});

describe('isFieldWorker', () => {
  it('normalises role casing and spacing', () => {
    expect(isFieldWorker({ role: 'Janitor' })).toBe(true);
    expect(isFieldWorker({ role: 'Railway Worker' })).toBe(true);
    expect(isFieldWorker({ role: 'CONTRACTOR_ADMIN' })).toBe(false);
  });
});
