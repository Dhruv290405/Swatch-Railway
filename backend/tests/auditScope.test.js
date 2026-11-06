import { describe, it, expect, vi } from 'vitest';

const users = {
  a1: { division: 'DELHI', zone: 'NR', entityId: 'e1' },
  a2: { division: 'MUMBAI', zone: 'WR', entityId: 'e2' },
  a3: { division: 'LUCKNOW', zone: 'NR' },
  legacy: {},
};
const logsRows = [
  { uid: 'l1', actorId: 'a1', action: 'X', timestamp: '2026-01-04T00:00:00Z' },
  { uid: 'l2', actorId: 'a2', action: 'X', timestamp: '2026-01-03T00:00:00Z' },
  { uid: 'l3', actorId: 'a3', action: 'X', timestamp: '2026-01-02T00:00:00Z' },
  { uid: 'l4', actorId: 'legacy', action: 'X', timestamp: '2026-01-01T00:00:00Z' },
  { uid: 'l5', actorId: 'ghost', action: 'X', timestamp: '2025-12-31T00:00:00Z' },
];
const stations = { st_del: { division: 'DELHI', zone: 'NR', stationName: 'Delhi' }, st_mum: { division: 'MUMBAI', zone: 'WR', stationName: 'Mumbai' } };

vi.mock('../src/database/index.js', () => {
  const doc = (table) => (id) => ({ get: async () => ({ exists: !!table[id], id, data: () => table[id] }) });
  const auditQuery = { orderBy: () => auditQuery, where: () => auditQuery, limit: () => auditQuery, get: async () => ({ empty: false, docs: [], forEach: (fn) => logsRows.forEach((r) => fn({ id: r.uid, data: () => r })) }) };
  return {
    db: {
      collection: (name) => {
        if (name === 'users') return { doc: doc(users) };
        if (name === 'stations') return { doc: doc(stations) };
        if (name === 'contracts') return { where: () => ({ limit: () => ({ get: async () => ({ forEach: () => {} }) }) }) };
        return auditQuery;
      },
    },
    admin: { firestore: { FieldValue: { serverTimestamp: () => 'ts' } } },
  };
});

const { auditService, auditScopeFor } = await import('../src/services/auditService.js');
const ids = async (user) => (await auditService.getAuditLogsForUser(user, {})).logs.map((l) => l.uid);

describe('audit log location scope', () => {
  it('super admin and company master are unrestricted', () => {
    expect(auditScopeFor({ role: 'SUPER_ADMIN', division: 'DELHI' })).toBeNull();
    expect(auditScopeFor({ role: 'Company Master' })).toBeNull();
  });
  it('a railway admin only sees logs from their own division (legacy / unknown actors kept)', async () => {
    expect(await ids({ role: 'RAILWAY_ADMIN', userType: 'railway', division: 'Delhi', zone: 'NR' })).toEqual(['l1', 'l4', 'l5']);
  });
  it('a railway master sees their whole zone', async () => {
    expect(await ids({ role: 'Railway Master', userType: 'railway', division: 'DELHI', zone: 'NR' })).toEqual(['l1', 'l3', 'l4', 'l5']);
  });
  it('a contractor user is limited to their company and division', async () => {
    expect(await ids({ role: 'Contractor Admin', userType: 'contractor', division: 'DELHI', zone: 'NR', entityId: 'e1' })).toEqual(['l1', 'l4', 'l5']);
  });
  it('a user with no location data keeps the old behaviour', async () => {
    expect(await ids({ role: 'Railway Admin', userType: 'railway' })).toEqual(['l1', 'l2', 'l3', 'l4', 'l5']);
  });
  it('station audit logs of another location are refused', async () => {
    await expect(auditService.getStationAuditLogs('st_mum', {}, { role: 'Railway Admin', division: 'DELHI', zone: 'NR' })).rejects.toThrow(/outside your location/);
    await expect(auditService.getStationAuditLogs('st_del', {}, { role: 'Railway Admin', division: 'DELHI', zone: 'NR' })).resolves.toBeDefined();
  });
});
