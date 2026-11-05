import { db } from '../database/index.js';
import { NotFoundError, ValidationError, ConflictError } from '../errors/index.js';

class StationService {
  async getStations(query = {}, user) {
    const { zone, division, category, active, limit, entityId } = query;
    let q = db.collection('stations');

    const contractorRoles = ['CONTRACTOR_ADMIN', 'CONTRACTOR_MASTER', 'CONTRACTOR_SUPERVISOR'];
    const userRole = (user?.role || '').toUpperCase().replace(/\s+/g, '_');

    if (entityId && !contractorRoles.includes(userRole)) {
      const mappings = await db.collection('stationContractorMappings')
        .where('contractorId', '==', entityId)
        .where('status', '==', 'active')
        .get();
      const stationIds = mappings.docs.map(d => d.data().stationId).filter(Boolean);
      if (stationIds.length > 0) {
        q = q.where('uid', 'in', stationIds);
      } else if (division) {
        q = q.where('division', '==', division);
      } else {
        return { count: 0, stations: [] };
      }
    } else if (contractorRoles.includes(userRole) && user?.entityId) {
      // OBHS contractors should not see stations
      if (user.domain === 'obhs') {
        return { count: 0, stations: [] };
      }
      const mappings = await db.collection('stationContractorMappings')
        .where('contractorId', '==', user.entityId)
        .where('status', '==', 'active')
        .get();
      let stationIds = mappings.docs.map(d => d.data().stationId).filter(Boolean);
      if (stationIds.length === 0 && Array.isArray(user.stations) && user.stations.length > 0) {
        stationIds = user.stations;
      }
      if (stationIds.length > 0) {
        q = q.where('uid', 'in', stationIds);
      } else if (division || user.division) {
        q = q.where('division', '==', division || user.division);
      } else {
        return { count: 0, stations: [] };
      }
    } else if (userRole === 'RAILWAY_SUPERVISOR' && user?.division) {
      q = q.where('division', '==', user.division);
    }

    if (division) q = q.where('division', '==', division);
    if (zone) q = q.where('zone', '==', zone);
    if (category) q = q.where('category', '==', category);
    if (active !== undefined) q = q.where('active', '==', active === 'true');

    const pageSize = Math.min(200, Math.max(1, parseInt(limit) || 200));
    const snapped = await q.limit(pageSize).get();

    const stations = [];
    snapped.forEach(doc => stations.push({ id: doc.id, ...doc.data() }));
    stations.sort((a, b) => (a.stationName || '').localeCompare(b.stationName || ''));

    return { count: stations.length, stations };
  }

  async getStationById(uid) {
    const doc = await db.collection('stations').doc(uid).get();
    if (!doc.exists) throw new NotFoundError('Station not found');
    return { id: doc.id, ...doc.data() };
  }

  async searchStations(queryStr) {
    if (!queryStr || queryStr.length < 2) throw new ValidationError('Search query must be at least 2 characters');
    const keyword = queryStr.toLowerCase();

    const keywordUpper = keyword.toUpperCase();
    const keywordLower = keyword.toLowerCase();

    const [codeSnap, namePrefixSnap, fullSnap] = await Promise.all([
      db.collection('stations').where('stationCode', '>=', keywordUpper).where('stationCode', '<=', keywordUpper + '\uf8ff').limit(20).get(),
      db.collection('stations').where('stationName', '>=', keyword).where('stationName', '<=', keyword + '\uf8ff').limit(20).get(),
      db.collection('stations').limit(200).get(),
    ]);

    const stationsMap = new Map();
    codeSnap.forEach(doc => stationsMap.set(doc.id, { id: doc.id, ...doc.data() }));
    namePrefixSnap.forEach(doc => {
      if (!stationsMap.has(doc.id)) stationsMap.set(doc.id, { id: doc.id, ...doc.data() });
    });
    fullSnap.forEach(doc => {
      if (!stationsMap.has(doc.id) && (doc.data().stationName || '').toLowerCase().includes(keywordLower)) {
        stationsMap.set(doc.id, { id: doc.id, ...doc.data() });
      }
    });

    const stations = Array.from(stationsMap.values()).slice(0, 20);
    return { count: stations.length, stations };
  }

  async getStationsByDivision(division) {
    if (!division) throw new ValidationError('Division is required');
    const snapshot = await db.collection('stations').where('division', '==', division).orderBy('stationName', 'asc').limit(200).get();
    const stations = [];
    snapshot.forEach(doc => stations.push({ id: doc.id, ...doc.data() }));
    return { count: stations.length, stations };
  }

  async createStation(userData, body) {
    const { stationCode, stationName, zone, division, category, stationType, active, latitude, longitude, address } = body;
    if (!stationCode || !stationName || !zone || !division) {
      throw new ValidationError('stationCode, stationName, zone, division are required');
    }
    const existing = await db.collection('stations').where('stationCode', '==', stationCode).limit(1).get();
    if (!existing.empty) throw new ConflictError(`Station with code ${stationCode} already exists`);
    const ref = db.collection('stations').doc();
    const data = {
      uid: ref.id, stationCode, stationName, zone, division,
      category: category || 'c', stationType: stationType || 'regular',
      active: active !== false,
      latitude: latitude || 0, longitude: longitude || 0, address: address || '',
      createdBy: userData.uid,
      createdAt: new Date().toISOString(), updatedAt: new Date().toISOString()
    };
    await ref.set(data);

    // A contractor-side creator (e.g. Contractor Master) only sees stations mapped to their company, so
    // register the mapping or the station they just created would not appear in their own list.
    if (String(userData.userType || '').toLowerCase() === 'contractor' && userData.entityId) {
      const mapRef = db.collection('stationContractorMappings').doc();
      await mapRef.set({
        uid: mapRef.id, stationId: ref.id, contractorId: userData.entityId, contractId: null,
        status: 'active', source: 'created-by-master', createdBy: userData.uid,
        createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(),
      });
    }
    return { message: 'Station created', uid: ref.id, station: data };
  }

  async updateStation(uid, userData, body) {
    const ref = db.collection('stations').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Station not found');
    const updates = {};
    const allowedStationFields = ['stationName', 'category', 'stationType', 'active', 'latitude', 'longitude', 'address', 'zone', 'division'];
    for (const key of allowedStationFields) {
      if (body[key] !== undefined) updates[key] = body[key];
    }
    updates.updatedAt = new Date().toISOString();
    updates.updatedBy = userData.uid;
    await ref.update(updates);
    return { message: 'Station updated' };
  }

  async deleteStation(uid) {
    const ref = db.collection('stations').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Station not found');
    await ref.update({ active: false, deletedAt: new Date().toISOString() });
    return { message: 'Station deactivated' };
  }
}

export const stationService = new StationService();
