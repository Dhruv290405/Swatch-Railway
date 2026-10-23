import { describe, expect, it } from 'vitest';
import { PERMISSIONS, ROLE_PERMISSIONS } from '../src/permissions/roles.js';

describe('user delete permissions', () => {
  it('defines a distinct delete_user permission', () => {
    expect(PERMISSIONS.DELETE_USER).toBe('delete_user');
  });

  it.each([
    'SUPER_ADMIN',
    'COMPANY_MASTER',
    'RAILWAY_MASTER',
    'ADMIN',
    'RAILWAY_ADMIN',
    'CONTRACTOR_MASTER',
    'CONTRACTOR_ADMIN',
  ])('%s may delete users', role => {
    expect(ROLE_PERMISSIONS[role]).toContain(PERMISSIONS.DELETE_USER);
  });

  it.each([
    'RAILWAY_SUPERVISOR',
    'CONTRACTOR_SUPERVISOR',
    'CTS',
    'WORKER',
    'JANITOR',
    'ATTENDANT',
    'PASSENGER',
  ])('%s may not delete users', role => {
    expect(ROLE_PERMISSIONS[role]).not.toContain(PERMISSIONS.DELETE_USER);
  });
});
