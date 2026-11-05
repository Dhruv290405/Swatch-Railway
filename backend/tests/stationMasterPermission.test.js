import { describe, it, expect } from 'vitest';
import { PERMISSIONS, ROLE_PERMISSIONS } from '../src/permissions/roles.js';
import { requirePermission, requireAnyPermission } from '../src/middleware/authorization.js';

const has = (role, perm) => (ROLE_PERMISSIONS[role] || []).includes(perm);

describe('master roles can register stations', () => {
  for (const role of ['RAILWAY_MASTER', 'CONTRACTOR_MASTER']) {
    it(`${role} can create/edit a station but not manage (delete) stations`, () => {
      expect(has(role, PERMISSIONS.CREATE_STATION)).toBe(true);
      expect(has(role, PERMISSIONS.MANAGE_STATIONS)).toBe(false);
      expect(has(role, PERMISSIONS.VIEW_STATIONS)).toBe(true);
    });
  }
  it('existing roles keep their rights', () => {
    for (const role of ['COMPANY_MASTER', 'ADMIN', 'RAILWAY_ADMIN']) {
      expect(has(role, PERMISSIONS.MANAGE_STATIONS)).toBe(true);
    }
  });
  it('supervisors, workers and passengers cannot create stations', () => {
    for (const role of ['CONTRACTOR_SUPERVISOR', 'CTS', 'JANITOR', 'ATTENDANT', 'WORKER', 'PASSENGER', 'RAILWAY_SUPERVISOR']) {
      expect(has(role, PERMISSIONS.CREATE_STATION)).toBe(false);
      expect(has(role, PERMISSIONS.MANAGE_STATIONS)).toBe(false);
    }
  });
});

const run = (mw, role) => {
  let error = null;
  mw({ user: { role } }, {}, (e) => { error = e || null; });
  return error;
};

describe('station route guards', () => {
  const createGuard = requireAnyPermission(PERMISSIONS.MANAGE_STATIONS, PERMISSIONS.CREATE_STATION);
  const deleteGuard = requirePermission(PERMISSIONS.MANAGE_STATIONS);
  const call = (mw, role) => { try { return run(mw, role); } catch (e) { return e; } };

  it('create passes for masters and is refused for a supervisor', () => {
    expect(call(createGuard, 'Contractor Master')).toBeNull();
    expect(call(createGuard, 'RAILWAY_MASTER')).toBeNull();
    expect(call(createGuard, 'CONTRACTOR_SUPERVISOR')).toBeTruthy();
  });
  it('delete is still refused for masters that only have CREATE_STATION', () => {
    expect(call(deleteGuard, 'RAILWAY_MASTER')).toBeTruthy();
    expect(call(deleteGuard, 'CONTRACTOR_MASTER')).toBeTruthy();
    expect(call(deleteGuard, 'COMPANY_MASTER')).toBeNull();
  });
});
