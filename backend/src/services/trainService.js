import { db } from '../database/index.js';
import { NotFoundError, ValidationError, ForbiddenError, ConflictError } from '../errors/index.js';
import { convertToDecimalDays } from '../utils/helpers.js';
import { visibleTrainFilter } from '../utils/assignedTrains.js';

const BLOCKED_ROLES = ['CONTRACTOR SUPERVISOR', 'CTS', 'RAILWAY SUPERVISOR', 'WORKER', 'RAILWAY WORKER'];
const ALLOWED_FIELDS = ['trainNo', 'trainName', 'origin', 'destination', 'days', 'zone', 'division', 'depot', 'status', 'TrainApplicableFor', 'outboundTrainNo', 'inboundTrainNo', 'returnOffset', 'cycleLength', 'outboundDurationStr', 'inboundDurationStr', 'layoverDestStr', 'layoverOriginStr', 'journeyStartTime'];

class TrainService {
  _checkRole(role, action) {
    const callerRole = (role || '').toUpperCase();
    if (BLOCKED_ROLES.includes(callerRole)) {
      throw new ForbiddenError(`Access Denied`, `Your role (${role}) is not authorized to ${action} trains. Only Admin-level users can manage trains.`);
    }
  }

  _validateFields(body) {
    const bodyKeys = Object.keys(body);
    for (const key of bodyKeys) {
      if (!ALLOWED_FIELDS.includes(key)) {
        throw new ValidationError(`Invalid field name.`, `The field '${key}' is not allowed.`);
      }
    }
  }

  _computeOBHS(params) {
    const { TrainApplicableFor, days, outboundDurationStr, inboundDurationStr, layoverDestStr, layoverOriginStr, cycleLength } = params;
    const isOBHSEnabled = TrainApplicableFor && TrainApplicableFor.includes('OBHS');
    let requiredInstances = 0;
    let finalCycleTime = 0;

    if (isOBHSEnabled) {
      if (!outboundDurationStr || !inboundDurationStr || !days || days.length === 0) {
        throw new ValidationError('OBHS Validation Failed', 'For OBHS; Outbound No, Inbound No, and Departure Days are mandatory.');
      }
      const outbound = convertToDecimalDays(outboundDurationStr);
      const inbound = convertToDecimalDays(inboundDurationStr);
      const layoverD = convertToDecimalDays(layoverDestStr);
      const layoverO = convertToDecimalDays(layoverOriginStr);
      const calculatedC = outbound + inbound + layoverD + layoverO;
      finalCycleTime = calculatedC > 0 ? calculatedC : (Number(cycleLength) || 0);
      const numDays = (days.includes('All Days') || days.includes('Daily')) ? 7 : days.length;
      const F = 7 / numDays;
      requiredInstances = Math.ceil(finalCycleTime / F);
      if (requiredInstances <= 0) requiredInstances = 1;
    }

    return { isOBHSEnabled, requiredInstances, finalCycleTime };
  }

  async createTrain(creatorData, body) {
    this._checkRole(creatorData.role, 'create');
    this._validateFields(body);

    const { trainNo, trainName, origin, destination, days, zone, division, depot, status, TrainApplicableFor, outboundTrainNo, inboundTrainNo, returnOffset, cycleLength, outboundDurationStr, inboundDurationStr, layoverDestStr, layoverOriginStr, journeyStartTime } = body;

    const { isOBHSEnabled, requiredInstances, finalCycleTime } = this._computeOBHS({
      TrainApplicableFor, days, outboundDurationStr, inboundDurationStr, layoverDestStr, layoverOriginStr, cycleLength
    });

    const { uid, name, email, role } = creatorData;
    const userName = name || email || role || 'Unknown';

    if (trainNo) {
      const existingTrain = await db.collection('trains').where('trainNo', '==', trainNo).limit(1).get();
      if (!existingTrain.empty) {
        throw new ConflictError('A train with this number already exists.');
      }
    }

    const docRef = db.collection('trains').doc();
    const newTrain = {
      uid: docRef.id,
      trainNo: trainNo || null,
      trainName: trainName || null,
      origin: origin || null,
      destination: destination || null,
      days: days || null,
      zone: zone || null,
      division: division || null,
      depot: depot || null,
      status: status || 'active',
      TrainApplicableFor: TrainApplicableFor || [],
      outboundTrainNo: isOBHSEnabled ? outboundTrainNo : null,
      inboundTrainNo: isOBHSEnabled ? inboundTrainNo : null,
      cycleLength: isOBHSEnabled ? Number(finalCycleTime.toFixed(4)) : (cycleLength || null),
      requiredInstances: isOBHSEnabled ? requiredInstances : null,
      journeyStartTime: isOBHSEnabled ? (journeyStartTime || null) : null,
      outboundDurationStr: isOBHSEnabled ? (outboundDurationStr || null) : null,
      inboundDurationStr: isOBHSEnabled ? (inboundDurationStr || null) : null,
      layoverDestStr: isOBHSEnabled ? (layoverDestStr || null) : null,
      layoverOriginStr: isOBHSEnabled ? (layoverOriginStr || null) : null,
      createdBy: uid,
      createdByName: userName,
      createdAt: new Date().toISOString(),
      updatedBy: null,
      updatedByName: null,
      updatedAt: null
    };

    await docRef.set(newTrain);

    if (isOBHSEnabled && requiredInstances > 0) {
      const batch = db.batch();
      for (let i = 0; i < requiredInstances; i++) {
        const instanceLetter = String.fromCharCode(65 + i);
        const instanceId = `${trainNo}-${trainName}-Inst-${instanceLetter}`;
        batch.set(db.collection('TrainPairs').doc(instanceId), {
          instanceId,
          instanceName: `Instance ${instanceLetter}`,
          trainNo,
          trainName,
          status: 'Inactive',
          inboundTrainNo,
          outboundTrainNo,
          rotationPattern: 'Round-Robin',
          parentTrainId: docRef.id,
          createdAt: new Date().toISOString()
        });
      }
      await batch.commit();
    }

    return { message: 'Train and OBHS Pool created successfully', uid: docRef.id, calculatedInstances: requiredInstances, data: newTrain };
  }

  async updateTrain(editorData, uid, updates) {
    this._checkRole(editorData.role, 'modify');
    this._validateFields(updates);

    if (!uid) throw new ValidationError("Train ID (UID) is required.");

    const docRef = db.collection('trains').doc(uid);
    const doc = await docRef.get();
    if (!doc.exists) throw new NotFoundError("Train not found.");
    const existingData = doc.data();

    const { uid: editorId, name, email, role: editorRole } = editorData;
    const editorName = name || email || editorRole || 'Unknown';

    const { trainNo, trainName, origin, destination, days, zone, division, depot, status, TrainApplicableFor, outboundTrainNo, inboundTrainNo, returnOffset, cycleLength, outboundDurationStr, inboundDurationStr, layoverDestStr, layoverOriginStr, journeyStartTime } = updates;

    const isOBHSNow = TrainApplicableFor ? TrainApplicableFor.includes('OBHS') : existingData.TrainApplicableFor.includes('OBHS');
    let newRequiredInstances = existingData.requiredInstances || 0;
    let newFinalCycleTime = existingData.cycleLength || 0;

    if (isOBHSNow) {
      const outbound = outboundDurationStr !== undefined ? convertToDecimalDays(outboundDurationStr) : convertToDecimalDays(existingData.outboundDurationStr);
      const inbound = inboundDurationStr !== undefined ? convertToDecimalDays(inboundDurationStr) : convertToDecimalDays(existingData.inboundDurationStr);
      const layoverD = layoverDestStr !== undefined ? convertToDecimalDays(layoverDestStr) : convertToDecimalDays(existingData.layoverDestStr);
      const layoverO = layoverOriginStr !== undefined ? convertToDecimalDays(layoverOriginStr) : convertToDecimalDays(existingData.layoverOriginStr);
      const calculatedC = outbound + inbound + layoverD + layoverO;
      newFinalCycleTime = calculatedC > 0 ? calculatedC : (Number(cycleLength) || existingData.cycleLength || 0);
      const finalDays = days || existingData.days || [];
      if (finalDays.length === 0) {
        throw new ValidationError('OBHS requires at least one departure day.');
      }
      const numDays = (finalDays.includes('All Days') || finalDays.includes('Daily')) ? 7 : finalDays.length;
      const F = 7 / numDays;
      newRequiredInstances = Math.ceil(newFinalCycleTime / F);
      if (newRequiredInstances <= 0) newRequiredInstances = 1;
    }

    const updateData = {};
    if (trainNo !== undefined) updateData.trainNo = trainNo;
    if (trainName !== undefined) updateData.trainName = trainName;
    if (origin !== undefined) updateData.origin = origin;
    if (destination !== undefined) updateData.destination = destination;
    if (days !== undefined) updateData.days = days;
    if (zone !== undefined) updateData.zone = zone;
    if (division !== undefined) updateData.division = division;
    if (depot !== undefined) updateData.depot = depot;
    if (TrainApplicableFor !== undefined) updateData.TrainApplicableFor = TrainApplicableFor;
    if (outboundTrainNo !== undefined) updateData.outboundTrainNo = outboundTrainNo;
    if (inboundTrainNo !== undefined) updateData.inboundTrainNo = inboundTrainNo;
    if (status) updateData.status = status;
    if (isOBHSNow) {
      updateData.cycleLength = Number(newFinalCycleTime.toFixed(4));
      updateData.requiredInstances = newRequiredInstances;
      if (outboundDurationStr) updateData.outboundDurationStr = outboundDurationStr;
      if (inboundDurationStr) updateData.inboundDurationStr = inboundDurationStr;
      if (layoverDestStr) updateData.layoverDestStr = layoverDestStr;
      if (layoverOriginStr) updateData.layoverOriginStr = layoverOriginStr;
      if (journeyStartTime) updateData.journeyStartTime = journeyStartTime;
    }
    updateData.updatedBy = editorId;
    updateData.updatedByName = editorName;
    updateData.updatedAt = new Date().toISOString();
    updateData.status = 'PENDING';

    await docRef.update(updateData);

    const needsPairUpdate = trainNo || trainName || days || outboundDurationStr || inboundDurationStr || layoverDestStr || layoverOriginStr || outboundTrainNo || inboundTrainNo;
    if (isOBHSNow && needsPairUpdate) {
      const finalTrainNo = trainNo || existingData.trainNo;
      const finalTrainName = trainName || existingData.trainName;
      const finalInbound = inboundTrainNo || existingData.inboundTrainNo;
      const finalOutbound = outboundTrainNo || existingData.outboundTrainNo;
      const oldPairs = await db.collection('TrainPairs').where('parentTrainId', '==', uid).limit(200).get();
      const deleteBatch = db.batch();
      oldPairs.forEach(doc => deleteBatch.delete(doc.ref));
      await deleteBatch.commit();
      const createBatch = db.batch();
      for (let i = 0; i < newRequiredInstances; i++) {
        const instanceLetter = String.fromCharCode(65 + i);
        const instanceId = `${finalTrainNo}-${finalTrainName}-Inst-${instanceLetter}`;
        createBatch.set(db.collection('TrainPairs').doc(instanceId), {
          instanceId,
          instanceName: `Instance ${instanceLetter}`,
          trainNo: finalTrainNo,
          trainName: finalTrainName,
          status: 'Inactive',
          inboundTrainNo: finalInbound,
          outboundTrainNo: finalOutbound,
          rotationPattern: 'Round-Robin',
          parentTrainId: uid,
          updatedAt: new Date().toISOString()
        });
      }
      await createBatch.commit();
    }

    return { message: 'Train and associated TrainPairs updated successfully.', uid, calculatedInstances: newRequiredInstances, updatedData: updateData };
  }

  async getTrains(userData, queryParams) {
    const { role, zone: userZone, division: userDivision, trainId: userTrainId } = userData;
    const { status, zone: queryZone, division: queryDivision, applicableFor } = queryParams || {};
    const userRole = (role || "").trim().toLowerCase().replace(/_/g, " ");

    let query = db.collection('trains');

    if (userRole === 'company master' || userRole === 'super admin') {
      if (queryZone) query = query.where('zone', '==', queryZone);
      if (queryDivision) query = query.where('division', '==', queryDivision);
    } else if (userRole === 'railway master') {
      if (!userZone) throw new ValidationError("Railway Master profile mein Zone missing hai.");
      query = query.where('zone', '==', userZone);
      if (queryDivision) query = query.where('division', '==', queryDivision);
    } else if (userRole === 'cts' || userRole === 'contractor supervisor') {
      if (!userTrainId) {
        return { count: 0, trains: [], message: 'No train assigned to your profile.' };
      }
      const trainDoc = await db.collection('trains').doc(userTrainId).get();
      if (!trainDoc.exists) return { count: 0, trains: [] };
      return { count: 1, trains: [{ uid: trainDoc.id, ...trainDoc.data() }] };
    } else if ((!userRole.includes("super admin") && userRole.includes("admin")) || userRole.includes('supervisor')) {
      if (!userDivision) throw new ValidationError("Supervisor profile mein Division missing hai.");
      query = query.where('division', '==', userDivision);
      if (userZone) query = query.where('zone', '==', userZone);
    }

    if (applicableFor) {
      query = query.where('TrainApplicableFor', 'array-contains', applicableFor);
    }
    if (status) {
      query = query.where('status', '==', status);
    }

    const snapshot = await query.limit(200).get();
    if (snapshot.empty) return { count: 0, trains: [] };

    const trainList = [];
    snapshot.forEach(doc => {
      trainList.push({ uid: doc.id, ...doc.data() });
    });
    trainList.sort((a, b) => {
      return String(a.trainNo || "").localeCompare(String(b.trainNo || ""), undefined, { numeric: true });
    });

    // A Contractor Master/Admin only sees trains on their contract(s) or created by their company.
    const visible = await visibleTrainFilter(userData);
    if (visible) {
      const mine = trainList.filter(visible);
      return { count: mine.length, trains: mine };
    }

    return { count: trainList.length, trains: trainList };
  }

  async getTrainsByZoneDivision(zone, division) {
    let query = db.collection('trains');
    if (zone) query = query.where('zone', '==', zone);
    if (division) query = query.where('division', '==', division);
    const snapshot = await query.limit(200).get();
    if (snapshot.empty) return { count: 0, trains: [] };
    const trainList = [];
    snapshot.forEach(doc => {
      trainList.push({ uid: doc.id, ...doc.data() });
    });
    return { count: trainList.length, trains: trainList };
  }

  async getTrainByUid(uid) {
    if (!uid) throw new ValidationError("Train ID (UID) is required.");
    const docRef = db.collection('trains').doc(uid);
    const doc = await docRef.get();
    if (!doc.exists) throw new NotFoundError("Train not found.");
    const trainData = doc.data();
    if (!trainData.TrainApplicableFor) {
      trainData.TrainApplicableFor = [];
    }
    return trainData;
  }

  async getTrainByNumber(trainNo) {
    if (!trainNo) throw new ValidationError("Train Number is required.");
    const snapshot = await db.collection('trains').where('trainNo', '==', trainNo).limit(1).get();
    if (snapshot.empty) throw new NotFoundError("Train not found with this number.");
    const doc = snapshot.docs[0];
    const trainData = { uid: doc.id, ...doc.data() };
    if (!trainData.TrainApplicableFor) {
      trainData.TrainApplicableFor = [];
    }
    return trainData;
  }

  async deleteTrain(uid) {
    if (!uid) throw new ValidationError("Train ID (UID) is required.");
    const docRef = db.collection('trains').doc(uid);
    const doc = await docRef.get();
    if (!doc.exists) throw new NotFoundError("Train not found.");
    await docRef.delete();
    return { uid, deleted: true };
  }

  async getTrainPairs(trainId) {
    if (!trainId) throw new ValidationError("Train ID is required.");
    const snapshot = await db.collection('TrainPairs').where('parentTrainId', '==', trainId).limit(200).get();
    const pairs = [];
    snapshot.forEach(doc => pairs.push({ id: doc.id, ...doc.data() }));
    return { count: pairs.length, data: pairs };
  }

  async generateSchedule(creatorData, trainId, body) {
    const { startDate, endDate } = body;
    if (!startDate || !endDate) throw new ValidationError('startDate and endDate are required.');
    const trainDoc = await db.collection('trains').doc(trainId).get();
    if (!trainDoc.exists) throw new NotFoundError('Train not found.');
    const train = trainDoc.data();
    const pairsSnap = await db.collection('TrainPairs').where('parentTrainId', '==', trainId).limit(200).get();
    if (pairsSnap.empty) throw new NotFoundError('No train pairs found for this train.');
    const batch = db.batch();
    const schedules = [];
    pairsSnap.forEach(doc => {
      const pair = doc.data();
      const scheduleId = `sched_${pair.instanceId}_${Date.now()}`;
      const schedule = {
        scheduleId,
        trainId,
        instanceId: pair.instanceId,
        startDate,
        endDate,
        status: 'SCHEDULED',
        createdBy: creatorData.uid,
        createdAt: new Date().toISOString()
      };
      batch.set(db.collection('Schedules').doc(scheduleId), schedule);
      schedules.push(schedule);
    });
    await batch.commit();
    return { message: 'Schedule generated successfully', count: schedules.length, schedules };
  }
}

export const trainService = new TrainService();
