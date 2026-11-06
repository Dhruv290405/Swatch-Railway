import { db } from '../database/index.js';

const norm = (r) => String(r || '').trim().toLowerCase().replace(/[_\s]+/g, ' ');
const isActive = (s) => !s || String(s).toLowerCase() === 'active';

/**
 * Train ids a contractor-side Master/Admin is assigned to: the trains on their own contract (Admin) or on
 * their company's active OBHS contracts (Master), plus any trains stored directly on the user.
 * Returns null when nothing can be determined, so legacy accounts keep their current list.
 */
export async function assignedTrainIds(user, database = db) {
  if (!user || String(user.userType || '').toLowerCase() !== 'contractor') return null;
  const role = norm(user.role);
  if (role !== 'contractor master' && role !== 'contractor admin') return null;

  const ids = new Set();
  if (user.trainId) ids.add(user.trainId);
  (Array.isArray(user.trainIds) ? user.trainIds : []).forEach((t) => t && ids.add(t));

  const addFrom = (c) => {
    if (!c || !isActive(c.status)) return;
    if (c.contractType && c.contractType !== 'obhs') return;
    (Array.isArray(c.trainIds) ? c.trainIds : []).forEach((t) => t && ids.add(t));
  };

  try {
    if (user.contractId) {
      const doc = await database.collection('contracts').doc(user.contractId).get();
      if (doc.exists) addFrom(doc.data());
    } else if (user.entityId) {
      const snap = await database.collection('contracts').where('entityId', '==', user.entityId).get();
      snap.forEach((d) => addFrom(d.data()));
    }
  } catch (_) { /* fall through with whatever was found */ }

  return ids.size > 0 ? ids : null;
}

/** uids of the user and everyone else in their company, i.e. who may have created trains for the entity. */
export async function entityMemberIds(user, database = db) {
  const ids = new Set(user?.uid ? [user.uid] : []);
  if (!user?.entityId) return ids;
  try {
    const snap = await database.collection('users').where('entityId', '==', user.entityId).limit(500).get();
    snap.forEach((d) => ids.add(d.id));
  } catch (_) { /* keep what we have */ }
  return ids;
}

/**
 * The trains a Contractor Master/Admin may see in the train list: trains on their contracts plus trains
 * created by their company. Returns null (no filtering) for other roles and for accounts that have
 * neither an entity nor any assigned train.
 */
export async function visibleTrainFilter(user, database = db) {
  if (!user || String(user.userType || '').toLowerCase() !== 'contractor') return null;
  const role = norm(user.role);
  if (role !== 'contractor master' && role !== 'contractor admin') return null;
  const assigned = await assignedTrainIds(user, database);
  if (!assigned && !user.entityId) return null;
  const members = await entityMemberIds(user, database);
  return (train) => (assigned?.has(train.uid)) || members.has(train.createdBy);
}
