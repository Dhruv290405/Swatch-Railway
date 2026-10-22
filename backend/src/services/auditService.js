import { db, admin } from '../database/index.js';
import { NotFoundError, ValidationError } from '../errors/index.js';
import logger from '../logger/index.js';

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

  async getStationAuditLogs(stationId, filters = {}) {
    if (!stationId) throw new ValidationError('stationId is required');
    const { action, limit = 100 } = filters;
    const maxLimit = Math.min(parseInt(limit) || 100, 200);

    const stationDoc = await db.collection('stations').doc(stationId).get();
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
