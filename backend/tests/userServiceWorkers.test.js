import { describe, it, expect, vi } from 'vitest';

const docs = [
  { id: 'w1', data: () => ({ role: 'JANITOR', status: 'APPROVED', password: 'plain-secret', entityId: 'ent1', division: 'DELHI', fullName: 'A' }) },
  { id: 'w2', data: () => ({ role: 'ATTENDANT', status: 'APPROVED', password: '$2a$hash', entityId: 'ent2', division: 'DELHI', fullName: 'B' }) },
  { id: 'w3', data: () => ({ role: 'JANITOR', status: 'PENDING', password: 'legacy', division: 'DELHI', fullName: 'C' }) }, // legacy: no entityId
  { id: 'a1', data: () => ({ role: 'CONTRACTOR_ADMIN', status: 'APPROVED', password: 'x', entityId: 'ent1', division: 'DELHI' }) }, // not a worker
];
const snapshot = { empty: false, size: docs.length, forEach: (fn) => docs.forEach(fn) };
const query = { where: () => query, limit: () => query, get: async () => snapshot };

vi.mock('../src/database/index.js', () => ({
  db: { collection: () => query },
  admin: { firestore: { FieldPath: { documentId: () => 'id' } } },
}));

const { default: svc } = await import('../src/services/userService.js').then((m) => ({ default: m.userService || m.default }));

describe('getRailwayWorkers', () => {
  it('never returns the password field', async () => {
    const res = await svc.getRailwayWorkers({ role: 'SUPER_ADMIN' }, {});
    expect(res.workers.length).toBeGreaterThan(0);
    for (const w of res.workers) expect(w).not.toHaveProperty('password');
  });

  it("limits a contractor caller to their own company's workers (legacy workers kept)", async () => {
    const res = await svc.getRailwayWorkers(
      { role: 'CONTRACTOR_ADMIN', userType: 'contractor', entityId: 'ent1', division: 'DELHI' }, {},
    );
    expect(res.workers.map((w) => w.uid).sort()).toEqual(['w1', 'w3']);
  });

  it('does not scope railway callers by company', async () => {
    const res = await svc.getRailwayWorkers({ role: 'RAILWAY_ADMIN', userType: 'railway', zone: 'NR' }, {});
    expect(res.workers.map((w) => w.uid).sort()).toEqual(['w1', 'w2', 'w3']);
  });
});
