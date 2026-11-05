import { db } from '../database/index.js';

const KNOWN = ['station_cleaning', 'obhs', 'mcc'];

/**
 * Works out which module a contractor-side user belongs to when the stored `contractType` is empty
 * (older accounts). The app uses this value to decide whether to show Station Cleaning or OBHS, and an
 * empty value makes it fall back to OBHS content. Precedence: stored value, the user's contract,
 * the user's domain, then station assignment (a user assigned stations is a station-cleaning user).
 */
export async function resolveContractType(user, database = db) {
  if (!user) return null;
  if (user.contractType) return user.contractType;
  if (String(user.userType || '').toLowerCase() !== 'contractor') return null;

  if (user.contractId) {
    try {
      const doc = await database.collection('contracts').doc(user.contractId).get();
      const t = doc.exists ? doc.data().contractType : null;
      if (KNOWN.includes(t)) return t;
    } catch (_) { /* fall through to the other signals */ }
  }
  if (KNOWN.includes(user.domain)) return user.domain;
  const hasStation = !!user.stationId || (Array.isArray(user.stations) && user.stations.length > 0);
  const hasTrain = !!user.trainId || (Array.isArray(user.trainIds) && user.trainIds.length > 0);
  if (hasStation) return 'station_cleaning';
  if (hasTrain) return 'obhs';
  // A Contractor Supervisor is the station-cleaning supervisor unless they are tied to a train (OBHS).
  if (String(user.role || '').toUpperCase().replace(/\s+/g, '_') === 'CONTRACTOR_SUPERVISOR') return 'station_cleaning';
  return null;
}

/** Fills `user.contractType` on a login response object (not persisted). */
export async function backfillContractType(user, database = db) {
  try {
    const resolved = await resolveContractType(user, database);
    if (resolved && !user.contractType) user.contractType = resolved;
  } catch (_) { /* never block a login on this */ }
  return user;
}
