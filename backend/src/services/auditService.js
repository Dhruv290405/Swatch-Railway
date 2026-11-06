import { db, admin } from '../database/index.js';
import { NotFoundError, ValidationError, ForbiddenError } from '../errors/index.js';
import logger from '../logger/index.js';

const normRole = (r) => String(r || '').trim().toLowerCase().replace(/[_\s]+/g, ' ');
const sameText = (a, b) => String(a).trim().toLowerCase() === String(b).trim().toLowerCase();

/** What a viewer may see: null = everything, otherwise the location fields to match. */
export function auditScopeFor(user) {
  if (!user) return null;
  const role = normRole(user.role);
  if (role === 'super admin' || role === 'company master') return null;
  const scope = {};
  if (role === 'railway master') {
    if (user.zone) scope.zone = user.zone;
  } else {
    if (user.division) scope.division = user.division;
    if (user.zone) scope.zone = user.zone;
  }
  if (String(user.userType || '').toLowerCase() === 'contractor' && user.entityId) scope.entityId = user.entityId;
  return Object.keys(scope).length ? scope : null;
}

/** True unless the actor has location data that contradicts the scope. */
export function actorInScope(actor, scope) {
  if (!actor) return true;
  for (const key of Object.keys(scope)) {
    if (actor[key] && !sameText(actor[key], scope[key])) return false;
  }
  return true;
}

async function filterLogsByScope(logs, scope, database = db) {
  const actorIds = [...new Set(logs.map((l) => l.actorId || l.userId).filter((id) => id && id !== 'anonymous'))];
  const actors = new Map();
  await Promise.all(actorIds.map(async (id) => {
    try {
      const doc = await database.collection('users').doc(id).get();
      if (doc.exists) actors.set(id, doc.data());
    } catch (_) { /* unknown actor: keep the log */ }
  }));
  return logs.filter((l) => actorInScope(actors.get(l.actorId || l.userId), scope));
}

class AuditService {
  async getAuditLogs(filters = {}) {
    const { action, actorId, targetId, startDate, endDate, limit = 50, offset = 0 } = filters;
    const maxLimit = Math.min(parseInt(limit), 200);

    let query = db.collection('audit_logs');
    if (action) {
      // A filtered audit query with orderBy(timestamp) requires a composite
      // Firestore index. Filter first and sort the small result set in memory.
      query = query.where('action', '==', action);
    } else {
      query = query.orderBy('timestamp', 'desc');
    }
    
    // Some services log 'userId', others log 'actorId'
    if (actorId && !filters.userId) query = query.where('actorId', '==', actorId);
    else if (filters.userId && !actorId) query = query.where('userId', '==', filters.userId);
    else if (actorId && filters.userId) {
      // If both are provided and they are the same (like in our route)
      // Since Firestore doesn't support OR natively well on different fields in a single inequality,
      // we'll just not use a where clause here and filter in memory if needed, or assume 'userId' or 'actorId'
      // Actually we'll just filter in memory for the actorId/userId if both could be present.
    }
    
    if (targetId) query = query.where('targetId', '==', targetId);

    const snapshot = await query.limit(maxLimit).get();
    const logs = [];
    snapshot.forEach(doc => {
      const data = doc.data();
      const ts = data.timestamp?.toDate?.()?.toISOString() || data.timestamp || data.createdAt?.toDate?.()?.toISOString() || data.createdAt || null;
      
      // Memory filter if actorId/userId was passed but we couldn't query it directly due to OR condition
      if ((actorId && filters.userId) && (data.actorId !== actorId && data.userId !== filters.userId)) {
        return; // skip this log
      }

      logs.push({
        ...data,
        timestamp: ts,
        createdAt: ts,
        type: data.targetType || data.type || data.action || 'Activity'
      });
    });

    if (action) {
      const toMillis = value => {
        if (value && typeof value.toDate === 'function') return value.toDate().getTime();
        const parsed = value == null ? NaN : new Date(value).getTime();
        return Number.isFinite(parsed) ? parsed : 0;
      };
      logs.sort((a, b) =>
        toMillis(b.timestamp || b.createdAt) - toMillis(a.timestamp || a.createdAt),
      );
    }

    return { count: logs.length, logs };
  }

  /**
   * Audit logs limited to the viewer's location. A log is kept when the person who did it works in the
   * same location as the viewer: same zone for a Railway Master, same division for other railway and
   * contractor roles, and the same company for contractor roles. Logs whose actor or location is unknown
   * (older records) are kept. Super Admin / Company Master see everything.
   */
  async getAuditLogsForUser(user, filters = {}) {
    const scope = auditScopeFor(user);
    if (!scope) return this.getAuditLogs(filters);

    const wanted = Math.min(parseInt(filters.limit) || 50, 200);
    const result = await this.getAuditLogs({ ...filters, limit: 200 });
    const kept = await filterLogsByScope(result.logs, scope);
    const logs = kept.slice(0, wanted);
    return { count: logs.length, logs };
  }

  async getAuditStats(filters = {}) {
    const snapshot = await db.collection('audit_logs').limit(200).get();
    const stats = {};
    snapshot.forEach(doc => {
      const d = doc.data();
      stats[d.action] = (stats[d.action] || 0) + 1;
    });

    let total = 0;
    for (const key of Object.keys(stats)) {
      total += stats[key];
    }

    return { stats, total };
  }

  async getStationAuditLogs(stationId, filters = {}, user = null) {
    if (!stationId) throw new ValidationError('stationId is required');
    const { action, limit = 100 } = filters;
    const maxLimit = Math.min(parseInt(limit) || 100, 200);

    const stationDoc = await db.collection('stations').doc(stationId).get();
    const scope = auditScopeFor(user);
    const { entityId: _ignored, ...locationScope } = scope || {};
    if (scope && stationDoc.exists && !actorInScope(stationDoc.data(), locationScope)) {
      throw new ForbiddenError('This station is outside your location');
    }
    const stationName = stationDoc.exists ? (stationDoc.data().stationName || '') : '';

    const contractSnap = await db.collection('contracts').where('stationIds', 'array-contains', stationId).limit(50).get();
    const contractIds = new Set();
    const contractNumbers = new Set();
    contractSnap.forEach(doc => {
      const d = doc.data();
      contractIds.add(doc.id);
      if (d.contractNumber) contractNumbers.add(String(d.contractNumber).toLowerCase());
    });

    let q = db.collection('audit_logs').orderBy('createdAt', 'desc').limit(maxLimit);
    if (action) q = q.where('action', '==', action);
    const snapshot = await q.get();
    if (snapshot.empty) return { count: 0, logs: [], station: stationName };

    const nameKey = stationName.toLowerCase();
    const stationIdKey = stationId.toLowerCase();

    const logs = [];
    for (const doc of snapshot.docs) {
      const data = doc.data();
      const details = (data.details || '').toLowerCase();
      const ts = data.timestamp?.toDate?.()?.toISOString() || data.timestamp || data.createdAt?.toDate?.()?.toISOString() || data.createdAt || null;

      // 1) Log directly targets the station
      let matched = data.targetId ? data.targetId === stationId : false;

      // 2) Log details mention the station name / id / contract
      if (!matched) {
        matched =
          (nameKey && nameKey !== 'station' && details.includes(nameKey)) ||
          details.includes(stationIdKey) ||
          [...contractNumbers].some(num => num && details.includes(num)) ||
          [...contractIds].some(cid => cid && details.includes(cid));
      }

      // 3) Trace the logged entity back to the station via its own document
      if (!matched && data.targetId && data.targetType) {
        try {
          const tDoc = await db.collection(data.targetType).doc(data.targetId).get();
          if (tDoc.exists) {
            const t = tDoc.data();
            matched =
              (t.stationId && t.stationId === stationId) ||
              (t.stationIds && Array.isArray(t.stationIds) && t.stationIds.includes(stationId)) ||
              (t.contractId && contractIds.has(t.contractId)) ||
              (t.contractUid && contractIds.has(t.contractUid));
          }
        } catch (_) {
          // collection name may differ from targetType; skip trace
        }
      }

      if (!matched) continue;
      logs.push({
        uid: doc.id,
        ...data,
        timestamp: ts,
        createdAt: ts,
        type: data.targetType || data.type || data.action || 'Activity',
      });
    }

    return { count: logs.length, logs, station: stationName };
  }

  async getEvidenceAudit(filters = {}) {
    const { evidenceId, action, userId, limit = 50 } = filters;
    let query = db.collection('audit_evidence').orderBy('timestamp', 'desc').limit(parseInt(limit));

    if (evidenceId) query = query.where('evidenceId', '==', evidenceId);
    if (action) query = query.where('action', '==', action);
    if (userId) query = query.where('userId', '==', userId);

    const snap = await query.get();
    const logs = snap.docs.map(d => ({ id: d.id, ...d.data() }));

    return { success: true, count: logs.length, logs };
  }

  async logAudit(action, actorId, actorName, targetId, targetType, details = null, changes = null) {
    const ref = db.collection('audit_logs').doc();
    const entry = {
      uid: ref.id,
      action,
      actorId,
      actorName,
      targetId,
      targetType,
      details,
      changes,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await ref.set(entry);
    logger.info('AuditService', `Audit log: ${action}`, { actorId, targetId, targetType });
    return { uid: ref.id, ...entry, createdAt: new Date().toISOString() };
  }
}

export const auditService = new AuditService();
