import { db, admin } from '../database/index.js';
import { NotFoundError, ValidationError, ForbiddenError } from '../errors/index.js';
import { paginate } from '../utils/paginate.js';
import { fcmService } from './fcmService.js';
import logger from '../logger/index.js';

function getISTDate(offset = 0) {
  const shifted = new Date(Date.now() + offset * 86400000);
  return shifted.toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' });
}

// Add N days to a plain YYYY-MM-DD date without any local-timezone drift.
function addDaysToDate(yyyymmdd, days) {
  const d = new Date(`${yyyymmdd}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().split('T')[0];
}

class StationCleaningService {

  _resolveStationId(requestedStationId, user) {
    const role = (user?.role || '').toUpperCase();
    if (user?.stationId && role === 'RAILWAY_SUPERVISOR') {
      return user.stationId;
    }
    return requestedStationId;
  }

  _resolveAreaId(requestedAreaId, user) {
    const role = (user?.role || '').toUpperCase();
    return requestedAreaId;
  }

  _isMasterOrAdmin(user) {
    const role = (user?.role || '').toUpperCase();
    return ['SUPER_ADMIN', 'COMPANY_MASTER', 'RAILWAY_MASTER', 'ADMIN'].includes(role);
  }

  _scopeByContract(query, user, stationField = 'stationId') {
    if (this._isMasterOrAdmin(user)) return query;
    const userStations = user?.stations;
    if (userStations && Array.isArray(userStations) && userStations.length > 0) {
      return query.where(stationField, 'in', userStations);
    }
    return query;
  }

  _scopeByDivision(query, user, divisionField = 'division') {
    const role = (user?.role || '').toUpperCase();
    if (this._isMasterOrAdmin(user)) return query;
    if (user?.division) {
      return query.where(divisionField, '==', user.division);
    }
    return query;
  }

  _scopeByArea(query, user, field = 'areaId') {
    return query;
  }

  _scopeByEntity(query, user, entityField = 'entityId') {
    if (user?.userType === 'contractor' && user?.entityId) {
      return query.where(entityField, '==', user.entityId);
    }
    return query;
  }

  _scopeByContractId(query, user, contractField = 'contractId') {
    if (this._isMasterOrAdmin(user)) return query;
    if (user?.contractId) {
      return query.where(contractField, '==', user.contractId);
    }
    return query;
  }

  _verifyStationAccess(task, user) {
    const role = (user?.role || '').toUpperCase();
    const userStationId = user?.stationId;
    if (userStationId && task.stationId && task.stationId !== userStationId) {
      throw new ForbiddenError('You can only access tasks in your assigned station');
    }
  }

  _calcTenderedArea(basicAreaSqFt, frequencyType, frequencyTimes) {
    const area = basicAreaSqFt || 0;
    const times = frequencyTimes || 1;
    switch ((frequencyType || 'daily').toLowerCase()) {
      case 'monthly': return Math.round((area * times) / 30);
      case 'weekly': return Math.round((area * times) / 7);
      case 'daily':
      default: return Math.round(area * times);
    }
  }

  // ─── Area / Work Item flexibility ──────────────────────────────────────────
  // An area record must be able to represent measurement types beyond sq.ft.
  // (count/unit, running ft, as available, not applicable...) and manually
  // editable / custom frequencies, WITHOUT forcing a numeric sqft. This is a
  // configuration concern only — billing logic is untouched and still reads
  // the same basicAreaSqFt / tenderedAreaPerDay / weightage fields.

  _NUMBER_MEASUREMENT_TYPES = new Set([
    'sq_ft', 'sq_meter', 'running_ft', 'count', 'number', 'quantity', 'unit'
  ]);

  _ALL_MEASUREMENT_TYPES = new Set([
    'sq_ft', 'sq_meter', 'running_ft', 'count', 'number', 'quantity', 'unit',
    'as_available', 'not_applicable', 'service', 'service_based', 'item'
  ]);

  _FREQUENCY_UNITS = new Set(['day', 'week', 'fortnight', 'month', 'shift']);

  _toNumberOrNull(v) {
    if (v === null || v === undefined || v === '') return null;
    const n = typeof v === 'number' ? v : parseFloat(String(v).replace(/,/g, '').trim());
    return Number.isFinite(n) ? n : null;
  }

  _toIntOrNull(v) {
    const n = this._toNumberOrNull(v);
    if (n === null) return null;
    return Math.trunc(n);
  }

  _resolveMeasurementType(body, existing) {
    if (body.measurementType && this._ALL_MEASUREMENT_TYPES.has(String(body.measurementType).toLowerCase())) {
      return String(body.measurementType).toLowerCase();
    }
    if (existing && existing.measurementType && this._ALL_MEASUREMENT_TYPES.has(String(existing.measurementType).toLowerCase())) {
      return String(existing.measurementType).toLowerCase();
    }
    // Back-compat: a positive basicAreaSqFt implies sq_ft, otherwise no sqft
    // requirement is assumed ("as available" / not provided).
    const sqft = this._toNumberOrNull(body.basicAreaSqFt);
    return (sqft !== null && sqft > 0) ? 'sq_ft' : 'as_available';
  }

  _quantityModeFor(measurementType) {
    if (this._NUMBER_MEASUREMENT_TYPES.has(measurementType)) return 'numeric';
    if (measurementType === 'as_available') return 'as_available';
    return 'not_applicable';
  }

  _deriveCleaningFrequency(frequencyType, frequencyValue, frequencyUnit) {
    switch ((frequencyType || '').toLowerCase()) {
      case 'once_daily':
      case 'daily':
        return 'daily';
      case 'two_times_daily':
      case 'twice_daily':
      case 'twice_daily_shift':
        return 'twice_daily';
      case 'three_times_daily':
      case 'shift_wise':
        return 'shift_wise';
      case 'four_times_daily':
        return 'four_times_daily';
      case 'custom':
        if (String(frequencyUnit || '').toLowerCase() === 'day') {
          const v = this._toIntOrNull(frequencyValue);
          if (v === 2) return 'twice_daily';
          if (v === 3) return 'shift_wise';
          if (v === 4) return 'four_times_daily';
          if (v !== null && v > 4) return '4hrs';
        }
        return 'daily';
      default:
        return 'daily';
    }
  }

  _resolveFrequency(body, existing) {
    const ftype = body.frequencyType || existing?.frequencyType || 'daily';
    let fval;
    let funit;
    if (String(ftype).toLowerCase() === 'custom') {
      fval = body.frequencyValue !== undefined
        ? this._toIntOrNull(body.frequencyValue)
        : (existing?.frequencyValue ?? null);
      funit = body.frequencyUnit || existing?.frequencyUnit || null;
    } else {
      fval = (body.frequencyValue !== undefined && body.frequencyValue !== null && body.frequencyValue !== '')
        ? this._toIntOrNull(body.frequencyValue)
        : null;
      funit = (body.frequencyUnit !== undefined && body.frequencyUnit !== null && body.frequencyUnit !== '')
        ? body.frequencyUnit
        : null;
    }

    let boqTimes = (body.boqTimesPerPeriod !== undefined && body.boqTimesPerPeriod !== null && body.boqTimesPerPeriod !== '')
      ? this._toIntOrNull(body.boqTimesPerPeriod)
      : (existing?.boqTimesPerPeriod ?? null);
    if (boqTimes === null || boqTimes < 1) {
      boqTimes = (String(ftype).toLowerCase() === 'custom' && String(funit).toLowerCase() === 'day' && fval !== null)
        ? fval
        : 1;
    }

    const freqChanged = body.frequencyType !== undefined || body.frequencyValue !== undefined
      || body.frequencyUnit !== undefined || body.boqTimesPerPeriod !== undefined;
    const cleaningFrequency = body.cleaningFrequency
      || (freqChanged ? (this._deriveCleaningFrequency(ftype, fval, funit) || 'daily')
                      : (existing?.cleaningFrequency || 'daily'));

    return { frequencyType: ftype, frequencyValue: fval, frequencyUnit: funit, boqTimesPerPeriod: boqTimes, cleaningFrequency };
  }

  _resolveQuantity(body, existing, measurementType, frequency) {
    const numeric = this._NUMBER_MEASUREMENT_TYPES.has(measurementType);
    let quantity;
    if (numeric) {
      const raw = body.quantity ?? body.areaQuantity ?? body.basicAreaSqFt
        ?? (existing?.quantity ?? existing?.basicAreaSqFt ?? null);
      quantity = this._toNumberOrNull(raw);
    } else {
      let raw;
      if (measurementType === 'not_applicable') {
        raw = null;
      } else if (body.quantity !== undefined && body.quantity !== null && body.quantity !== '') {
        raw = body.quantity;
      } else if (body.areaQuantity !== undefined && body.areaQuantity !== null && body.areaQuantity !== '') {
        raw = body.areaQuantity;
      } else if (body.basicAreaSqFt !== undefined && body.basicAreaSqFt !== null && body.basicAreaSqFt !== '') {
        raw = body.basicAreaSqFt;
      } else {
        raw = existing?.quantity ?? null;
      }
      quantity = this._toNumberOrNull(raw);
      if (measurementType === 'not_applicable') quantity = null;
    }

    let basicAreaSqFt;
    if (measurementType === 'sq_ft') {
      basicAreaSqFt = quantity;
    } else if (body.basicAreaSqFt !== undefined) {
      basicAreaSqFt = this._toNumberOrNull(body.basicAreaSqFt);
    } else if (existing?.basicAreaSqFt != null) {
      basicAreaSqFt = this._toNumberOrNull(existing.basicAreaSqFt);
    } else {
      basicAreaSqFt = null;
    }

    let tenderedAreaPerDay = (existing?.tenderedAreaPerDay != null) ? this._toNumberOrNull(existing.tenderedAreaPerDay) : null;
    if (body.tenderedAreaPerDay !== undefined && body.tenderedAreaPerDay !== null && body.tenderedAreaPerDay !== '') {
      tenderedAreaPerDay = this._toNumberOrNull(body.tenderedAreaPerDay);
    }

    if (measurementType === 'sq_ft') {
      const areaChanged = body.basicAreaSqFt !== undefined || body.quantity !== undefined
        || body.areaQuantity !== undefined || body.frequencyType !== undefined
        || body.boqTimesPerPeriod !== undefined || body.frequencyValue !== undefined
        || body.frequencyUnit !== undefined;
      if (areaChanged || tenderedAreaPerDay === null) {
        tenderedAreaPerDay = this._calcTenderedArea(quantity || 0, frequency.frequencyType, frequency.boqTimesPerPeriod);
      }
    }

    return { quantity, basicAreaSqFt, tenderedAreaPerDay };
  }

  _validateAreaConfig(measurementType, quantity, frequency) {
    if (this._NUMBER_MEASUREMENT_TYPES.has(measurementType)) {
      if (quantity === null || quantity <= 0) {
        throw new ValidationError(
          `Quantity is required and must be a positive number for measurement type "${measurementType}"`
        );
      }
    }
    if (String(frequency.frequencyType).toLowerCase() === 'custom') {
      if (frequency.frequencyValue === null || frequency.frequencyValue <= 0) {
        throw new ValidationError('Custom frequency requires a frequency value greater than 0');
      }
      if (!this._FREQUENCY_UNITS.has(String(frequency.frequencyUnit).toLowerCase())) {
        throw new ValidationError('Custom frequency requires a valid frequency unit (day, week, fortnight, month or shift)');
      }
    }
  }

  _resolveStatus(body, existing, fallback) {
    if (body.status !== undefined) return body.status === 'inactive' ? 'inactive' : 'active';
    if (body.active !== undefined) return body.active === false ? 'inactive' : 'active';
    return existing?.status || fallback || 'active';
  }

  // ─── Station Areas ──────────────────────────────────────────────────────────
  async createStationArea(body) {
    const areaName = body.areaName || body.name || body.subArea;
    const { stationId } = body;
    if (!stationId || !areaName) throw new ValidationError('stationId and areaName are required');
    const stationDoc = await db.collection('stations').doc(stationId).get();
    if (!stationDoc.exists) throw new NotFoundError('Station not found');
    const ref = db.collection('stationAreas').doc();

    const measurementType = this._resolveMeasurementType(body, null);
    const frequency = this._resolveFrequency(body, null);
    const { quantity, basicAreaSqFt, tenderedAreaPerDay } = this._resolveQuantity(body, null, measurementType, frequency);

    this._validateAreaConfig(measurementType, quantity, frequency);
    const status = this._resolveStatus(body, null, 'active');

    const data = {
      uid: ref.id, stationId,
      stationName: stationDoc.data().stationName || '',
      areaName, name: areaName,
      subArea: body.subArea || null,
      workItem: body.workItem || '',
      areaType: body.areaType || 'Other',
      mainArea: body.mainArea || '',
      measurementType,
      quantity,
      quantityMode: body.quantityMode || this._quantityModeFor(measurementType),
      basicAreaSqFt,
      frequencyType: frequency.frequencyType,
      frequencyValue: frequency.frequencyValue,
      frequencyUnit: frequency.frequencyUnit,
      boqTimesPerPeriod: frequency.boqTimesPerPeriod,
      tenderedAreaPerDay,
      cleaningFrequency: frequency.cleaningFrequency,
      priority: body.priority || 3,
      order: body.order ?? 0,
      description: body.description || '',
      remarks: body.remarks || '',
      status,
      active: status === 'active',
      platformId: body.platformId || null,
      createdAt: new Date().toISOString(), updatedAt: new Date().toISOString()
    };
    await ref.set(data);
    return { message: 'Station area created', uid: ref.id, data };
  }

  async updateStationArea(uid, body) {
    const ref = db.collection('stationAreas').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Station area not found');
    const existing = doc.data();

    const measurementType = this._resolveMeasurementType(body, existing);
    const frequency = this._resolveFrequency(body, existing);
    const { quantity, basicAreaSqFt, tenderedAreaPerDay } = this._resolveQuantity(body, existing, measurementType, frequency);

    this._validateAreaConfig(measurementType, quantity, frequency);
    const status = this._resolveStatus(body, existing, existing.status || 'active');

    const areaName = body.areaName || body.name
      || ((typeof body.subArea === 'string' && body.subArea.trim().length > 0) ? body.subArea.trim() : null)
      || existing.areaName || existing.name;

    const updates = {
      name: areaName,
      areaName,
      measurementType,
      quantity,
      quantityMode: body.quantityMode || this._quantityModeFor(measurementType),
      basicAreaSqFt,
      frequencyType: frequency.frequencyType,
      frequencyValue: frequency.frequencyValue,
      frequencyUnit: frequency.frequencyUnit,
      boqTimesPerPeriod: frequency.boqTimesPerPeriod,
      tenderedAreaPerDay,
      cleaningFrequency: frequency.cleaningFrequency,
      status,
      active: status === 'active',
      updatedAt: new Date().toISOString()
    };

    // Copy through the remaining user-editable configuration fields.
    for (const key of ['workItem', 'subArea', 'mainArea', 'areaType', 'description', 'remarks', 'platformId', 'priority', 'order', 'quantityMode']) {
      if (body[key] !== undefined) updates[key] = body[key];
    }
    delete updates.uid;
    delete updates.id;
    delete updates.stationId;
    delete updates.stationName;
    delete updates.createdAt;

    await ref.update(updates);
    return { message: 'Station area updated', uid };
  }

  async deleteStationArea(uid) {
    const ref = db.collection('stationAreas').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Station area not found');
    await ref.update({ status: 'inactive', deletedAt: new Date().toISOString(), updatedAt: new Date().toISOString() });
    return { message: 'Station area deleted', uid };
  }

  async listStationAreas(stationId, user) {
    if (!stationId) throw new ValidationError('stationId is required');
    const snapshot = await db.collection('stationAreas')
      .where('stationId', '==', stationId)
      .where('status', '==', 'active').get();
    const areas = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
    areas.sort((a, b) => (a.areaName || '').localeCompare(b.areaName || ''));
    return { count: areas.length, areas };
  }

  async getStationArea(uid) {
    const doc = await db.collection('stationAreas').doc(uid).get();
    if (!doc.exists) throw new NotFoundError('Station area not found');
    return { id: doc.id, ...doc.data() };
  }

  async getStationAreaSummary(stationId) {
    if (!stationId) throw new ValidationError('stationId is required');
    const snapshot = await db.collection('stationAreas')
      .where('stationId', '==', stationId)
      .where('status', '==', 'active').get();
    const areas = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));

    const grouped = {};
    let totalBasicArea = 0;
    let totalTenderedArea = 0;

    for (const area of areas) {
      const main = area.mainArea || 'Uncategorized';
      if (!grouped[main]) grouped[main] = [];
      grouped[main].push(area);
      totalBasicArea += (area.basicAreaSqFt || 0);
      totalTenderedArea += (area.tenderedAreaPerDay || 0);
    }

    return {
      count: areas.length,
      grouped,
      totals: {
        totalBasicArea: Math.round(totalBasicArea),
        totalTenderedArea: Math.round(totalTenderedArea)
      }
    };
  }

  // ─── Station Zones ──────────────────────────────────────────────────────────
  async createStationZone(body) {
    const { stationId } = body;
    const zoneName = body.zoneName || body.name;
    if (!stationId || !zoneName) throw new ValidationError('stationId and zoneName are required');
    const ref = db.collection('stationZones').doc();
    const data = {
      uid: ref.id, stationId, areaId: body.areaId || null,
      zoneName, name: zoneName, zoneType: body.zoneType || 'Other',
      description: body.description || '',
      status: 'active',
      createdAt: new Date().toISOString(), updatedAt: new Date().toISOString()
    };
    await ref.set(data);
    return { message: 'Station zone created', uid: ref.id, data };
  }

  async listStationZones(stationId, areaId, user) {
    if (!stationId) throw new ValidationError('stationId is required');
    let q = db.collection('stationZones').where('stationId', '==', stationId).where('status', '==', 'active');
    if (areaId) q = q.where('areaId', '==', areaId);
    const snapshot = await q.get();
    let zones = snapshot.docs.map(d => {
      const data = d.data();
      const zName = data.zoneName || data.name || '';
      return {
        id: d.id,
        uid: d.id,
        ...data,
        name: zName,
        zoneName: zName
      };
    });

    if (zones.length === 0 && areaId) {
      const areaDoc = await db.collection('stationAreas').doc(areaId).get();
      if (areaDoc.exists && (areaDoc.data().areaName || areaDoc.data().name || '').toLowerCase().includes('platform')) {
        zones = [
          { id: `${areaId}-toilet`, uid: `${areaId}-toilet`, stationId, areaId, name: 'Toilet', zoneName: 'Toilet', status: 'active', createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() },
          { id: `${areaId}-waiting`, uid: `${areaId}-waiting`, stationId, areaId, name: 'Waiting Room', zoneName: 'Waiting Room', status: 'active', createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() },
          { id: `${areaId}-concourse`, uid: `${areaId}-concourse`, stationId, areaId, name: 'Concourse', zoneName: 'Concourse', status: 'active', createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() },
          { id: `${areaId}-track`, uid: `${areaId}-track`, stationId, areaId, name: 'Track Side', zoneName: 'Track Side', status: 'active', createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() }
        ];
      }
    }

    return { count: zones.length, zones };
  }

  async getStationZone(uid) {
    const doc = await db.collection('stationZones').doc(uid).get();
    if (!doc.exists) throw new NotFoundError('Station zone not found');
    const data = doc.data();
    const zName = data.zoneName || data.name || '';
    return {
      id: doc.id,
      uid: doc.id,
      ...data,
      name: zName,
      zoneName: zName
    };
  }

  async updateStationZone(uid, body) {
    const ref = db.collection('stationZones').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Station zone not found');
    const zoneName = body.zoneName || body.name;
    const updates = { ...body, updatedAt: new Date().toISOString() };
    if (zoneName) {
      updates.zoneName = zoneName;
      updates.name = zoneName;
    }
    delete updates.uid;
    await ref.update(updates);
    return { message: 'Station zone updated', uid };
  }

  async deleteStationZone(uid) {
    const ref = db.collection('stationZones').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Station zone not found');
    await ref.update({ status: 'inactive', deletedAt: new Date().toISOString(), updatedAt: new Date().toISOString() });
    return { message: 'Station zone deleted', uid };
  }

  // ─── Contractor Mappings ────────────────────────────────────────────────────
  async mapContractor(body) {
    const { stationId, contractorId } = body;
    if (!stationId || !contractorId) throw new ValidationError('stationId and contractorId are required');
    const ref = db.collection('stationContractorMappings').doc();
    const data = {
      uid: ref.id, stationId, contractorId,
      contractId: body.contractId || null,
      status: 'active',
      createdAt: new Date().toISOString(), updatedAt: new Date().toISOString()
    };
    await ref.set(data);
    return { message: 'Contractor mapped', uid: ref.id, data };
  }

  async listContractorMappings(stationId, user) {
    if (!stationId) throw new ValidationError('stationId is required');
    const snapshot = await db.collection('stationContractorMappings')
      .where('stationId', '==', stationId).where('status', '==', 'active').get();
    const mappings = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
    return { count: mappings.length, mappings };
  }

  async getContractorMapping(uid) {
    const doc = await db.collection('stationContractorMappings').doc(uid).get();
    if (!doc.exists) throw new NotFoundError('Contractor mapping not found');
    return { id: doc.id, ...doc.data() };
  }

  async updateContractorMapping(uid, body) {
    const ref = db.collection('stationContractorMappings').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Contractor mapping not found');
    await ref.update({ ...body, updatedAt: new Date().toISOString() });
    return { message: 'Contractor mapping updated', uid };
  }

  async deleteContractorMapping(uid) {
    const ref = db.collection('stationContractorMappings').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Contractor mapping not found');
    await ref.update({ status: 'inactive', deletedAt: new Date().toISOString(), updatedAt: new Date().toISOString() });
    return { message: 'Contractor mapping deleted', uid };
  }

  // ─── Schedules ──────────────────────────────────────────────────────────────
  async createSchedule(body) {
    const { stationId } = body;
    if (!stationId) throw new ValidationError('stationId is required');
    const ref = db.collection('stationSchedules').doc();
    const data = {
      uid: ref.id,
      stationId,
      scheduleName: body.scheduleName || 'Schedule',
      areaId: body.areaId || '',
      zoneId: body.zoneId || '',
      frequency: body.frequency || 'daily',
      shift: body.shift || body.shiftType || 'morning',
      shiftType: body.shift || body.shiftType || 'morning',
      entityId: body.entityId || '',
      entityName: body.entityName || '',
      supervisorId: body.supervisorId || '',
      supervisorName: body.supervisorName || '',
      startTime: body.startTime || '06:00',
      endTime: body.endTime || '14:00',
      daysOfWeek: body.daysOfWeek || [],
      estimatedHours: body.estimatedHours || null,
      effectiveFrom: body.effectiveFrom || null,
      effectiveTo: body.effectiveTo || null,
      status: 'active',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
    await ref.set(data);
    return { message: 'Schedule created', uid: ref.id, data };
  }

  async listSchedules(stationId, user) {
    if (!stationId) throw new ValidationError('stationId is required');
    const role = (user?.role || '').toUpperCase();
    if (!this._isMasterOrAdmin(user)) {
      const userStations = user?.stations || (user?.stationId ? [user.stationId] : []);
      if (userStations.length > 0 && !userStations.includes(stationId)) {
        throw new ForbiddenError('You can only access schedules for your assigned stations');
      }
    }
    const snapshot = await db.collection('stationSchedules')
      .where('stationId', '==', stationId).where('status', '==', 'active').get();
    const schedules = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
    return { count: schedules.length, schedules };
  }

  async getSchedule(uid) {
    const doc = await db.collection('stationSchedules').doc(uid).get();
    if (!doc.exists) throw new NotFoundError('Schedule not found');
    return { id: doc.id, ...doc.data() };
  }

  async updateSchedule(uid, body) {
    const ref = db.collection('stationSchedules').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Schedule not found');
    await ref.update({ ...body, updatedAt: new Date().toISOString() });
    return { message: 'Schedule updated', uid };
  }

  async deleteSchedule(uid) {
    const ref = db.collection('stationSchedules').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Schedule not found');
    await ref.update({ status: 'inactive', deletedAt: new Date().toISOString(), updatedAt: new Date().toISOString() });
    return { message: 'Schedule deleted', uid };
  }

  async generateTasksFromSchedule(data) {
    const { scheduleId, date, generateForDays } = data;
    if (!scheduleId) throw new ValidationError('scheduleId is required');
    const scheduleDoc = await db.collection('stationSchedules').doc(scheduleId).get();
    if (!scheduleDoc.exists) throw new NotFoundError('Schedule not found');
    const schedule = scheduleDoc.data();

    const targetDate = date || getISTDate();
    const numDays = Math.max(1, generateForDays || 1);
    const daysToGenerate = [];
    const start = new Date(targetDate + 'T00:00:00Z');
    for (let i = 0; i < numDays; i++) {
      const d = new Date(start);
      d.setUTCDate(d.getUTCDate() + i);
      daysToGenerate.push(d.toISOString().split('T')[0]);
    }

    // ─── Resolve the area(s) this schedule is responsible for ──────────────
    // - schedule.areaId set   -> that exact area (skipped when the area has
    //   been deactivated so stale duplicate schedules generate nothing).
    // - schedule.areaId empty  -> EVERY active area of the station, so a
    //   per-shift default schedule produces daily tasks for all areas.
    const areas = [];
    if (schedule.areaId) {
      const areaDoc = await db.collection('stationAreas').doc(schedule.areaId).get();
      if (areaDoc.exists) {
        const areaData = areaDoc.data();
        if (String(areaData.status || 'active').toLowerCase() !== 'inactive') {
          areas.push({ id: schedule.areaId, data: areaData });
        }
      }
    } else {
      const snap = await db.collection('stationAreas')
        .where('stationId', '==', schedule.stationId)
        .where('status', '==', 'active').get();
      snap.forEach(doc => areas.push({ id: doc.id, data: doc.data() }));
      if (areas.length === 0) {
        const all = await db.collection('stationAreas')
          .where('stationId', '==', schedule.stationId).get();
        all.forEach(doc => areas.push({ id: doc.id, data: doc.data() }));
      }
    }

    // ─── Idempotency: one task per (station, date, area, time) regardless of
    // how many (duplicate) schedules or cron runs try to create it. Uses
    // equality filters only (stationId + date) so no composite index is
    // required. Existing slots are recorded WITH their owner so they can also
    // be self-healed: slots whose supervisor/shift no longer matches the
    // current shift-holder are reassigned / re-tagged instead of duplicated.
    const existingMap = new Map();
    const TERMINAL = new Set(['completed', 'approved', 'rejected', 'cancelled']);
    for (const dayStr of daysToGenerate) {
      try {
        const daySnap = await db.collection('cleaningTasks')
          .where('stationId', '==', schedule.stationId)
          .where('date', '==', dayStr)
          .select('areaId', 'scheduledTime', 'status', 'supervisorId', 'shift', 'manualOverride')
          .get();
        daySnap.forEach(doc => {
          const d = doc.data();
          // A cancelled task that was closed by a MANUAL override still occupies
          // its slot: the auto generator must not recreate the auto task that the
          // user deliberately cancelled/reduced (manual override wins).
          if (d.status === 'cancelled' && !d.manualOverride) return;
          existingMap.set(`${dayStr}|${d.areaId || ''}|${d.scheduledTime}`, {
            id: doc.id,
            supervisorId: d.supervisorId || '',
            shift: d.shift ? String(d.shift).trim().toLowerCase() : '',
            status: d.status,
          });
        });
      } catch (dayErr) {
        const allSnap = await db.collection('cleaningTasks')
          .where('stationId', '==', schedule.stationId).get();
        allSnap.forEach(doc => {
          const d = doc.data();
          if ((d.status !== 'cancelled' || d.manualOverride) && (d.date || d.scheduledDate || '') === dayStr) {
            existingMap.set(`${dayStr}|${d.areaId || ''}|${d.scheduledTime}`, {
              id: doc.id,
              supervisorId: d.supervisorId || '',
              shift: d.shift ? String(d.shift).trim().toLowerCase() : '',
              status: d.status,
            });
          }
        });
      }
    }

    let totalCount = 0;
    const allTaskIds = [];
    const supervisorsByShift = await this._supervisorsByShift(schedule);
    const batch = db.batch();
    let batchCount = 0;

    for (const dayStr of daysToGenerate) {
      for (const area of areas) {
        // Frequency always comes from the AREA's mapped cleaning frequency
        // (how many times this area must be cleaned), never a schedule's
        // hardcoded every_30_min. Slot times use the canonical full-day
        // times for that frequency so each day has exactly its required
        // number of cleaning passes, spread across the shifts.
        const areaData = area.data || {};
        const effectiveFrequency =
          areaData.cleaningFrequency || areaData.frequency || schedule.frequency || 'daily';
        const taskTimes = this._getCanonicalFrequencyTimes(effectiveFrequency);
        const areaName = areaData.name || areaData.areaName || schedule.areaName || '';

        for (const timeSlot of taskTimes) {
          const key = `${dayStr}|${area.id}|${timeSlot}`;
          const slotShift = this._shiftForTime(timeSlot) ||
            (schedule.shift || 'morning').toString().toLowerCase();
          const shiftSupervisor = supervisorsByShift.get(slotShift);
          const supervisorId = shiftSupervisor?.uid || schedule.supervisorId || null;
          const supervisorName = shiftSupervisor?.fullName || schedule.supervisorName || '';

          // Self-healing: reassign a stale slot to the current shift-holder
          // and retag its shift so the supervisor screen count matches the
          // task list. Terminal tasks are never touched.
          const existing = existingMap.get(key);
          if (existing) {
            if (!TERMINAL.has(existing.status) && supervisorId) {
              const patches = {};
              if (existing.supervisorId !== supervisorId) {
                patches.supervisorId = supervisorId;
                patches.supervisorName = supervisorName;
              }
              if (existing.shift !== slotShift) patches.shift = slotShift;
              if (Object.keys(patches).length > 0) {
                patches.updatedAt = new Date().toISOString();
                batch.update(db.collection('cleaningTasks').doc(existing.id), patches);
                batchCount++;
              }
            }
            continue;
          }
          if (!supervisorId) continue;

          const taskRef = db.collection('cleaningTasks').doc();
          const task = {
            uid: taskRef.id,
            stationId: schedule.stationId,
            stationName: schedule.stationName || '',
            areaId: area.id,
            areaName,
            zoneId: areaData.zoneId || schedule.zoneId || '',
            shift: slotShift,
            frequency: effectiveFrequency,
            date: dayStr,
            scheduledDate: dayStr,
            scheduledTime: timeSlot,
            supervisorId,
            supervisorName,
            scheduleId,
            entityId: areaData.entityId || schedule.entityId || '',
            entityName: areaData.entityName || schedule.entityName || '',
            activityType: 'station_cleaning',
            status: 'pending',
            workerId: null,
            workerName: null,
            priority: 3,
            startedAt: null, completedAt: null,
            approvedAt: null, rejectedAt: null,
            beforePhoto: null, afterPhoto: null,
            gpsLat: null, gpsLng: null,
            supervisorNotes: null, rejectionReason: null,
            resubmittedAt: null,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: new Date().toISOString()
          };
          batch.set(taskRef, task);
          existingMap.set(key, {
            id: taskRef.id,
            supervisorId,
            shift: slotShift,
            status: 'pending',
          });
          allTaskIds.push(taskRef.id);
          batchCount++;
        }
      }
    }

    if (batchCount > 0) {
      await batch.commit();
      totalCount += batchCount;
    }

    return {
      message: `Generated ${totalCount} tasks for ${daysToGenerate.length} day(s) across ${areas.length} area(s)`,
      count: totalCount,
      taskIds: allTaskIds,
    };
  }

  // Canonical full-day slot times for a given area frequency, mirroring
  // taskManagementService._getDefaultFrequencyTimes so the schedule generator
  // agrees with the frequency/attendance dashboards.
  _getCanonicalFrequencyTimes(frequency) {
    switch (frequency) {
      case 'hourly':
        return ['06:00', '07:00', '08:00', '09:00', '10:00', '11:00', '12:00', '13:00', '14:00', '15:00', '16:00', '17:00', '18:00', '19:00', '20:00', '21:00', '22:00'];
      case '2hrs':
        return ['06:00', '08:00', '10:00', '12:00', '14:00', '16:00', '18:00', '20:00', '22:00'];
      case '4hrs':
        return ['06:00', '10:00', '14:00', '18:00', '22:00'];
      case 'daily':
        return ['08:00'];
      case 'twice_daily':
        return ['06:00', '18:00'];
      case 'shift_wise':
        return ['06:00', '14:00', '22:00'];
      case 'four_times_daily':
        return ['06:00', '10:00', '14:00', '18:00'];
      default:
        return ['08:00'];
    }
  }

  _shiftForTime(timeStr) {
    const m = /^(\d{1,2}):/.exec(String(timeStr || ''));
    if (!m) return null;
    const h = parseInt(m[1], 10);
    if (h >= 4 && h < 12) return 'morning';
    if (h >= 12 && h < 20) return 'evening';
    return 'night';
  }

  // Formats a minute-of-day value onto a 24h clock, wrapping past midnight
  // (e.g. 1440 -> 00:00) so night-shift windows produce valid slot times.
  _wrapTime(minutes) {
    const m = ((minutes % 1440) + 1440) % 1440;
    return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
  }

  // Supervisors recorded for each shift window at a station (from
  // stationSupervisorShifts). Used so night-window tasks are given to the
  // night supervisor even when the schedule itself specifies another one.
  async _supervisorsByShift(schedule) {
    const map = new Map();
    try {
      const snaps = await db.collection('stationSupervisorShifts')
        .where('stationId', '==', schedule.stationId).get();
      snaps.forEach(doc => {
        const d = doc.data();
        const shift = d.shift ? String(d.shift).trim().toLowerCase() : '';
        if (!shift) return;
        if (!map.has(shift)) {
          map.set(shift, { uid: doc.id, fullName: d.supervisorName || '' });
        }
      });
    } catch (_) {}
    if (schedule.supervisorId) {
      const scheduleShift = (schedule.shift || 'morning').toString().toLowerCase();
      if (!map.has(scheduleShift)) {
        map.set(scheduleShift, { uid: schedule.supervisorId, fullName: schedule.supervisorName || '' });
      }
    }
    return map;
  }

  _calculateTaskTimes(frequency, startTime, endTime) {
    const [startH, startM] = (startTime || '06:00').split(':').map(Number);
    const [endH, endM] = (endTime || '14:00').split(':').map(Number);
    let startMinutes = startH * 60 + (startM || 0);
    let endMinutes = endH * 60 + (endM || 0);
    if (endMinutes <= startMinutes) {
      // Night-shift window wrapping past midnight (e.g. 20:00 -> 04:00 next day).
      endMinutes += 1440;
    }
    const durationMinutes = endMinutes - startMinutes;

    if (durationMinutes <= 0) return [startTime || '08:00'];

    if (frequency === 'hourly_mopping') {
      const slots = [];
      for (let m = 300; m < 1380; m += 60) {
        slots.push(this._wrapTime(m));
      }
      return slots;
    }

    const intervalMap = {
      every_15_min: 15, every15min: 15, every_15min: 15,
      every_30_min: 30, every30min: 30, every_30min: 30,
      hourly: 60, every_1_hour: 60, '2hrs': 120, every_2_hour: 120, every2h: 120, every_2h: 120,
      every_3_hour: 180,
      '4hrs': 240, every_4_hour: 240, every4h: 240, every_4h: 240,
      every_6_hour: 360, every6h: 360, every_6h: 360,
    };

    const interval = intervalMap[frequency];
    if (interval) {
      const slots = [];
      for (let m = startMinutes; m < endMinutes; m += interval) {
        slots.push(this._wrapTime(m));
      }
      return slots;
    }

    switch (frequency) {
      case 'twice_daily':
      case 'twice_daily_shift':
      case 'two_times_daily': {
        const mid1 = startMinutes + Math.floor(durationMinutes * 0.33);
        const mid2 = startMinutes + Math.floor(durationMinutes * 0.66);
        return [this._wrapTime(mid1), this._wrapTime(mid2)];
      }
      case 'three_times_daily': {
        const slots = [];
        for (let i = 1; i <= 3; i++) {
          slots.push(this._wrapTime(startMinutes + Math.floor(durationMinutes * i / 4)));
        }
        return slots;
      }
      case 'four_times_daily': {
        const slots = [];
        for (let i = 1; i <= 4; i++) {
          slots.push(this._wrapTime(startMinutes + Math.floor(durationMinutes * i / 5)));
        }
        return slots;
      }
      case 'six_times_daily':
      case 'once_every_4h': {
        const allSlots = [];
        for (let m = 0; m < endMinutes; m += 240) {
          if (m >= startMinutes) {
            allSlots.push(this._wrapTime(m));
          }
        }
        return allSlots.length > 0 ? allSlots : [startTime || '08:00'];
      }
      case 'once_daily':
      case 'once_per_day':
      case 'daily':
        return [startTime || '08:00'];
      case 'twice_weekly':
      case 'twice_monthly':
      case 'once_weekly':
      case 'once_monthly':
      case 'weekly':
      case 'monthly':
        return [startTime || '08:00'];
      default:
        return [startTime || '08:00'];
    }
  }

  _shiftDefaultTime(shift) {
    const s = (shift || '').toLowerCase();
    if (s.includes('morning')) return '08:00';
    if (s.includes('afternoon')) return '12:00';
    if (s.includes('evening')) return '16:00';
    if (s.includes('night')) return '20:00';
    return '08:00';
  }

  async _createPlatformTasks(platforms, runData, user) {
    const batch = admin.firestore().batch();
    const tasks = [];
    const now = new Date().toISOString();
    const scheduledTime = this._shiftDefaultTime(runData.shift);
    for (const plat of (platforms || [])) {
      if (!runData.supervisorId && !user?.uid) continue;
      const taskRef = db.collection('cleaningTasks').doc();
      const areaId = plat.areaId || `platform_${plat.platformNumber || 'unknown'}_${runData.stationId}`;
      const areaName = plat.areaName || (plat.platformNumber ? `Platform ${plat.platformNumber}` : 'Station Area');
      const taskData = {
        uid: taskRef.id,
        stationId: runData.stationId,
        stationName: runData.stationName || '',
        platformId: plat.platformNumber || '',
        areaId,
        areaName,
        workerId: runData.supervisorId || (user && user.uid) || null,
        workerName: runData.supervisorName || '',
        supervisorId: runData.supervisorId || (user && user.uid) || null,
        activityType: 'station_cleaning',
        frequency: runData.frequency || 'daily',
        scheduledDate: runData.date || runData.runDate,
        scheduledTime,
        priority: 3,
        shift: runData.shift || 'morning',
        status: 'pending',
        runInstanceId: runData.runInstanceId || '',
        createdBy: user && user.uid,
        createdAt: now,
        updatedAt: now
      };
      batch.set(taskRef, taskData);
      tasks.push(taskData);
    }
    if (tasks.length > 0) await batch.commit();
    return tasks;
  }

  // ─── Station Runs ───────────────────────────────────────────────────────────
  async createStationRun(body, user) {
    const { stationId } = body;
    if (!stationId) throw new ValidationError('stationId is required');
    const ref = db.collection('stationRuns').doc();
    
    const runDate = body.date || body.runDate || new Date().toISOString().split('T')[0];
    const shiftType = body.shift || body.shiftType || 'morning';
    const runInstanceId = body.runInstanceId || ref.id;

    const data = {
      ...body,
      uid: ref.id,
      runInstanceId,
      stationId,
      stationName: body.stationName || '',
      date: runDate,
      runDate,
      shift: shiftType,
      shiftType: shiftType.toLowerCase(),
      platforms: body.platforms || [],
      supervisorId: body.supervisorId || (user && user.uid) || null,
      contractorId: body.contractorId || null,
      contractId: body.contractId || (user && user.contractId) || null,
      status: body.status || 'active',
      createdBy: user && user.uid,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
    await ref.set(data);

    const tasks = await this._createPlatformTasks(body.platforms, data, user);

    return { message: 'Station run created', uid: ref.id, data, tasksCreated: tasks.length };
  }

  async listStationRuns(query, user) {
    const { stationId } = query;
    let q = db.collection('stationRuns').limit(200);
    q = this._scopeByContract(q, user, 'stationId');
    q = this._scopeByContractId(q, user);
    if (stationId) q = q.where('stationId', '==', stationId);
    const snapshot = await q.get();
    const runs = snapshot.docs
      .filter(d => d.data().status !== 'deleted')
      .map(d => ({ id: d.id, ...d.data() }));
    return { count: runs.length, runs };
  }

  async updateStationRun(runId, body) {
    const ref = db.collection('stationRuns').doc(runId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Station run not found');
    
    const runDate = body.date || body.runDate || new Date().toISOString().split('T')[0];
    const shiftType = body.shift || body.shiftType || 'morning';

    await ref.update({
      ...body,
      date: runDate,
      runDate,
      shift: shiftType,
      shiftType: shiftType.toLowerCase(),
      updatedAt: new Date().toISOString()
    });
    return { message: 'Station run updated', runId };
  }

  async getMyStationRuns(userId) {
    const supervisorSnap = await db.collection('stationRuns')
      .where('supervisorId', '==', userId).limit(100).get();
    
    const runs = [];
    supervisorSnap.forEach(d => {
      const data = d.data();
      if (data.status !== 'deleted') {
        runs.push({ id: d.id, ...data });
      }
    });
    return { count: runs.length, runs };
  }

  async deleteStationRun(runId) {
    const ref = db.collection('stationRuns').doc(runId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Station run not found');
    await ref.update({ status: 'deleted', deletedAt: new Date().toISOString(), updatedAt: new Date().toISOString() });
    return { message: 'Station run deleted', runId };
  }

  async getWorkerStationRuns(workerId, user) {
    let q = db.collection('stationRuns').limit(300);
    q = this._scopeByContractId(q, user);
    const snapshot = await q.get();
    const runs = [];
    snapshot.forEach(d => {
      const runData = d.data();
      if (runData.status === 'deleted') return;
      if (runData.platforms && Array.isArray(runData.platforms)) {
        const workerPlatforms = runData.platforms.filter(p => p.janitorId === workerId);
        if (workerPlatforms.length > 0) {
          runs.push({ id: d.id, ...runData, platforms: workerPlatforms });
        }
      }
    });
    return { count: runs.length, runs };
  }

  async getSupervisorStationRuns(supervisorId, user) {
    let q = db.collection('stationRuns')
      .where('supervisorId', '==', supervisorId).limit(100);
    q = this._scopeByContractId(q, user);
    const snapshot = await q.get();
    const runs = snapshot.docs
      .filter(d => d.data().status !== 'deleted')
      .map(d => ({ id: d.id, ...d.data() }));
    return { count: runs.length, runs };
  }

  async completePlatform(runId, body, user) {
    const ref = db.collection('stationRuns').doc(runId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Station run not found');

    const runData = doc.data();
    if (runData.status === 'deleted') throw new NotFoundError('Station run not found');

    const platformNumber = body.platformNumber;
    const photoUrl = body.photoUrl;

    if (!platformNumber) {
      throw new Error('platformNumber is required in the body');
    }

    const platforms = runData.platforms || [];
    const platformIndex = platforms.findIndex(p => p.platformNumber === platformNumber);
    if (platformIndex === -1) {
      throw new NotFoundError('Platform not found in this run');
    }

    if (platforms[platformIndex].status === 'Completed') {
       throw new Error('Platform is already completed');
    }

    platforms[platformIndex].status = 'Completed';
    platforms[platformIndex].completedAt = new Date().toISOString();
    platforms[platformIndex].completedBy = user.uid;
    if (photoUrl) {
      platforms[platformIndex].photoUrl = photoUrl;
    }

    const allCompleted = platforms.every(p => p.status === 'Completed');
    const newStatus = allCompleted ? 'Completed' : 'In Progress';

    await ref.update({
      platforms: platforms,
      status: newStatus,
      updatedAt: new Date().toISOString()
    });

    return { message: `Platform ${platformNumber} marked complete`, runId, platformNumber: platformNumber };
  }

  // ─── Station Tasks ──────────────────────────────────────────────────────────
  // Tasks are primarily managed via taskManagementService (used by tasksV2 routes).
  // These methods provide station-task CRUD for admin use cases.

  async submitStationTask(body, user) {
    const { stationId, areaId, workerId } = body;
    const userStationId = user?.stationId;
    if (userStationId && stationId && stationId !== userStationId) {
      throw new ForbiddenError('You can only create tasks in your assigned station');
    }
    const ref = db.collection('cleaningTasks').doc();
    const data = {
      uid: ref.id, stationId, areaId: areaId || null,
      workerId: workerId || null,
      taskType: body.taskType || 'cleaning',
      status: 'pending',
      beforePhoto: body.beforePhoto || null,
      afterPhoto: body.afterPhoto || null,
      remarks: body.remarks || '',
      createdAt: new Date().toISOString(), updatedAt: new Date().toISOString()
    };
    await ref.set(data);
    return { message: 'Task created', uid: ref.id, data };
  }

  async getStationTask(taskId, user) {
    const doc = await db.collection('cleaningTasks').doc(taskId).get();
    if (!doc.exists) throw new NotFoundError('Station task not found');
    const task = doc.data();
    this._verifyStationAccess(task, user);
    return { id: doc.id, ...task };
  }

  async updateStationTask(taskId, body, user) {
    const ref = db.collection('cleaningTasks').doc(taskId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Station task not found');
    this._verifyStationAccess(doc.data(), user);
    await ref.update({ ...body, updatedAt: new Date().toISOString() });
    return { message: 'Station task updated', taskId };
  }

  async deleteStationTask(taskId) {
    const ref = db.collection('cleaningTasks').doc(taskId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Station task not found');
    await ref.delete();
    return { message: 'Station task deleted', taskId };
  }

  async listPendingStationTasks(runInstanceId, user) {
    const pendingStatuses = ['completed', 'resubmitted'];
    let allTasks = [];
    const userStationId = user?.stationId || null;
    for (const status of pendingStatuses) {
      let q = db.collection('cleaningTasks').where('status', '==', status).limit(200);
      if (runInstanceId) q = q.where('runInstanceId', '==', runInstanceId);
      if (userStationId) q = q.where('stationId', '==', userStationId);
      const snapshot = await q.get();
      snapshot.forEach(d => allTasks.push({ id: d.id, ...d.data() }));
    }
    return { count: allTasks.length, tasks: allTasks };
  }

  // ─── Area-Task Frequency Mapping (SRS #2) ──────────────────────────────────
  async createAreaTaskFrequency(body) {
    const { stationId, areaId, taskTypeId, frequencyId, shift } = body;
    if (!stationId || !areaId || !taskTypeId || !frequencyId) {
      throw new ValidationError('stationId, areaId, taskTypeId, and frequencyId are required');
    }
    const ref = db.collection('areaTaskFrequencies').doc();
    const data = {
      uid: ref.id, stationId, areaId, taskTypeId, frequencyId,
      shift: shift || null,
      isActive: true,
      createdAt: new Date().toISOString(), updatedAt: new Date().toISOString()
    };
    await ref.set(data);
    return { message: 'Area-task frequency mapping created', uid: ref.id, data };
  }

  async updateAreaTaskFrequency(uid, body) {
    const ref = db.collection('areaTaskFrequencies').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Area-task frequency mapping not found');
    await ref.update({ ...body, updatedAt: new Date().toISOString() });
    return { message: 'Area-task frequency mapping updated', uid };
  }

  async deleteAreaTaskFrequency(uid) {
    const ref = db.collection('areaTaskFrequencies').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Area-task frequency mapping not found');
    await ref.update({ isActive: false, updatedAt: new Date().toISOString() });
    return { message: 'Area-task frequency mapping deactivated', uid };
  }

  async listAreaTaskFrequencies(query) {
    const { stationId, areaId } = query;
    let q = db.collection('areaTaskFrequencies').where('isActive', '==', true);
    if (stationId) q = q.where('stationId', '==', stationId);
    if (areaId) q = q.where('areaId', '==', areaId);
    const snapshot = await q.limit(200).get();
    const mappings = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
    return { count: mappings.length, mappings };
  }

  // ─── Station Cleaning Forms ─────────────────────────────────────────────────
  async createStationCleaningForm(body, user) {
    const { stationId } = body;
    if (!stationId) throw new ValidationError('stationId is required');
    const ref = db.collection('stationCleaningForms').doc();
    const data = {
      uid: ref.id, stationId,
      entityId: body.entityId || null,
      contractId: body.contractId || null,
      platformId: body.platformId || null,
      shiftType: body.shiftType || 'morning',
      formDate: body.formDate || new Date().toISOString().split('T')[0],
      status: body.status || 'draft',
      createdBy: user && user.uid,
      createdByName: user && (user.fullName || user.name) || 'Unknown',
      submittedBy: user && user.uid,
      submittedByName: user && (user.fullName || user.name) || 'Unknown',
      createdAt: new Date().toISOString(), updatedAt: new Date().toISOString()
    };
    await ref.set(data);
    return { message: 'Cleaning form created', uid: ref.id, data };
  }

  async submitStationCleaningForm(uid, body, user) {
    const ref = db.collection('stationCleaningForms').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Cleaning form not found');
    const currentStatus = doc.data().status;
    const allowed = ['draft', 'rejected'];
    if (!allowed.includes(currentStatus)) {
      throw new ValidationError(`Only draft or rejected forms can be submitted. Current status: ${currentStatus}`);
    }
    await ref.update({
      ...body, status: 'submitted',
      submittedBy: user && user.uid,
      submittedByName: user && (user.fullName || user.name) || 'Unknown',
      submittedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });
    return { message: 'Cleaning form submitted', uid };
  }

  async approveStationCleaningForm(uid, user) {
    const ref = db.collection('stationCleaningForms').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Cleaning form not found');
    await ref.update({
      status: 'approved',
      approvedBy: user && user.uid,
      approvedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });
    return { message: 'Cleaning form approved', uid };
  }

  async rejectStationCleaningForm(uid, reason, user) {
    const ref = db.collection('stationCleaningForms').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Cleaning form not found');
    await ref.update({
      status: 'rejected',
      rejectionReason: reason || '',
      rejectedBy: user && user.uid,
      rejectedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });
    return { message: 'Cleaning form rejected', uid };
  }

  async scoreStationCleaningForm(uid, scoringData, totalScore, grade, user) {
    const ref = db.collection('stationCleaningForms').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Cleaning form not found');
    await ref.update({
      scoringData: scoringData || {},
      totalScore: totalScore || 0,
      grade: grade || 'D',
      scoredBy: user && user.uid,
      scoredAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });
    return { message: 'Cleaning form scored', uid, totalScore, grade };
  }

  async lockStationCleaningForm(uid) {
    const ref = db.collection('stationCleaningForms').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Cleaning form not found');
    await ref.update({ locked: true, lockedAt: new Date().toISOString(), updatedAt: new Date().toISOString() });
    return { message: 'Cleaning form locked', uid };
  }

  async listStationCleaningForms(query, user) {
    const { stationId, status, startDate, endDate } = query;
    let q = db.collection('stationCleaningForms').limit(200);
    q = this._scopeByContract(q, user, 'stationId');
    q = this._scopeByContractId(q, user);
    if (stationId) q = q.where('stationId', '==', stationId);
    if (status) q = q.where('status', '==', status);
    const snapshot = await q.get();
    let forms = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
    if (startDate) forms = forms.filter(f => (f.formDate || '') >= startDate);
    if (endDate) forms = forms.filter(f => (f.formDate || '') <= endDate);
    return { count: forms.length, forms };
  }

  async getStationCleaningFormDetail(uid) {
    const doc = await db.collection('stationCleaningForms').doc(uid).get();
    if (!doc.exists) throw new NotFoundError('Cleaning form not found');
    return { id: doc.id, ...doc.data() };
  }

  // ─── Station Dashboard ──────────────────────────────────────────────────────
  async getStationDashboard(user) {
    const now = new Date();
    const today = now.toISOString().split('T')[0];
    const stationId = user && user.stationId;
    const userStations = user?.stations;

    let tasks = [];
    let tasksQuery = db.collection('cleaningTasks')
      .where('scheduledDate', '==', today).limit(500);
    if (stationId) {
      tasksQuery = tasksQuery.where('stationId', '==', stationId);
    } else if (userStations && Array.isArray(userStations) && userStations.length > 0) {
      tasksQuery = tasksQuery.where('stationId', 'in', userStations);
    }
    const snapshot = await tasksQuery.get();
    tasks = snapshot.docs.map(d => d.data());

    const total = tasks.length;
    const completed = tasks.filter(t => t.status === 'completed' || t.status === 'approved').length;
    const inProgress = tasks.filter(t => t.status === 'in_progress').length;
    const pending = tasks.filter(t => t.status === 'pending').length;
    const approved = tasks.filter(t => t.status === 'approved').length;
    const rejected = tasks.filter(t => t.status === 'rejected').length;
    const completionRate = total > 0 ? Math.round(completed / total * 100) : 0;
    const avgScore = total > 0 ? Math.round(tasks.reduce((s, t) => s + this._taskScore(t), 0) / total) : 0;

    return {
      stationId: stationId || null,
      date: today,
      totalTasks: total, completedTasks: completed,
      pendingTasks: pending, inProgressTasks: inProgress,
      approvedTasks: approved, rejectedTasks: rejected,
      completionRate, averageScore: avgScore
    };
  }

  // ─── Pest Control ───────────────────────────────────────────────────────────
  async recordPestControl(body, user) {
    const { stationId, pestType } = body;
    if (!stationId) throw new ValidationError('stationId is required');
    const ref = db.collection('pestControlRecords').doc();
    const data = {
      uid: ref.id, stationId,
      stationName: body.stationName || '',
      pestType: pestType || 'General',
      entityId: body.entityId || null,
      contractId: body.contractId || (user && user.contractId) || null,
      frequency: body.frequency || 'monthly',
      conductedDate: body.conductedDate || new Date().toISOString().split('T')[0],
      area: body.area || '',
      zone: body.zone || '',
      severity: body.severity || 'LOW',
      treatmentMethod: body.treatmentMethod || '',
      chemicalsUsed: body.chemicalsUsed || [],
      status: 'pending',
      evidence: body.evidence || [],
      beforePhoto: body.beforePhoto || '',
      afterPhoto: body.afterPhoto || '',
      remarks: body.remarks || '',
      recordedBy: user && user.uid,
      createdAt: new Date().toISOString(), updatedAt: new Date().toISOString()
    };
    await ref.set(data);
    return { message: 'Pest control record created', uid: ref.id, data };
  }

  async listPestControl(stationId, query, user) {
    if (!stationId) throw new ValidationError('stationId is required');
    const snapshot = await db.collection('pestControlRecords')
      .where('stationId', '==', stationId).limit(200).get();
    const records = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
    return records;
  }

  async listAllPestControl(query, user) {
    const { stationId, status } = query || {};
    let q = db.collection('pestControlRecords').limit(300);
    q = this._scopeByContract(q, user, 'stationId');
    q = this._scopeByContractId(q, user);
    if (stationId) q = q.where('stationId', '==', stationId);
    if (status) q = q.where('status', '==', status);
    const snapshot = await q.get();
    return snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
  }

  async reviewPestControl(uid, body, user) {
    const ref = db.collection('pestControlRecords').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Pest control record not found');
    const status = body.status || 'approved';
    await ref.update({
      status,
      reviewedBy: user && user.uid,
      reviewedAt: new Date().toISOString(),
      reviewNotes: body.notes || '',
      updatedAt: new Date().toISOString()
    });
    return { message: 'Pest control record reviewed', uid, status };
  }

  async pestControlReport(query, user) {
    const { stationId, startDate, endDate } = query || {};
    let q = db.collection('pestControlRecords').limit(300);
    q = this._scopeByContract(q, user, 'stationId');
    q = this._scopeByContractId(q, user);
    if (stationId) q = q.where('stationId', '==', stationId);
    const snapshot = await q.get();
    let records = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
    if (startDate) records = records.filter(r => (r.conductedDate || '') >= startDate);
    if (endDate) records = records.filter(r => (r.conductedDate || '') <= endDate);
    return { count: records.length, records };
  }

  // ─── Machine Deployment ─────────────────────────────────────────────────────
  async deployMachine(body, user) {
    const { stationId, machineType } = body;
    if (!stationId) throw new ValidationError('stationId is required');
    const ref = db.collection('machineDeployments').doc();
    const data = {
      uid: ref.id, stationId,
      machineType: machineType || 'General',
      entityId: body.entityId || null,
      contractId: body.contractId || (user && user.contractId) || null,
      deployedDate: body.deployedDate || new Date().toISOString().split('T')[0],
      status: 'deployed',
      quantity: body.quantity || 1,
      remarks: body.remarks || '',
      deployedBy: user && user.uid,
      createdAt: new Date().toISOString(), updatedAt: new Date().toISOString()
    };
    await ref.set(data);
    return { message: 'Machine deployed', uid: ref.id, data };
  }

  async listMachines(query, user) {
    const { stationId } = query || {};
    let q = db.collection('machineDeployments').limit(200);
    q = this._scopeByContract(q, user, 'stationId');
    q = this._scopeByContractId(q, user);
    if (stationId) q = q.where('stationId', '==', stationId);
    const snapshot = await q.get();
    return snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
  }

  async returnMachine(uid, body, user) {
    const ref = db.collection('machineDeployments').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Machine deployment not found');
    await ref.update({
      status: 'returned',
      returnedDate: body.returnedDate || new Date().toISOString().split('T')[0],
      returnedBy: user && user.uid,
      returnRemarks: body.remarks || '',
      updatedAt: new Date().toISOString()
    });
    return { message: 'Machine returned', uid };
  }

  async maintenanceMachine(uid, body, user) {
    const ref = db.collection('machineDeployments').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Machine deployment not found');
    await ref.update({
      status: 'maintenance',
      maintenanceReason: body.reason || '',
      maintenanceBy: user && user.uid,
      updatedAt: new Date().toISOString()
    });
    return { message: 'Machine sent for maintenance', uid };
  }

  async machineReport(query, user) {
    const { stationId } = query || {};
    let q = db.collection('machineDeployments').limit(300);
    q = this._scopeByContract(q, user, 'stationId');
    q = this._scopeByContractId(q, user);
    if (stationId) q = q.where('stationId', '==', stationId);
    const snapshot = await q.get();
    const records = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
    return { count: records.length, records };
  }

  // ─── Garbage Disposal ───────────────────────────────────────────────────────
  async recordGarbageDisposal(body, user) {
    const { stationId } = body;
    if (!stationId) throw new ValidationError('stationId is required');
    const ref = db.collection('garbageDisposalRecords').doc();
    const data = {
      uid: ref.id, stationId,
      stationName: body.stationName || '',
      entityId: body.entityId || null,
      contractId: body.contractId || (user && user.contractId) || null,
      disposalDate: body.disposalDate || new Date().toISOString().split('T')[0],
      garbageType: body.garbageType || body.wasteType || 'General',
      wasteType: body.wasteType || '',
      quantityKg: body.quantityKg || 0,
      area: body.area || '',
      disposalMethod: body.disposalMethod || '',
      disposalAgency: body.disposalAgency || '',
      vehicleNumber: body.vehicleNumber || '',
      notes: body.notes || '',
      status: 'recorded',
      evidence: body.evidence || [],
      beforePhoto: body.beforePhoto || '',
      afterPhoto: body.afterPhoto || '',
      remarks: body.remarks || '',
      recordedBy: user && user.uid,
      createdAt: new Date().toISOString(), updatedAt: new Date().toISOString()
    };
    await ref.set(data);
    return { message: 'Garbage disposal recorded', uid: ref.id, data };
  }

  async listGarbageRecords(query, user) {
    const { stationId, startDate, endDate, status } = query || {};
    let q = db.collection('garbageDisposalRecords').limit(300);
    q = this._scopeByContract(q, user, 'stationId');
    q = this._scopeByContractId(q, user);
    if (stationId) q = q.where('stationId', '==', stationId);
    if (status) q = q.where('status', '==', status);
    const snapshot = await q.get();
    let records = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
    if (startDate) records = records.filter(r => (r.disposalDate || '') >= startDate);
    if (endDate) records = records.filter(r => (r.disposalDate || '') <= endDate);
    return records;
  }

  async approveGarbageRecord(uid, user) {
    const ref = db.collection('garbageDisposalRecords').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Garbage record not found');
    const record = doc.data();
    if (record.status !== 'recorded') throw new ValidationError(`Cannot approve. Current status: ${record.status}`);
    await ref.update({
      status: 'approved',
      reviewedBy: user && user.uid,
      reviewedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });
    return { message: 'Garbage record approved', uid };
  }

  async rejectGarbageRecord(uid, body, user) {
    const reason = body.reason || '';
    if (!reason.trim()) throw new ValidationError('Rejection reason is required');
    const ref = db.collection('garbageDisposalRecords').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Garbage record not found');
    const record = doc.data();
    if (record.status !== 'recorded') throw new ValidationError(`Cannot reject. Current status: ${record.status}`);
    await ref.update({
      status: 'rejected',
      reviewedBy: user && user.uid,
      reviewedAt: new Date().toISOString(),
      rejectionReason: reason,
      updatedAt: new Date().toISOString()
    });
    return { message: 'Garbage record rejected', uid };
  }

  async garbageReport(query, user) {
    const { stationId, startDate, endDate } = query || {};
    let q = db.collection('garbageDisposalRecords').limit(300);
    q = this._scopeByContract(q, user, 'stationId');
    q = this._scopeByContractId(q, user);
    if (stationId) q = q.where('stationId', '==', stationId);
    const snapshot = await q.get();
    let records = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
    if (startDate) records = records.filter(r => (r.disposalDate || '') >= startDate);
    if (endDate) records = records.filter(r => (r.disposalDate || '') <= endDate);
    const totalKg = records.reduce((s, r) => s + (r.quantityKg || 0), 0);
    return { count: records.length, totalKg, records };
  }

  // ─── Legacy Dashboards ──────────────────────────────────────────────────────
  async getWorkerDashboard(workerId, query = {}) {
    const { date } = query;
    const targetDate = date || new Date().toISOString().split('T')[0];
    const workerDoc = await db.collection('users').doc(workerId).get();
    if (!workerDoc.exists) throw new NotFoundError('Worker not found');
    const worker = workerDoc.data();
    const tasksSnapshot = await db.collection('cleaningTasks').where('workerId', '==', workerId).where('scheduledDate', '==', targetDate).get();
    const tasks = tasksSnapshot.docs.map(d => d.data());
    const total = tasks.length;
    const completed = tasks.filter(t => t.status === 'completed' || t.status === 'approved').length;
    const inProgress = tasks.filter(t => t.status === 'in_progress').length;
    const pending = tasks.filter(t => t.status === 'pending').length;
    const approved = tasks.filter(t => t.status === 'approved').length;
    const rejected = tasks.filter(t => t.status === 'rejected').length;
    const avgScore = total > 0 ? Math.round(tasks.reduce((s, t) => s + this._taskScore(t), 0) / total) : 0;
    return {
      workerId, workerName: worker.fullName || '',
      date: targetDate, totalTasks: total,
      completedTasks: completed, inProgressTasks: inProgress,
      pendingTasks: pending, approvedTasks: approved,
      rejectedTasks: rejected, averageScore: avgScore, tasks
    };
  }

  _gradeFromScore(score) {
    const s = Number(score) || 0;
    return s >= 90 ? 'A' : s >= 75 ? 'B' : s >= 60 ? 'C' : 'D';
  }

  _taskScore(t) {
    const s = Number(t.score);
    if (Number.isFinite(s) && s > 0) return s;
    const ts = Number(t.totalScore);
    return Number.isFinite(ts) && ts > 0 ? ts : 0;
  }

  async getSupervisorDashboard(supervisorId, query = {}, user) {
    const { date } = query;
    const targetDate = date || new Date().toISOString().split('T')[0];
    const supDoc = await db.collection('users').doc(supervisorId).get();
    if (!supDoc.exists) throw new NotFoundError('Supervisor not found');
    const supervisor = supDoc.data();
    if (user && !this._isMasterOrAdmin(user)) {
      const userStations = user?.stations || (user?.stationId ? [user.stationId] : []);
      const supStations = supervisor.stations?.length ? supervisor.stations : supervisor.stationId ? [supervisor.stationId] : [];
      const overlap = supStations.filter(s => userStations.includes(s));
      if (overlap.length === 0 && (user.uid !== supervisorId || userStations.length === 0)) {
        throw new ForbiddenError('You can only access data for your assigned stations');
      }
    }
    const stationIds = supervisor.stations && supervisor.stations.length > 0
      ? supervisor.stations
      : supervisor.stationId ? [supervisor.stationId] : [];
    let tasks = [];
    if (stationIds.length > 0) {
      const s = await db.collection('cleaningTasks')
        .where('supervisorId', '==', supervisorId)
        .where('scheduledDate', '==', targetDate)
        .get();
      tasks = s.docs.map(d => d.data()).filter(t => stationIds.includes(t.stationId));
    }
    const total = tasks.length;
    const completed = tasks.filter(t => t.status === 'completed' || t.status === 'approved').length;
    const inProgress = tasks.filter(t => t.status === 'in_progress').length;
    const pending = tasks.filter(t => t.status === 'pending').length;
    const approved = tasks.filter(t => t.status === 'approved').length;
    const rejected = tasks.filter(t => t.status === 'rejected').length;
    const now = new Date();
    const overdue = tasks.filter(t => {
      const actionableStatuses = ['pending', 'assigned', 'in_progress'];
      if (!actionableStatuses.includes(t.status)) return false;
      const taskDate = t.date || t.scheduledDate || '';
      const taskTime = t.scheduledTime || '23:59';
      return new Date(`${taskDate}T${taskTime}:00`) < now;
    }).length;

    // Fetch workers count for this supervisor
    let workerPerformance = [];
    try {
      const workersSnap = await db.collection('supervisorWorkers')
        .where('supervisorId', '==', supervisorId)
        .where('isActive', '==', true)
        .limit(300)
        .get();
      workerPerformance = workersSnap.docs.map(d => ({ uid: d.id, fullName: d.data().fullName || '' }));
    } catch (e) {
      console.error('Error fetching supervisor workers:', e.message);
    }

    const avgScore = total > 0 ? Math.round(tasks.reduce((s, t) => s + this._taskScore(t), 0) / total) : 0;
    const gradedTasks = tasks.filter(t => this._taskScore(t) > 0);
    const gradedAvg = gradedTasks.length > 0 ? Math.round(gradedTasks.reduce((s, t) => s + this._taskScore(t), 0) / gradedTasks.length) : 0;

    // Per-area score snapshot so the supervisor can see the latest grade for
    // each area they cleaned today (frontend renders `areaPerformance`).
    const areaMap = {};
    for (const t of tasks) {
      const areaId = t.areaId || t.areaName || 'Unknown';
      if (!areaMap[areaId]) areaMap[areaId] = { areaId, areaName: t.areaName || areaId, total: 0, completed: 0 };
      areaMap[areaId].total += 1;
      const st = t.status || '';
      if (st === 'completed' || st === 'approved') {
        areaMap[areaId].completed += 1;
        areaMap[areaId].score = Math.max(areaMap[areaId].score || 0, this._taskScore(t));
      }
    }
    const areaPerformance = Object.values(areaMap);

    return {
      supervisorId, supervisorName: supervisor.fullName || '',
      date: targetDate, totalTasks: total,
      completedTasks: completed, inProgressTasks: inProgress,
      pendingTasks: pending, approvedTasks: approved, rejectedTasks: rejected,
      overdueTasks: overdue,
      averageScore: gradedAvg || avgScore,
      grade: this._gradeFromScore(gradedAvg || avgScore),
      areaPerformance,
      workerPerformance
    };
  }

  // Aggregated dashboard for contractor admins: today's auto-generated tasks
  // across the station plus every supervisor with their own task counts and
  // shift assignment. Administrators see supervisors (not workers) here.
  async getAdminDashboard(stationId, query = {}, user) {
    const resolvedStationId = this._resolveStationId(stationId, user);
    this._verifyStationAccessForStationId(resolvedStationId, user);
    const { date } = query;
    const targetDate = date || new Date().toISOString().split('T')[0];

    const stationDoc = await db.collection('stations').doc(resolvedStationId).get();
    const station = stationDoc.exists ? stationDoc.data() : {};

    const snapshot = await db.collection('cleaningTasks')
      .where('stationId', '==', resolvedStationId)
      .where('scheduledDate', '==', targetDate)
      .get();
    const tasks = snapshot.docs.map((d) => ({ id: d.id, ...d.data() }));

    const total = tasks.length;
    const completed = tasks.filter((t) => t.status === 'completed' || t.status === 'approved').length;
    const inProgress = tasks.filter((t) => t.status === 'in_progress').length;
    const pending = tasks.filter((t) => t.status === 'pending').length;
    const approved = tasks.filter((t) => t.status === 'approved').length;
    const rejected = tasks.filter((t) => t.status === 'rejected').length;
    const now = new Date();
    const overdue = tasks.filter((t) => {
      const actionableStatuses = ['pending', 'assigned', 'in_progress'];
      if (!actionableStatuses.includes(t.status)) return false;
      const taskDate = t.date || t.scheduledDate || '';
      const taskTime = t.scheduledTime || '23:59';
      return new Date(`${taskDate}T${taskTime}:00`) < now;
    }).length;
    const avgScore = total > 0
      ? Math.round(tasks.reduce((s, t) => s + this._taskScore(t), 0) / total)
      : 0;

    // Group task counts per supervisor for the day
    const perSupervisor = {};
    for (const t of tasks) {
      if (!t.supervisorId) continue;
      const key = t.supervisorId;
      if (!perSupervisor[key]) {
        perSupervisor[key] = {
          supervisorId: key, totalTasks: 0, completedTasks: 0,
          inProgressTasks: 0, pendingTasks: 0, approvedTasks: 0, rejectedTasks: 0,
        };
      }
      const row = perSupervisor[key];
      row.totalTasks += 1;
      if (t.status === 'completed' || t.status === 'approved') row.completedTasks += 1;
      if (t.status === 'in_progress') row.inProgressTasks += 1;
      if (t.status === 'pending') row.pendingTasks += 1;
      if (t.status === 'approved') row.approvedTasks += 1;
      if (t.status === 'rejected') row.rejectedTasks += 1;
    }

    // Enrich with supervisor profile and shift assignment
    const contract = await this._getActiveStationCleaningContract(resolvedStationId);
    let supervisors = [];
    if (contract) {
      const supSnap = await db.collection('users')
        .where('contractId', '==', contract.uid)
        .where('status', '==', 'APPROVED')
        .limit(200)
        .get();
      const list = [];
      for (const doc of supSnap.docs) {
        const d = doc.data();
        const role = String(d.role || '').toUpperCase().replace(/\s+/g, '_');
        if (role !== 'CONTRACTOR_SUPERVISOR') continue;
        const userStations = d.stations || [];
        if (!userStations.includes(resolvedStationId)) continue;
        const uid = doc.id;
        const shiftDoc = await db.collection('stationSupervisorShifts').doc(uid).get();
        const summary = perSupervisor[uid] || {
          supervisorId: uid, totalTasks: 0, completedTasks: 0,
          inProgressTasks: 0, pendingTasks: 0, approvedTasks: 0, rejectedTasks: 0,
        };
        list.push({
          uid,
          fullName: d.fullName || '',
          email: d.email || '',
          mobile: d.mobile || '',
          shift: shiftDoc.exists && shiftDoc.data().shift ? String(shiftDoc.data().shift).toLowerCase() : null,
          ...summary,
        });
      }
      list.sort((a, b) => (a.fullName || '').localeCompare(b.fullName || ''));
      supervisors = list;
    }

    return {
      stationId: resolvedStationId,
      stationName: station.stationName || '',
      date: targetDate,
      totalTasks: total,
      completedTasks: completed,
      inProgressTasks: inProgress,
      pendingTasks: pending,
      approvedTasks: approved,
      rejectedTasks: rejected,
      overdueTasks: overdue,
      averageScore: avgScore,
      grade: this._gradeFromScore(avgScore),
      supervisorCount: supervisors.length,
      supervisors,
    };
  }

  _verifyStationAccessForStationId(stationId, user) {
    if (this._isMasterOrAdmin(user)) return;
    const userStations = user?.stations || (user?.stationId ? [user.stationId] : []);
    if (userStations.length > 0 && !userStations.includes(stationId)) {
      throw new ForbiddenError('You can only access data for your assigned stations');
    }
  }

  async generateDailyReport(stationId, query = {}, user) {
    const { date } = query;
    const targetDate = date || new Date().toISOString().split('T')[0];
    this._verifyStationAccessForStationId(stationId, user);
    const stationDoc = await db.collection('stations').doc(stationId).get();
    if (!stationDoc.exists) throw new NotFoundError('Station not found');
    const station = stationDoc.data();
    const snapshot = await db.collection('cleaningTasks').where('stationId', '==', stationId).where('scheduledDate', '==', targetDate).get();
    const tasks = snapshot.docs.map(d => d.data());
    const total = tasks.length;
    const completed = tasks.filter(t => t.status === 'completed' || t.status === 'approved').length;
    const avgScore = total > 0 ? Math.round(tasks.reduce((s, t) => s + this._taskScore(t), 0) / total) : 0;
    return {
      stationId, stationName: station.stationName || '',
      date: targetDate, totalTasks: total, completedTasks: completed,
      averageScore: avgScore,
      grade: this._gradeFromScore(avgScore),
      generatedAt: new Date().toISOString()
    };
  }

  async generateWeeklyReport(stationId, query = {}, user) {
    const { endDate } = query;
    const end = endDate || new Date().toISOString().split('T')[0];
    const start = new Date(end); start.setDate(start.getDate() - 6);
    const startStr = start.toISOString().split('T')[0];
    this._verifyStationAccessForStationId(stationId, user);
    const stationDoc = await db.collection('stations').doc(stationId).get();
    if (!stationDoc.exists) throw new NotFoundError('Station not found');
    const station = stationDoc.data();
    const snapshot = await db.collection('cleaningTasks')
      .where('stationId', '==', stationId)
      .get();
    const tasks = snapshot.docs
      .map(d => d.data())
      .filter(t => {
        const d = t.scheduledDate || t.date || '';
        return d >= startStr && d <= end;
      });
    const total = tasks.length;
    const completed = tasks.filter(t => t.status === 'completed' || t.status === 'approved').length;
    const avgScore = total > 0 ? Math.round(tasks.reduce((s, t) => s + this._taskScore(t), 0) / total) : 0;
    return {
      stationId, stationName: station.stationName || '',
      startDate: startStr, endDate: end, totalTasks: total, completedTasks: completed,
      completionRate: total > 0 ? Math.round(completed / total * 100) : 0,
      averageScore: avgScore, grade: this._gradeFromScore(avgScore),
      generatedAt: new Date().toISOString()
    };
  }

  async generateMonthlyReport(stationId, query = {}, user) {
    const { month, year } = query;
    const now = new Date();
    const m = month !== undefined ? parseInt(month) : now.getMonth() + 1;
    const y = year !== undefined ? parseInt(year) : now.getFullYear();
    const startStr = `${y}-${String(m).padStart(2, '0')}-01`;
    const lastDay = new Date(y, m, 0).getDate();
    const endStr = `${y}-${String(m).padStart(2, '0')}-${String(lastDay).padStart(2, '0')}`;
    this._verifyStationAccessForStationId(stationId, user);
    const stationDoc = await db.collection('stations').doc(stationId).get();
    if (!stationDoc.exists) throw new NotFoundError('Station not found');
    const station = stationDoc.data();
    const snapshot = await db.collection('cleaningTasks')
      .where('stationId', '==', stationId)
      .get();
    const tasks = snapshot.docs
      .map(d => d.data())
      .filter(t => {
        const d = t.scheduledDate || t.date || '';
        return d >= startStr && d <= endStr;
      });
    const total = tasks.length;
    const completed = tasks.filter(t => t.status === 'completed' || t.status === 'approved').length;
    const avgScore = total > 0 ? Math.round(tasks.reduce((s, t) => s + this._taskScore(t), 0) / total) : 0;
    return {
      stationId, stationName: station.stationName || '',
      month: m, year: y, period: `${startStr} to ${endStr}`,
      totalTasks: total, completedTasks: completed,
      completionRate: total > 0 ? Math.round(completed / total * 100) : 0,
      averageScore: avgScore, grade: this._gradeFromScore(avgScore),
      generatedAt: new Date().toISOString()
    };
  }

  async getScoreTrend(stationId, query = {}, user) {
    const { months } = query;
    this._verifyStationAccessForStationId(stationId, user);
    const numMonths = months ? parseInt(months) : 6;
    const now = new Date();
    const data = [];
    for (let i = numMonths - 1; i >= 0; i--) {
      const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
      const m = d.getMonth() + 1;
      const y = d.getFullYear();
      const startStr = `${y}-${String(m).padStart(2, '0')}-01`;
      const lastDay = new Date(y, m, 0).getDate();
      const endStr = `${y}-${String(m).padStart(2, '0')}-${String(lastDay).padStart(2, '0')}`;
      const snapshot = await db.collection('cleaningTasks')
        .where('stationId', '==', stationId)
        .get();
      const tasks = snapshot.docs
        .map(d => d.data())
        .filter(t => {
          const d = t.scheduledDate || t.date || '';
          return d >= startStr && d <= endStr;
        });
      const withScore = tasks.filter(t => t.score);
      const avgScore = withScore.length > 0 ? Math.round(withScore.reduce((s, t) => s + this._taskScore(t), 0) / withScore.length) : 0;
      data.push({ month: m, year: y, label: `${y}-${String(m).padStart(2, '0')}`, averageScore: avgScore, taskCount: tasks.length });
    }
    return { stationId, trend: data };
  }

  // ─── Daily Log ──────────────────────────────────────────────────────────────

  async submitDailyLog(body, user) {
    const { activitiesSummary, machineUsage, issuesEncountered, handoverNotes } = body;
    if (!activitiesSummary) {
      throw new Error('Activities summary is required');
    }

    const logData = {
      supervisorId: user.uid,
      supervisorName: user.name || 'Unknown',
      contractId: user.contractId || null,
      stationId: user.stationId || null,
      date: new Date().toISOString().split('T')[0],
      activitiesSummary,
      machineUsage: machineUsage || '',
      issuesEncountered: issuesEncountered || '',
      handoverNotes: handoverNotes || '',
      createdAt: new Date().toISOString(),
      status: 'SUBMITTED'
    };

    const ref = await db.collection('stationDailyLogs').add(logData);
    return { id: ref.id, ...logData };
  }

  // ─── Supervisor Workers CRUD ───────────────────────────────────────────────
  async createWorker(body, user) {
    const { fullName, phone, employeePhotoUrl, aadhaarNumber, aadhaarPhotoUrl, panNumber, panPhotoUrl, pfUanNumber, pfDocumentUrl, policeVerificationNumber, policeVerificationDocUrl, stationId } = body;
    if (!fullName || !phone) throw new ValidationError('fullName and phone are required');
    if (!/^\d{10}$/.test(String(phone).trim())) throw new ValidationError('Invalid mobile number. Must be 10 digits.');
    if (!aadhaarNumber || !/^\d{12}$/.test(String(aadhaarNumber).trim())) throw new ValidationError('Aadhaar number is required and must be 12 digits.');
    if (!employeePhotoUrl || !String(employeePhotoUrl).trim()) throw new ValidationError('Employee identity photo is required');
    const phoneQuery = await db.collection('supervisorWorkers').where('phone', '==', phone).limit(1).get();
    if (!phoneQuery.empty) throw new ValidationError('Mobile Number already registered.');
    const aadhaarQuery = await db.collection('supervisorWorkers').where('aadhaarNumber', '==', aadhaarNumber).limit(1).get();
    if (!aadhaarQuery.empty) throw new ValidationError('Aadhaar Number already registered.');
    const ref = db.collection('supervisorWorkers').doc();
    const data = {
      uid: ref.id,
      supervisorId: user.uid,
      supervisorName: user.name || user.fullName || 'Unknown',
      fullName, phone,
      employeePhotoUrl: employeePhotoUrl || '',
      aadhaarNumber: aadhaarNumber || '',
      aadhaarPhotoUrl: aadhaarPhotoUrl || '',
      panNumber: panNumber || '',
      panPhotoUrl: panPhotoUrl || '',
      pfUanNumber: pfUanNumber || '',
      pfDocumentUrl: pfDocumentUrl || '',
      policeVerificationNumber: policeVerificationNumber || '',
      policeVerificationDocUrl: policeVerificationDocUrl || '',
      stationId: stationId || user.stationId || '',
      contractId: user.contractId || '',
      isActive: true,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
    await ref.set(data);
    return { message: 'Worker created', uid: ref.id, data };
  }

  async updateWorker(uid, body, user) {
    const ref = db.collection('supervisorWorkers').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Worker not found');
    const worker = doc.data();
    if (worker.supervisorId !== user.uid && !this._isMasterOrAdmin(user)) {
      throw new ForbiddenError('You can only update your own workers');
    }
    const updates = { ...body, updatedAt: new Date().toISOString() };
    delete updates.uid;
    delete updates.supervisorId;
    if (updates.phone !== undefined && updates.phone !== '') {
      if (!/^\d{10}$/.test(String(updates.phone).trim())) throw new ValidationError('Invalid mobile number. Must be 10 digits.');
      const phoneQuery = await db.collection('supervisorWorkers').where('phone', '==', updates.phone).limit(1).get();
      if (!phoneQuery.empty && phoneQuery.docs[0].id !== uid) throw new ValidationError('Mobile Number already registered.');
    }
    if (updates.aadhaarNumber !== undefined && updates.aadhaarNumber !== '') {
      if (!/^\d{12}$/.test(String(updates.aadhaarNumber).trim())) throw new ValidationError('Aadhaar number must be 12 digits.');
      const aadhaarQuery = await db.collection('supervisorWorkers').where('aadhaarNumber', '==', updates.aadhaarNumber).limit(1).get();
      if (!aadhaarQuery.empty && aadhaarQuery.docs[0].id !== uid) throw new ValidationError('Aadhaar Number already registered.');
    }
    await ref.update(updates);
    return { message: 'Worker updated', uid };
  }

  async deleteWorker(uid, user) {
    const ref = db.collection('supervisorWorkers').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Worker not found');
    const worker = doc.data();
    if (worker.supervisorId !== user.uid && !this._isMasterOrAdmin(user)) {
      throw new ForbiddenError('You can only delete your own workers');
    }
    await ref.update({ isActive: false, updatedAt: new Date().toISOString() });
    return { message: 'Worker deactivated', uid };
  }

  async listWorkers(query, user) {
    let q = db.collection('supervisorWorkers').where('isActive', '==', true);
    const role = (user?.role || '').toUpperCase().replace(/\s+/g, '_');
    const isContractorSupervisor = role === 'CONTRACTOR_SUPERVISOR';
    if (isContractorSupervisor) {
      q = q.where('supervisorId', '==', user.uid);
    } else if (user.contractId) {
      q = q.where('contractId', '==', user.contractId);
    }
    if (query.stationId) q = q.where('stationId', '==', query.stationId);
    if (query.supervisorId) q = q.where('supervisorId', '==', query.supervisorId);
    const snapshot = await q.limit(200).get();
    const workers = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
    return { count: workers.length, workers };
  }

  async getWorker(uid) {
    const doc = await db.collection('supervisorWorkers').doc(uid).get();
    if (!doc.exists) throw new NotFoundError('Worker not found');
    return { id: doc.id, ...doc.data() };
  }

  // ─── Supervisor Shift Assignment (station-cleaning only) ──────────────────
  // The active station-cleaning contract for a station, or null when there is
  // none. This is what keeps the whole feature isolated: supervisors are only
  // ever listed/assigned under this exact contract.
  async _getActiveStationCleaningContract(stationId) {
    if (!stationId) return null;
    const snap = await db.collection('contracts')
      .where('contractType', '==', 'station_cleaning')
      .where('stationIds', 'array-contains', stationId)
      .limit(10)
      .get();
    if (snap.empty) return null;
    const active = snap.docs.find(d => {
      const s = String(d.data().status || '').toLowerCase();
      return s === 'active' || s === 'approved' || s === 'running' || s === 'ongoing' || s === '';
    });
    if (!active) return null;
    const d = active.data();
    return { uid: active.id, entityId: d.entityId || '', contractType: d.contractType };
  }

  // Contract-cleaning supervisors for a station belonging to the station-cleaning
  // contract, each enriched with their assigned shift (defaults 'morning').
  async getSupervisorShifts(stationIdParam, user) {
    const stationId = this._resolveStationId(stationIdParam, user);
    const contract = await this._getActiveStationCleaningContract(stationId);
    if (!contract) return { count: 0, contractId: null, supervisors: [] };

    let q = db.collection('users')
      .where('contractId', '==', contract.uid)
      .where('status', '==', 'APPROVED')
      .limit(200);
    const snapshot = await q.get();
    const supervisors = [];
    for (const doc of snapshot.docs) {
      const d = doc.data();
      const role = String(d.role || '').toUpperCase().replace(/\s+/g, '_');
      if (role !== 'CONTRACTOR_SUPERVISOR') continue;
      const userStations = d.stations || [];
      if (!userStations.includes(stationId)) continue;
      const uid = doc.id;
      const shiftDoc = await db.collection('stationSupervisorShifts').doc(uid).get();
      const shift = shiftDoc.exists && shiftDoc.data().shift
        ? String(shiftDoc.data().shift).toLowerCase()
        : null;
      supervisors.push({
        uid,
        fullName: d.fullName || '',
        email: d.email || '',
        mobile: d.mobile || '',
        stations: userStations,
        contractId: contract.uid,
        contractType: 'station_cleaning',
        shift,
      });
    }
    supervisors.sort((a, b) => (a.fullName || '').localeCompare(b.fullName || ''));
    return { count: supervisors.length, contractId: contract.uid, supervisors };
  }

  // Persist a supervisor's shift for the station-cleaning contract. Assigning
  // 'none' clears the assignment. Validated against the live contract so other
  // contracts can never be (mis)configured through this endpoint.
  async assignSupervisorShift(supervisorId, body, user) {
    const stationId = this._resolveStationId(body?.stationId, user);
    if (!supervisorId) throw new ValidationError('supervisorId is required');
    if (!stationId) throw new ValidationError('stationId is required');

    const shift = body?.shift ? String(body.shift).trim().toLowerCase() : 'none';
    if (!['morning', 'evening', 'night', 'none'].includes(shift)) {
      throw new ValidationError('shift must be one of: morning, evening, night, none');
    }

    const contract = await this._getActiveStationCleaningContract(stationId);
    if (!contract) throw new NotFoundError('No active station-cleaning contract for this station');

    const supDoc = await db.collection('users').doc(supervisorId).get();
    if (!supDoc.exists) throw new NotFoundError('Supervisor not found');
    const supData = supDoc.data();
    const role = String(supData.role || '').toUpperCase().replace(/\s+/g, '_');
    if (role !== 'CONTRACTOR_SUPERVISOR') throw new ValidationError('User is not a contractor supervisor');
    if (String(supData.status || '').toUpperCase() !== 'APPROVED') {
      throw new ValidationError('Only approved supervisors can be assigned a shift');
    }
    if (supData.contractId !== contract.uid) {
      throw new ValidationError('Supervisor does not belong to this station-cleaning contract');
    }
    const userStations = supData.stations || [];
    if (!userStations.includes(stationId)) {
      throw new ValidationError('Supervisor is not assigned to this station');
    }

    const ref = db.collection('stationSupervisorShifts').doc(supervisorId);

    // Read the current shift before overwriting so we can migrate tasks if it changes.
    let oldShift = null;
    try {
      const existingDoc = await ref.get();
      if (existingDoc.exists) {
        const existingData = existingDoc.data();
        oldShift = existingData.shift ? String(existingData.shift).trim().toLowerCase() : null;
      }
    } catch (_) {}

    if (shift === 'none') {
      await ref.delete();
    } else {
      await ref.set({
        shift,
        stationId,
        contractId: contract.uid,
        supervisorName: supData.fullName || '',
        updatedAt: new Date().toISOString(),
      }, { merge: true });
    }
    if (shift !== 'none') {
      await this._ensureShiftSchedule(stationId, shift, contract.uid, supervisorId, supData.fullName || '');
    }

    // If the shift actually changed, migrate today's pending tasks from the old
    // shift-holder to the supervisor now holding the old shift window so tasks
    // remain visible to the correct person.
    if (oldShift && oldShift !== shift && shift !== 'none') {
      try {
        await this._migrateShiftTasksOnReassign(supervisorId, stationId, oldShift);
      } catch (err) {
        console.error('[assignSupervisorShift] task migration failed:', err.message);
      }
    }

    return { uid: supervisorId, shift: shift === 'none' ? null : shift, stationId };
  }

  // After a supervisor is moved to a different shift, reassign that supervisor's
  // today tasks (still pending/assigned/in_progress) that belong to the OLD
  // shift window to the supervisor(s) now holding that window. Keeps the rule
  // 'supervisor only sees tasks of their own shift' from hiding their tasks.
  // When several supervisors share the old shift, tasks are distributed evenly
  // so a single holder does not end up with everything.
  async _migrateShiftTasksOnReassign(supervisorId, stationId, oldShift) {
    const todayIST = getISTDate();

    // Candidates currently holding the old shift at this station (excluding the
    // supervisor being reassigned). If none, the old window is unstaffed for now
    // and there is no valid destination to move tasks to.
    const candidates = [];
    try {
      const shiftSnap = await db.collection('stationSupervisorShifts')
        .where('stationId', '==', stationId).get();
      shiftSnap.forEach(doc => {
        const d = doc.data();
        const s = d.shift ? String(d.shift).trim().toLowerCase() : '';
        if (doc.id !== supervisorId && s === oldShift) {
          candidates.push({ uid: doc.id, fullName: d.supervisorName || '' });
        }
      });
    } catch (_) {}
    if (candidates.length === 0) return 0;

    const terminal = new Set(['completed', 'approved', 'rejected']);
    const toMigrate = [];
    const taskSnap = await db.collection('cleaningTasks')
      .where('supervisorId', '==', supervisorId).get();
    taskSnap.forEach(doc => {
      const t = doc.data();
      const taskDate = t.date || t.scheduledDate || '';
      const taskShift = t.shift ? String(t.shift).trim().toLowerCase() : '';
      if (taskDate === todayIST && taskShift === oldShift && !terminal.has(t.status || '')) {
        toMigrate.push(doc);
      }
    });
    if (toMigrate.length === 0) return 0;

    const batch = db.batch();
    toMigrate.forEach((doc, i) => {
      const target = candidates[i % candidates.length];
      batch.update(doc.ref, {
        supervisorId: target.uid,
        supervisorName: target.fullName,
      });
    });
    await batch.commit();
    console.log(`[assignSupervisorShift] migrated ${toMigrate.length} ${oldShift} tasks from ${supervisorId} to ${candidates.length} holder(s)`);
    return toMigrate.length;
  }

  // Guarantees a default schedule exists for a station+shift window so the
  // daily / refresh crons produce tasks for the supervisor assigned to that
  // shift. Skips when one already exists; idempotent by (stationId, shift).
  async _ensureShiftSchedule(stationId, shift, contractId, supervisorId, supervisorName) {
    const s = String(shift || '').trim().toLowerCase();
    if (!['morning', 'evening', 'night'].includes(s)) return null;
    const existing = await db.collection('stationSchedules')
      .where('stationId', '==', stationId)
      .where('status', '==', 'active').get();
    for (const doc of existing.docs) {
      const d = doc.data();
      if (String(d.shift || d.shiftType || '').trim().toLowerCase() === s) {
        return null;
      }
    }
    const windows = { morning: ['06:00', '14:00'], evening: ['14:00', '22:00'], night: ['20:00', '04:00'] };
    const [startTime, endTime] = windows[s] || ['06:00', '14:00'];
    const ref = db.collection('stationSchedules').doc();
    const data = {
      uid: ref.id,
      stationId,
      scheduleName: `Default ${s.charAt(0).toUpperCase() + s.slice(1)} Shift`,
      areaId: '',
      zoneId: '',
      frequency: 'daily',
      shift: s,
      shiftType: s,
      entityId: '',
      entityName: 'Station Cleaning',
      supervisorId: supervisorId || '',
      supervisorName: supervisorName || '',
      startTime,
      endTime,
      daysOfWeek: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      estimatedHours: null,
      effectiveFrom: getISTDate(),
      effectiveTo: null,
      status: 'active',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    await ref.set(data);
    logger.info('StationCleaning', `Auto-created default ${s} shift schedule ${ref.id} for station ${stationId}`);
    return data;
  }

  // Reconciles default shift schedules for every station that has supervisors
  // recorded. Idempotent — used at boot/cron so any newly-assigned shift
  // (morning/evening/night) immediately gets a schedule + daily tasks.
  async ensureShiftSchedulesForAllStations() {
    const snaps = await db.collection('stationSupervisorShifts').get();
    const handled = new Map();
    let created = 0;
    for (const doc of snaps.docs) {
      const d = doc.data();
      const stationId = d.stationId;
      const shift = String(d.shift || '').trim().toLowerCase();
      if (!stationId || !['morning', 'evening', 'night'].includes(shift)) continue;
      const key = `${stationId}|${shift}`;
      if (handled.has(key)) continue;
      handled.set(key, true);
      const result = await this._ensureShiftSchedule(
        stationId, shift, d.contractId || '', doc.id, d.supervisorName || ''
      );
      if (result) created++;
    }
    if (created > 0) {
      logger.info('StationCleaning', `Ensured ${created} default shift schedule(s) from recorded supervisor shifts`);
    }
    return { created };
  }

  // ─── Cleaning Submissions CRUD ─────────────────────────────────────────────
  async createSubmission(body, user) {
    const { stationId, stationName, areaId, areaName, taskTypeId, taskTypeName, beforePhotoUrl, afterPhotoUrl, notes } = body;
    if (!stationId || !areaId || !beforePhotoUrl || !afterPhotoUrl) {
      throw new ValidationError('stationId, areaId, beforePhotoUrl, and afterPhotoUrl are required');
    }
    if (!user.stationId && !stationId) throw new ValidationError('stationId is required');
    const resolvedStationId = this._resolveStationId(stationId, user);
    const ref = db.collection('cleaningSubmissions').doc();
    const data = {
      uid: ref.id,
      stationId: resolvedStationId,
      stationName: stationName || '',
      areaId, areaName: areaName || '',
      taskTypeId: taskTypeId || '',
      taskTypeName: taskTypeName || '',
      beforePhotoUrl, afterPhotoUrl,
      notes: notes || '',
      supervisorId: user.uid,
      supervisorName: user.name || user.fullName || 'Unknown',
      contractId: user.contractId || '',
      submittedAt: new Date().toISOString(),
      status: 'pending',
      reviewedBy: null,
      reviewedAt: null,
      rejectionReason: null
    };
    await ref.set(data);
    return { message: 'Submission created', uid: ref.id, data };
  }

  async listMySubmissions(query, user) {
    let q = db.collection('cleaningSubmissions')
      .where('supervisorId', '==', user.uid)
      .orderBy('submittedAt', 'desc');
    if (query.date) {
      const start = query.date + 'T00:00:00.000Z';
      const end = query.date + 'T23:59:59.999Z';
      q = q.where('submittedAt', '>=', start).where('submittedAt', '<=', end);
    }
    const snapshot = await q.limit(100).get();
    const submissions = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
    return { count: submissions.length, submissions };
  }

  async listAllSubmissions(query, user) {
    let q = db.collection('cleaningSubmissions');
    if (query.stationId) q = q.where('stationId', '==', query.stationId);
    if (query.status) q = q.where('status', '==', query.status);
    if (query.supervisorId) q = q.where('supervisorId', '==', query.supervisorId);
    if (user.contractId) q = q.where('contractId', '==', user.contractId);
    q = q.orderBy('submittedAt', 'desc');
    const snapshot = await q.limit(200).get();
    const submissions = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
    return { count: submissions.length, submissions };
  }

  async reviewSubmission(uid, body, user) {
    const ref = db.collection('cleaningSubmissions').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Submission not found');
    const { status, rejectionReason } = body;
    if (!['approved', 'rejected'].includes(status)) throw new ValidationError('status must be approved or rejected');
    await ref.update({
      status,
      rejectionReason: rejectionReason || null,
      reviewedBy: user.uid,
      reviewedAt: new Date().toISOString()
    });
    return { message: `Submission ${status}`, uid };
  }

  // ─── Execution Plan with Supervisor Assignments ────────────────────────────
  async createExecutionPlanWithAssignments(body, user) {
    const { contractId, stationId, month, year, shiftPlan, machinePlan, materialPlan, garbageDisposalPlan, weeklySchedule } = body;
    if (!contractId || !stationId || !shiftPlan) throw new ValidationError('contractId, stationId, and shiftPlan are required');
    const ref = db.collection('executionPlans').doc();
    const data = {
      uid: ref.id, contractId, stationId,
      month: month || new Date().getMonth() + 1,
      year: year || new Date().getFullYear(),
      shiftPlan: typeof shiftPlan === 'object' ? shiftPlan : {},
      manpowerPlan: body.manpowerPlan || {},
      machinePlan: machinePlan || {},
      materialPlan: materialPlan || [],
      garbageDisposalPlan: garbageDisposalPlan || {},
      weeklySchedule: weeklySchedule || [],
      status: 'DRAFT',
      version: 1,
      createdBy: user.uid,
      createdByName: user.name || user.fullName || 'Unknown',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
    await ref.set(data);
    return { message: 'Execution plan created', uid: ref.id, data };
  }

  _validateSummaryAreas(areas) {
    if (!Array.isArray(areas) || areas.length < 1) {
      throw new ValidationError(`At least 1 area must be submitted for the shift summary. Received ${Array.isArray(areas) ? areas.length : 0}.`);
    }
    const hasPhoto = (a) => {
      if (a.photoUrl && String(a.photoUrl).trim()) return true;
      return Array.isArray(a.photoUrls) && a.photoUrls.some(u => u && String(u).trim());
    };
    const photoCount = areas.filter(hasPhoto).length;
    const requiredPhotos = areas.length > 5 ? 5 : areas.length;
    if (photoCount < requiredPhotos) {
      if (areas.length > 5) {
        throw new ValidationError(`At least 5 photos are required to submit the shift summary when more than 5 tasks are submitted. Photos uploaded: ${photoCount}/5.`);
      }
      throw new ValidationError(`Photos are required for every area worked. Please add photos for all ${areas.length} area(s). Photos uploaded: ${photoCount}/${areas.length}.`);
    }
    for (const a of areas) {
      const hasAreaPhoto = hasPhoto(a);
      if (!String(a.remark || '').trim()) {
        throw new ValidationError(`Remark is required for area ${a.areaName || a.areaId || ''}`);
      }
      if (hasAreaPhoto && (a.latitude === undefined || a.latitude === null || a.longitude === undefined || a.longitude === null)) {
        throw new ValidationError(`Live location (latitude/longitude) is required for area ${a.areaName || a.areaId || ''}`);
      }
    }
  }

  // A task is MISSED when its 1-hour start window (scheduledTime <= now <
  // scheduledTime + 1h) has elapsed without it ever being started. Missed
  // tasks are legitimately unworked and never block the shift summary.
  _isTaskMissed(task) {
    const status = String(task.status || '').toLowerCase();
    if (!['pending', 'assigned', ''].includes(status)) return false;
    const scheduledDate = task.scheduledDate || task.date || '';
    const scheduledTime = task.scheduledTime || '';
    if (!scheduledDate || !scheduledTime) return false;
    const dateMatch = /^(\d{4})-(\d{2})-(\d{2})$/.exec(scheduledDate);
    const timeMatch = /^(\d{2}):(\d{2})$/.exec(scheduledTime);
    if (!dateMatch || !timeMatch) return false;
    const [, y, mo, d] = dateMatch.map(Number);
    const [, hh, mm] = timeMatch.map(Number);
    const scheduledIST = new Date(Date.UTC(y, mo - 1, d, hh, mm, 0));
    const nowIST = Date.now() + 5.5 * 60 * 60 * 1000;
    return nowIST >= scheduledIST.getTime() + 60 * 60 * 1000;
  }

  // Only actionable tasks (pending / in progress / rejected / resubmitted)
  // block the shift summary submission. Terminal tasks (completed / approved /
  // cancelled) and MISSED tasks (start window elapsed, never started) never
  // block.
  async _assertAllTasksTerminal(supervisorId, stationId, date, resolvedShift) {
    const incompleteTasks = [];
    const taskSnap = await db.collection('cleaningTasks')
      .where('supervisorId', '==', supervisorId)
      .get();
    taskSnap.forEach(doc => {
      const t = doc.data();
      const taskDate = t.date || t.scheduledDate || '';
      if (taskDate !== String(date)) return;
      if (stationId && t.stationId && t.stationId !== stationId) return;
      const taskShift = t.shift ? String(t.shift).trim().toLowerCase() : '';
      if (taskShift && resolvedShift && taskShift !== resolvedShift) return;
      if (!taskShift && resolvedShift && resolvedShift !== 'morning') return;
      const status = String(t.status || '').toLowerCase();
      if (['completed', 'approved', 'cancelled', 'missed'].includes(status)) return;
      if (this._isTaskMissed(t)) return;
      incompleteTasks.push({ areaName: t.areaName || 'Unknown area', scheduledTime: t.scheduledTime || '', status });
    });
    if (incompleteTasks.length > 0) {
      const uniqAreas = [...new Set(incompleteTasks.map(x => x.areaName))].slice(0, 10);
      const extra = incompleteTasks.length > uniqAreas.length ? `, ... (${incompleteTasks.length} total)` : '';
      const noun = incompleteTasks.length === 1 ? 'task is' : 'tasks are';
      throw new ValidationError(
        `Cannot submit shift summary: ${incompleteTasks.length} ${noun} still pending or in progress: ${uniqAreas.join(', ')}${extra}. Please complete or resolve them before submitting.`
      );
    }
  }

  async _enrichSummaryAreas(areas) {
    return Promise.all(areas.map(async (a) => {
      let areaBasicAreaSqFt = parseFloat(a.basicAreaSqFt) || 0;
      let areaTimesPerPeriod = parseInt(a.boqTimesPerPeriod, 10) || 1;
      let timesCleaned = parseInt(a.times, 10) || 0;
      let frequency = a.cleaningFrequency || a.frequency || 'daily';
      let mainArea = a.mainArea || '';
      let areaName = a.areaName || '';
      let tenderedAreaPerDay = parseFloat(a.tenderedAreaPerDay) || 0;
      if (a.areaId) {
        try {
          const areaDoc = await db.collection('stationAreas').doc(a.areaId).get();
          if (areaDoc.exists) {
            const area = areaDoc.data();
            if (!areaBasicAreaSqFt) areaBasicAreaSqFt = parseFloat(area.basicAreaSqFt) || 0;
            if (!areaTimesPerPeriod) areaTimesPerPeriod = parseInt(area.boqTimesPerPeriod || area.frequencyTimes, 10) || 1;
            if (!frequency || frequency === 'daily') frequency = area.cleaningFrequency || area.frequency || frequency || 'daily';
            if (!mainArea) mainArea = area.mainArea || '';
            if (!areaName) areaName = area.areaName || area.name || '';
            if (!tenderedAreaPerDay) tenderedAreaPerDay = parseFloat(area.tenderedAreaPerDay) || 0;
          }
        } catch (_) { /* keep provided values */ }
      }
      if (!timesCleaned) timesCleaned = areaTimesPerPeriod;
      const workDone = Math.round(areaBasicAreaSqFt * timesCleaned);
      return {
        areaId: a.areaId || '',
        areaName: areaName,
        mainArea: mainArea || '',
        basicAreaSqFt: areaBasicAreaSqFt,
        cleaningFrequency: frequency || 'daily',
        boqTimesPerPeriod: areaTimesPerPeriod,
        times: timesCleaned,
        workDone,
        tenderedAreaPerDay: tenderedAreaPerDay || workDone,
        photoUrl: a.photoUrl || '',
        photoUrls: Array.isArray(a.photoUrls) && a.photoUrls.some(u => u && String(u).trim())
          ? a.photoUrls.filter(u => u && String(u).trim())
          : (a.photoUrl && String(a.photoUrl).trim() ? [a.photoUrl] : []),
        scheduledTime: a.scheduledTime || '',
        taskId: a.taskId || null,
        latitude: a.latitude,
        longitude: a.longitude,
        remark: String(a.remark || '').trim(),
      };
    }));
  }

  _assertRailwayApprover(user) {
    const role = (user?.role || '').toUpperCase().replace(/\s+/g, '_');
    const allowed = ['SUPER_ADMIN', 'COMPANY_MASTER', 'RAILWAY_MASTER', 'ADMIN', 'RAILWAY_ADMIN', 'RAILWAY_SUPERVISOR', 'CONTRACTOR_ADMIN', 'CONTRACTOR_MASTER'];
    if (!allowed.includes(role)) {
      throw new ForbiddenError('Only railway employees or contractor admins can approve or reject shift summaries');
    }
  }

  async _notifyRailwaysForApproval({ summaryUid, supervisorName, stationName, stationId, shift, isResubmit = false }) {
    try {
      const notifyRoles = ['RAILWAY_SUPERVISOR', 'RAILWAY_ADMIN', 'RAILWAY_MASTER', 'SUPER_ADMIN'];
      const usersSnap = await db.collection('users')
        .where('role', 'in', notifyRoles)
        .limit(50)
        .get();
      const title = isResubmit ? 'Shift Summary Resubmitted' : 'Shift Summary Submitted';
      const body = `${supervisorName || 'Supervisor'} ${isResubmit ? 'resubmitted' : 'submitted'} shift summary for ${stationName || 'station'} — ${shift || ''} shift. Please review and approve.`;
      const data = { type: 'shift_summary_approval', summaryUid, stationId: stationId || '' };
      for (const userDoc of usersSnap.docs) {
        const userData = userDoc.data();
        if (userData.stationId === stationId || (userData.stations && Array.isArray(userData.stations) && userData.stations.includes(stationId))) {
          fcmService.sendPush(userDoc.id, title, body, data).catch(() => {});
        }
      }
    } catch (_) { /* notification failure should not block submission */ }
  }

  async submitShiftSummary(data, user) {
    const { supervisorId, supervisorName, stationId, stationName, date, shift, areas } = data;
    if (!supervisorId || !stationId || !date || !areas || !Array.isArray(areas)) {
      throw new ValidationError('supervisorId, stationId, date, and areas array are required');
    }
    this._validateSummaryAreas(areas);

    // ─── Duplicate guard: a submitted/approved summary already exists for this
    // supervisor/date/shift → block (resubmission is done via resubmit) ───
    const existingSnap = await db.collection('stationShiftSummaries')
      .where('supervisorId', '==', supervisorId)
      .get();
    let existingStatus = null;
    existingSnap.forEach(d => {
      if (existingStatus) return;
      const s = d.data();
      if (String(s.date) !== String(date)) return;
      const sShift = s.shift ? String(s.shift).trim().toLowerCase() : '';
      const inShift = String(shift || '').trim().toLowerCase();
      if (inShift) {
        if (sShift !== inShift) return;
      } else if (sShift && sShift !== 'morning') {
        return;
      }
      if (['submitted', 'approved'].includes(s.status)) existingStatus = s.status;
    });
    if (existingStatus) {
      throw new ValidationError(`A shift summary for this supervisor/date/shift is already ${existingStatus}. You cannot submit again while it is ${existingStatus}.`);
    }

    const now = new Date().toISOString();
    const ref = db.collection('stationShiftSummaries').doc();

    // ─── Gate: all tasks for this supervisor/station/date/shift must be
    // terminal (completed/approved/cancelled) before the summary can submit ───
    const resolvedShift = String(shift || '').trim().toLowerCase();
    await this._assertAllTasksTerminal(supervisorId, stationId, date, resolvedShift);
    const enriched = await this._enrichSummaryAreas(areas);

    const totalWorkDone = enriched.reduce((sum, a) => sum + (a.workDone || 0), 0);
    const totalTenderedArea = enriched.reduce((sum, a) => sum + (a.tenderedAreaPerDay || 0), 0);
    const record = {
      uid: ref.id,
      supervisorId,
      supervisorName: supervisorName || '',
      stationId,
      stationName: stationName || '',
      date,
      shift: shift || '',
      areas: enriched,
      totalWorkDone,
      totalTenderedArea,
      status: 'submitted',
      submittedAt: now,
      submittedBy: (user && user.uid) || supervisorId,
      approvedBy: null, approvedByName: null, approvedAt: null,
      rejectedBy: null, rejectionReason: null, rejectedAt: null,
      autoApproved: false,
      resubmitCount: 0,
      lastResubmittedAt: null,
      createdAt: now,
      updatedAt: now,
    };
    await ref.set(record);

    // ─── End-of-shift attendance: submitting the shift summary auto-marks the
    // contractor supervisor's END attendance in station_cleaning_attendance ───
    try {
      await this._autoMarkShiftEndAttendance({
        supervisorId, supervisorName, stationId, stationName, date, shift, areas: enriched,
      });
    } catch (attErr) {
      logger.error('StationCleaning', '(Shift Summary End Attendance) Error:', attErr);
    }

    // Notify railway supervisors/admins for approval
    await this._notifyRailwaysForApproval({
      summaryUid: ref.id, supervisorName, stationName, stationId, shift, isResubmit: false,
    });

    return { message: 'Shift summary submitted for approval', uid: ref.id, count: enriched.length, totalWorkDone, status: 'submitted' };
  }

  // Auto-marks the contractor supervisor's END attendance when a shift summary
  // is submitted. Uses a submitted end-of-shift area photo (with live GPS) as
  // the attendance evidence, so no separate face-capture step is required.
  async _autoMarkShiftEndAttendance({ supervisorId, supervisorName, stationId, stationName, date, shift, areas }) {
    if (!supervisorId) return;
    const now = new Date().toISOString();

    // Prefer a submitted area photo with live GPS as attendance evidence.
    const evidence = Array.isArray(areas)
      ? areas.find(a => a.photoUrl && String(a.photoUrl).trim() && a.latitude != null && a.longitude != null)
      : null;
    const photoUrl = evidence ? evidence.photoUrl : (Array.isArray(areas) && areas[0] ? areas[0].photoUrl || '' : '');
    const latitude = evidence ? evidence.latitude : (Array.isArray(areas) && areas[0] ? areas[0].latitude : null);
    const longitude = evidence ? evidence.longitude : (Array.isArray(areas) && areas[0] ? areas[0].longitude : null);

    const endAttendance = {
      photoUrl: photoUrl || '',
      deviceTimestamp: now,
      serverTimestamp: now,
      location: (latitude != null && longitude != null) ? { latitude, longitude } : null,
      mobileNumber: null, deviceId: null,
      isLate: false, lateByMinutes: 0,
      source: 'shift_summary_submit',
      status: 'PRESENT',
    };

    // Find the supervisor's attendance record for today (station_cleaning_attendance).
    let attendanceRef = null;
    try {
      const snapshot = await db.collection('station_cleaning_attendance').where('workerId', '==', supervisorId).get();
      let candidate = null;
      let latestTime = 0;
      snapshot.forEach(doc => {
        const d = doc.data();
        const t = new Date(d.createdAt || 0).getTime();
        if (t > latestTime) { latestTime = t; candidate = doc; }
      });
      if (candidate && String(candidate.data().date) === String(date)) {
        attendanceRef = db.collection('station_cleaning_attendance').doc(candidate.id);
      }
    } catch (e) {
      logger.error('StationCleaning', '(Shift Summary End Attendance lookup) Error:', e);
      return;
    }

    if (!attendanceRef) {
      // No start-attendance record today — create an end-only record so history is preserved.
      const docId = `summary_${supervisorId}_${date}_${shift || 'shift'}`;
      attendanceRef = db.collection('station_cleaning_attendance').doc(docId);
    }

    const existing = await attendanceRef.get();
    const current = existing.exists ? existing.data() : null;
    if (current && current.isEndMarked === true) {
      // End already marked — update the timestamp snapshot but don't overwrite.
      await attendanceRef.update({ updatedAt: now, shiftSummaryEndRecordedAt: now });
      return;
    }

    if (current) {
      await attendanceRef.update({
        endAttendance,
        isEndMarked: true,
        attendanceStatus: 'PRESENT',
        identityAuditStatus: photoUrl ? 'VERIFIED_SUCCESS' : 'UNVERIFIED_REVIEW',
        source: 'shift_summary_submit',
        shiftSummaryEndRecordedAt: now,
        updatedAt: now,
      });
    } else {
      await attendanceRef.set({
        uid: attendanceRef.id,
        runInstanceId: `summary_${supervisorId}_${date}_${shift || 'shift'}`,
        stationId: stationId || null,
        stationName: stationName || '',
        workerId: supervisorId,
        workerName: supervisorName || 'Supervisor',
        workerType: 'supervisor',
        date,
        shift: shift || '',
        isStartMarked: false, isMidMarked: false, isEndMarked: true,
        attendanceStatus: 'PRESENT',
        identityAuditStatus: photoUrl ? 'VERIFIED_SUCCESS' : 'UNVERIFIED_REVIEW',
        startAttendance: null, midAttendance: null, endAttendance,
        source: 'shift_summary_submit',
        shiftSummaryEndRecordedAt: now,
        createdAt: now, updatedAt: now,
      });
    }
  }

  async listShiftSummaries(query = {}, user) {
    const { stationId, date, shift, supervisorId, status } = query;
    let q = db.collection('stationShiftSummaries');
    if (stationId) q = q.where('stationId', '==', stationId);
    if (date) q = q.where('date', '==', date);
    if (shift) q = q.where('shift', '==', shift);
    if (status) q = q.where('status', '==', status);
    const role = (user && user.role) ? String(user.role).toUpperCase().replace(/\s+/g, '_') : '';
    const isRailwayOrMaster = ['SUPER_ADMIN', 'COMPANY_MASTER', 'RAILWAY_MASTER', 'ADMIN', 'RAILWAY_ADMIN', 'RAILWAY_INSPECTOR', 'RAILWAY_SUPERVISOR'].includes(role);
    const canViewStationSummaries = isRailwayOrMaster || ['CONTRACTOR_ADMIN', 'CONTRACTOR_MASTER'].includes(role);
    const userStationIds = new Set();
    if (user && user.stationId) userStationIds.add(user.stationId);
    if (user && Array.isArray(user.stations)) user.stations.forEach((s) => userStationIds.add(s));
    const allowedOnStation = (summary) => {
      if (canViewStationSummaries) return true;
      if (summary.supervisorId === user.uid) return true;
      return userStationIds.has(summary.stationId);
    };
    let snap;
    try {
      snap = await q.orderBy('submittedAt', 'desc').limit(200).get();
    } catch (indexErr) {
      snap = await q.limit(200).get();
      const docs = [];
      snap.forEach(d => docs.push(d));
      docs.sort((a, b) => (b.data().submittedAt || '').localeCompare(a.data().submittedAt || ''));
      const records = docs
        .filter(d => {
          if (supervisorId && d.data().supervisorId !== supervisorId) return false;
          if (!allowedOnStation(d.data())) return false;
          return true;
        })
        .map(d => ({ id: d.id, ...d.data() }));
      return { count: records.length, summaries: records };
    }
    const summaries = [];
    snap.forEach(d => {
      const s = d.data();
      if (supervisorId && s.supervisorId !== supervisorId) return;
      if (!allowedOnStation(s)) return;
      summaries.push({ id: d.id, ...s });
    });
    return { count: summaries.length, summaries };
  }

  async getShiftSummary(uid) {
    const doc = await db.collection('stationShiftSummaries').doc(uid).get();
    if (!doc.exists) throw new NotFoundError('Shift summary not found');
    return { id: doc.id, ...doc.data() };
  }

  async approveShiftSummary(uid, user, { auto = false } = {}) {
    if (user && String(user.role || '').toUpperCase() !== 'SYSTEM') {
      this._assertRailwayApprover(user);
    }
    const ref = db.collection('stationShiftSummaries').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Shift summary not found');
    if (doc.data().status !== 'submitted') {
      throw new ValidationError(`Only submitted shift summaries can be approved. Current: ${doc.data().status}`);
    }
    await ref.update({
      status: 'approved',
      approvedBy: auto ? 'system' : user.uid,
      approvedByName: auto ? 'Auto-approved (1 hour)' : (user.fullName || user.name || 'Unknown'),
      approvedAt: new Date().toISOString(),
      autoApproved: !!auto,
      updatedAt: new Date().toISOString(),
    });
    return { message: auto ? 'Shift summary auto-approved' : 'Shift summary approved', uid };
  }

  async rejectShiftSummary(uid, reason, user) {
    if (user) this._assertRailwayApprover(user);
    const ref = db.collection('stationShiftSummaries').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Shift summary not found');
    if (doc.data().status !== 'submitted') {
      throw new ValidationError(`Only submitted shift summaries can be rejected. Current: ${doc.data().status}`);
    }
    const rejectionReason = typeof reason === 'string' ? reason : (reason && reason.reason) || '';
    await ref.update({
      status: 'rejected',
      rejectedBy: user.uid,
      rejectedByName: user.fullName || user.name || 'Unknown',
      rejectionReason,
      rejectedAt: new Date().toISOString(),
      autoApproved: false,
      updatedAt: new Date().toISOString(),
    });
    try {
      if (doc.data().supervisorId) {
        fcmService.sendPush(
          doc.data().supervisorId,
          'Shift Summary Rejected',
          `Your shift summary for ${doc.data().stationName || 'station'} (${doc.data().shift || ''} shift) was rejected. Reason: ${rejectionReason || 'No reason provided'}. Please resubmit.`,
          { type: 'shift_summary_rejected', summaryUid: uid, stationId: doc.data().stationId || '' }
        ).catch(() => {});
      }
    } catch (_) { /* notification failure should not block rejection */ }
    return { message: 'Shift summary rejected', uid };
  }

  async resubmitShiftSummary(uid, data, user) {
    const ref = db.collection('stationShiftSummaries').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Shift summary not found');
    const summary = doc.data();
    if (summary.status !== 'rejected') {
      throw new ValidationError(`Only rejected shift summaries can be resubmitted. Current: ${summary.status}`);
    }
    const userId = (user && user.uid) || '';
    if (userId && summary.supervisorId && userId !== summary.supervisorId) {
      throw new ForbiddenError('Only the submitting supervisor can resubmit this shift summary');
    }

    const { supervisorId, supervisorName, stationId, stationName, date, shift, areas } = data;
    if (!supervisorId || !stationId || !date || !areas || !Array.isArray(areas)) {
      throw new ValidationError('supervisorId, stationId, date, and areas array are required');
    }
    this._validateSummaryAreas(areas);

    const resolvedShift = String(summary.shift || shift || '').trim().toLowerCase();
    await this._assertAllTasksTerminal(supervisorId, stationId, date, resolvedShift);
    const enriched = await this._enrichSummaryAreas(areas);
    const totalWorkDone = enriched.reduce((sum, a) => sum + (a.workDone || 0), 0);
    const totalTenderedArea = enriched.reduce((sum, a) => sum + (a.tenderedAreaPerDay || 0), 0);

    const now = new Date().toISOString();
    const resubmitCount = (parseInt(summary.resubmitCount, 10) || 0) + 1;
    const shiftValue = shift || summary.shift || '';
    await ref.update({
      supervisorName: supervisorName || summary.supervisorName || '',
      stationName: stationName || summary.stationName || '',
      shift: shiftValue,
      areas: enriched,
      totalWorkDone,
      totalTenderedArea,
      status: 'submitted',
      submittedAt: now,
      submittedBy: userId || supervisorId || summary.supervisorId || '',
      approvedBy: null, approvedByName: null, approvedAt: null,
      rejectedBy: null, rejectedByName: null, rejectionReason: null, rejectedAt: null,
      autoApproved: false,
      resubmitCount,
      lastResubmittedAt: now,
      updatedAt: now,
    });

    await this._notifyRailwaysForApproval({
      summaryUid: uid,
      supervisorName: supervisorName || summary.supervisorName,
      stationName: stationName || summary.stationName,
      stationId: stationId || summary.stationId,
      shift: shiftValue,
      isResubmit: true,
    });

    return { message: 'Shift summary resubmitted for approval', uid, count: enriched.length, totalWorkDone, status: 'submitted', resubmitCount };
  }

  async autoApproveExpiredShiftSummaries({ maxAgeMs = 3600000 } = {}) {
    const systemUser = { uid: 'system', fullName: 'Auto-approved (1 hour)', name: 'Auto-approved (1 hour)', role: 'SYSTEM' };
    const snap = await db.collection('stationShiftSummaries').where('status', '==', 'submitted').get();
    const cutoff = Date.now() - maxAgeMs;
    let approved = 0;
    for (const d of snap.docs) {
      const s = d.data();
      const submittedAt = s.submittedAt ? new Date(s.submittedAt).getTime() : 0;
      if (!submittedAt || submittedAt > cutoff) continue;
      await this.approveShiftSummary(d.id, systemUser, { auto: true });
      try {
        if (s.supervisorId) {
          fcmService.sendPush(
            s.supervisorId,
            'Shift Summary Auto-Approved',
            `Your shift summary for ${s.stationName || 'station'} (${s.shift || ''} shift) was auto-approved as no action was taken within 1 hour.`,
            { type: 'shift_summary_auto_approved', summaryUid: d.id, stationId: s.stationId || '' }
          ).catch(() => {});
        }
      } catch (_) { /* notification failure should not block auto-approval */ }
      approved++;
    }
    if (approved > 0) {
      logger.info('StationCleaning', `[ShiftSummary] Auto-approved ${approved} expired shift summar${approved === 1 ? 'y' : 'ies'}`);
    }
    return { autoApprovedCount: approved };
  }
}

export const stationCleaningService = new StationCleaningService();
