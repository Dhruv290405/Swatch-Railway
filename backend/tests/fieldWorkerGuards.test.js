import { describe, it, expect } from 'vitest';
import { forbidFieldWorkers, requireSelfForFieldWorkers } from '../src/middleware/authorization.js';

const run = (mw, user, params = {}) => {
  let called = false;
  mw({ user, params }, {}, () => { called = true; });
  return called;
};

describe('forbidFieldWorkers', () => {
  for (const role of ['JANITOR', 'ATTENDANT', 'WORKER', 'RAILWAY_WORKER', 'PASSENGER', 'Janitor']) {
    it(`blocks ${role}`, () => {
      expect(() => run(forbidFieldWorkers, { role })).toThrow(/Supervisory role required/);
    });
  }
  for (const role of ['SUPER_ADMIN', 'COMPANY_MASTER', 'RAILWAY_ADMIN', 'RAILWAY_SUPERVISOR',
    'CONTRACTOR_ADMIN', 'CONTRACTOR_SUPERVISOR', 'CTS', 'Contractor Supervisor']) {
    it(`allows ${role}`, () => {
      expect(run(forbidFieldWorkers, { role })).toBe(true);
    });
  }
});

describe('requireSelfForFieldWorkers', () => {
  const mw = requireSelfForFieldWorkers('workerId');
  it('lets a field worker read their own record', () => {
    expect(run(mw, { role: 'JANITOR', uid: 'u1' }, { workerId: 'u1' })).toBe(true);
  });
  it('blocks a field worker reading another record', () => {
    expect(() => run(mw, { role: 'JANITOR', uid: 'u1' }, { workerId: 'u2' })).toThrow(/own records/);
  });
  it('does not restrict supervisory roles', () => {
    expect(run(mw, { role: 'CONTRACTOR_SUPERVISOR', uid: 'u1' }, { workerId: 'u2' })).toBe(true);
  });
  it('passes legacy tokens without a uid', () => {
    expect(run(mw, { role: 'WORKER' }, { workerId: 'u2' })).toBe(true);
  });
});
