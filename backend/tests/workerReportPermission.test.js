import { describe, expect, it } from 'vitest';
import { PERMISSIONS, ROLE_PERMISSIONS } from '../src/permissions/roles.js';

describe('worker report permissions', () => {
  it.each(['WORKER', 'JANITOR', 'ATTENDANT'])(
    '%s may view reports used by worker attendance summaries',
    role => {
      expect(ROLE_PERMISSIONS[role]).toContain(PERMISSIONS.VIEW_REPORTS);
    },
  );
});
