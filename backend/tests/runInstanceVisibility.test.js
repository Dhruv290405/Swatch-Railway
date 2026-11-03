import { describe, it, expect, vi, beforeEach } from 'vitest';

const runs = [
  { id: 'r1', division: 'DELHI', coaches: [{ janitorId: 'jan1', workerId: 'jan1' }] },
  { id: 'r2', division: 'DELHI', coaches: [{ janitorId: 'jan2', attendantId: 'att1' }] },
  { id: 'r3', division: 'MUMBAI', coaches: [{ janitorId: 'jan3' }] },
];
const byDivision = vi.fn(async (division) => ({
  success: true,
  data: runs.filter((r) => !division || r.division === division),
}));

vi.mock('../src/database/index.js', () => ({ db: { collection: () => ({ doc: () => ({ get: async () => ({ exists: false }) }) }) } }));
vi.mock('../src/services/runInstanceService.js', () => ({
  runInstanceService: {
    getRunInstancesByDivision: (...a) => byDivision(...a),
    getRunInstancesByZone: vi.fn(),
    getRunInstanceById: async (id) => ({ id, ...runs.find((r) => r.id === id) }),
  },
}));

const { list, getObhsRun } = await import('../src/controllers/runInstanceController.js');

const call = (handler, user, { query = {}, params = {} } = {}) =>
  new Promise((resolve) => {
    const res = {
      statusCode: 200,
      status(c) { this.statusCode = c; return this; },
      json(b) { resolve({ status: this.statusCode, body: b }); },
    };
    handler({ user, query, params }, res, (err) => resolve({ error: err }));
  });

beforeEach(() => byDivision.mockClear());

describe('OBHS run list visibility', () => {
  it('janitor only sees runs assigned to them', async () => {
    const r = await call(list, { role: 'JANITOR', uid: 'jan1', division: 'DELHI' });
    expect(r.body.data.map((x) => x.id)).toEqual(['r1']);
  });
  it('attendant only sees runs assigned to them', async () => {
    const r = await call(list, { role: 'Attendant', uid: 'att1' });
    expect(r.body.data.map((x) => x.id)).toEqual(['r2']);
  });
  it('contractor admin is limited to own division even if another is requested', async () => {
    await call(list, { role: 'CONTRACTOR_ADMIN', uid: 'ca', division: 'DELHI' }, { query: { division: 'MUMBAI' } });
    expect(byDivision).toHaveBeenCalledWith('DELHI', undefined, false);
  });
  it('super admin can choose any division', async () => {
    await call(list, { role: 'SUPER_ADMIN', uid: 'sa' }, { query: { division: 'MUMBAI' } });
    expect(byDivision).toHaveBeenCalledWith('MUMBAI', undefined, true);
  });
  it('legacy admin without division/zone keeps the old (unscoped) view', async () => {
    await call(list, { role: 'RAILWAY_ADMIN', uid: 'ra' });
    expect(byDivision).toHaveBeenCalledWith(null, undefined, true);
  });
});

describe('OBHS single run access', () => {
  it('blocks a janitor from an unassigned run', async () => {
    const r = await call(getObhsRun, { role: 'JANITOR', uid: 'jan1' }, { params: { runId: 'r2' } });
    expect(r.error?.message || '').toMatch(/not assigned/);
  });
  it('allows the assigned janitor', async () => {
    const r = await call(getObhsRun, { role: 'JANITOR', uid: 'jan1' }, { params: { runId: 'r1' } });
    expect(r.body.success).toBe(true);
  });
  it('blocks another division for scoped roles', async () => {
    const r = await call(getObhsRun, { role: 'CONTRACTOR_SUPERVISOR', uid: 'cs', division: 'DELHI' }, { params: { runId: 'r3' } });
    expect(r.error?.message || '').toMatch(/another division/);
  });
});
