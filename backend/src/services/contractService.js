import { db } from '../database/index.js';
import { NotFoundError, ConflictError, ValidationError, ForbiddenError } from '../errors/index.js';
import { computeContractDays } from '../utils/period.js';

class ContractService {
  async createContract(creatorData, body) {
    const { contractNumber, contractName, entityId, stationIds: reqStationIds, trainIds: reqTrainIds, startDate, endDate, contractValue, workCategories, remarks, status, repName, repDesignation, repMobile, repEmail, repIdProofType, repIdProofNumber, assignedRailwayOfficials, assignedContractorUsers, scoringApplicability, billingCycle, zone, division, contractType } = body;
    const { uid, name, fullName, email, role } = creatorData;
    const creatorName = fullName || name || email || role || 'Unknown';

    if (!entityId) {
      throw new ValidationError("Please select a Contractor (Entity) to create a contract.");
    }
    if (!contractNumber || !contractName || !startDate || !endDate || !workCategories || !repName || !repMobile || !repEmail) {
      throw new ValidationError("Please fill all mandatory fields: Contract No, Name, Dates, Work Categories, Representative.");
    }

    if (new Date(endDate) <= new Date(startDate)) {
      throw new ValidationError("End date must be after start date.");
    }

    const entityDoc = await db.collection('entities').doc(entityId).get();
    if (!entityDoc.exists) {
      throw new NotFoundError("Selected Contractor does not exist.");
    }
    const entityData = entityDoc.data();
    if (entityData.status !== 'APPROVED') {
      throw new ValidationError("Selected Contractor is not Active/Approved.");
    }
    const entityName = entityData.companyName;

    // Determine assignment: Station Cleaning = stations from division; OBHS = trains from request
    const isStationCleaning = contractType === 'station_cleaning';
    const isOBHS = contractType === 'obhs';
    const isMCC = contractType === 'mcc';
    const stationNames = [];
    let stationIds = [];
    let trainIds = [];
    let trainNames = [];
    let effectiveZone = zone || '';

    if (isStationCleaning || isMCC) {
      if (reqStationIds && reqStationIds.length > 0) {
        for (const sid of reqStationIds) {
          const snap = await db.collection('stations').doc(sid).get();
          if (snap.exists) {
            stationIds.push(snap.id);
            stationNames.push(snap.data().stationName || snap.id);
            if (!effectiveZone) effectiveZone = snap.data().zone;
          } else throw new NotFoundError(`Station ${sid} not found.`);
        }
      } else {
        const effectiveDivision = division || '';
        if (!effectiveDivision) {
          throw new ValidationError("Division is required for station cleaning contracts.");
        }
        const stationsSnap = await db.collection('stations')
          .where('division', '==', effectiveDivision)
          .limit(500)
          .get();
        stationsSnap.forEach(doc => {
          stationIds.push(doc.id);
          stationNames.push(doc.data().stationName || doc.id);
        });
        effectiveZone = zone || stationsSnap.docs[0]?.data().zone || '';
      }
    } else if (isOBHS) {
      trainIds = reqTrainIds || [];
      if (trainIds.length === 0) {
        throw new ValidationError("Please select at least one train for OBHS contract.");
      }
      for (const tid of trainIds) {
        const snap = await db.collection('trains').doc(tid).get();
        if (snap.exists) {
          const tData = snap.data();
          trainNames.push(tData.trainName || tData.trainNo || tid);
          if (!effectiveZone) effectiveZone = tData.zone;
        } else throw new NotFoundError(`Train ${tid} not found.`);
      }
    } else {
      stationIds = reqStationIds || [];
      if (stationIds.length === 0) {
        throw new ValidationError("Please select at least one station for this contract.");
      }
      for (const sid of stationIds) {
        const snap = await db.collection('stations').doc(sid).get();
        if (snap.exists) {
          stationNames.push(snap.data().stationName || sid);
          if (!effectiveZone) effectiveZone = snap.data().zone;
        } else throw new NotFoundError(`Station ${sid} not found.`);
      }
    }

    const duplicateSnap = await db.collection('contracts')
      .where('entityId', '==', entityId)
      .where('status', '==', 'Active').get();
    if (!duplicateSnap.empty) {
      for (const doc of duplicateSnap.docs) {
        const d = doc.data();
        const isDocStationCleaning = d.contractType === 'station_cleaning';
        const isDocOBHS = d.contractType === 'obhs';
        if (isStationCleaning && isDocStationCleaning && stationIds.length > 0) {
          const existingStations = d.stationIds || [];
          const overlap = existingStations.filter(s => stationIds.includes(s));
          if (overlap.length > 0) {
            throw new ValidationError(`This Contractor already has an active Station Cleaning contract covering station(s): ${overlap.join(', ')}.`);
          }
        }
        if (isOBHS && isDocOBHS && trainIds.length > 0) {
          const existingTrains = d.trainIds || [];
          const overlap = existingTrains.filter(t => trainIds.includes(t));
          if (overlap.length > 0) {
            throw new ValidationError(`This Contractor already has an active OBHS contract covering train(s): ${overlap.join(', ')}.`);
          }
        }
        if (!isStationCleaning && !isOBHS && !isDocStationCleaning && !isDocOBHS && stationIds.length > 0) {
          const existingStations = d.stationIds || [];
          const overlap = existingStations.filter(s => stationIds.includes(s));
          if (overlap.length > 0) {
            throw new ValidationError(`This Contractor already has an active contract covering station(s): ${overlap.join(', ')}.`);
          }
        }
      }
    }

    const representative = { name: repName, designation: repDesignation || null, mobile: repMobile, email: repEmail, idProofType: repIdProofType || null, idProofNumber: repIdProofNumber || null };

    const startMs = new Date(startDate).getTime();
    const endMs = new Date(endDate).getTime();
    const durationDays = computeContractDays(startDate, endDate) || Math.ceil((endMs - startMs) / (1000 * 60 * 60 * 24));
    const dailyContractValue = durationDays > 0 ? Math.round(((contractValue || 0) / durationDays) * 100) / 100 : 0;

    const savedDivision = division || '';

    const docRef = db.collection('contracts').doc();
    await docRef.set({
      uid: docRef.id,
      contractNumber,
      contractName,
      entityId,
      entityName,
      stationIds,
      stationNames,
      trainIds,
      trainNames,
      startDate,
      endDate,
      contractDays: durationDays,
      contractDuration: `${durationDays} days`,
      dailyContractValue,
      contractValue: contractValue || 0,
      workCategories,
      remarks: remarks || null,
      status: status || 'Active',
      representative,
      assignedRailwayOfficials: assignedRailwayOfficials || [],
      assignedContractorUsers: assignedContractorUsers || [],
      scoringApplicability: scoringApplicability || false,
      billingCycle: billingCycle || 'monthly',
      contractType: contractType || null,
      zone: effectiveZone,
      division: savedDivision,
      createdAt: db.Timestamp(),
      createdBy: uid,
      createdByName: creatorName
    });

    // Auto-create station-contractor mappings for station cleaning so contractor admin users see these stations
    if ((isStationCleaning || isMCC) && stationIds.length > 0) {
      const batch = db.batch();
      for (const sid of stationIds) {
        const mappingRef = db.collection('stationContractorMappings').doc();
        batch.set(mappingRef, {
          uid: mappingRef.id,
          stationId: sid,
          contractorId: entityId,
          contractId: docRef.id,
          status: 'active',
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString()
        });
      }
      await batch.commit();
    }

    return { message: 'Contract created successfully', uid: docRef.id };
  }

  async updateContract(editorData, uid, updates) {
    const { uid: userId, name, fullName, email, role } = editorData;
    const editorName = fullName || name || email || role || 'Unknown';

    const docRef = db.collection('contracts').doc(uid);
    const doc = await docRef.get();
    if (!doc.exists) {
      throw new NotFoundError("Contract not found.");
    }

    const updateData = { ...updates };
    updateData.updatedBy = userId;
    updateData.updatedByName = editorName;
    updateData.updatedAt = new Date().toISOString();

    if (updates.contractValue !== undefined || updates.startDate !== undefined || updates.endDate !== undefined) {
      const current = doc.data();
      const s = updates.startDate ?? current.startDate;
      const e = updates.endDate ?? current.endDate;
      const days = computeContractDays(s, e) || Number(current.contractDays) || 0;
      const val = updates.contractValue !== undefined ? Number(updates.contractValue) : Number(current.contractValue) || 0;
      updateData.contractDays = days;
      updateData.contractDuration = `${days} days`;
      updateData.dailyContractValue = days > 0 ? Math.round((val / days) * 100) / 100 : 0;
    }


    await docRef.update(updateData);
    return { message: 'Contract updated successfully', updates: updateData };
  }

  async getContracts(requesterData, query) {
    const { status, stationId, entityId, contractType: queryContractType } = query;
    const { userType, zone: userZone, division: userDivision, role, domain } = requesterData;
    const userRole = (role || "").trim().toLowerCase().replace(/_/g, " ");

    let firestoreQuery = db.collection('contracts');

    if (userType === 'railway') {
      // All railway users can see all contracts (filtered by stationId if provided)
    } else if (userType === 'contractor') {
      const contractorEntityId = requesterData.entityId;
      if (!contractorEntityId) throw new ValidationError("Entity linkage missing.");
      firestoreQuery = firestoreQuery.where('entityId', '==', contractorEntityId);
      const restrictedRoles = ['contractor supervisor', 'contractor worker', 'worker'];
      if (restrictedRoles.includes(userRole) && requesterData.contractId) {
        firestoreQuery = firestoreQuery.where('uid', '==', requesterData.contractId);
      }
    }

    if (status) firestoreQuery = firestoreQuery.where('status', '==', status);
    if (entityId && userType !== 'contractor') firestoreQuery = firestoreQuery.where('entityId', '==', entityId);

    // Auto-filter by contractType/domain for contractor users
    const effectiveContractType = queryContractType || (userType === 'contractor' ? domain : null);
    if (effectiveContractType) firestoreQuery = firestoreQuery.where('contractType', '==', effectiveContractType);

    const snapshot = await firestoreQuery.limit(200).get();
    if (snapshot.empty) return { count: 0, contracts: [] };

    let contracts = [];
    snapshot.forEach(doc => {
      contracts.push({ ...doc.data(), uid: doc.id });
    });

    if (stationId) {
      contracts = contracts.filter(c => (c.stationIds || []).includes(stationId));
    }

    return { count: contracts.length, contracts };
  }

  async rejectContract(rejectorData, uid, reason) {
    const { uid: userId, name, fullName, email, role } = rejectorData;
    const editorName = fullName || name || email || role || 'Unknown';

    const docRef = db.collection('contracts').doc(uid);
    const doc = await docRef.get();
    if (!doc.exists) {
      throw new NotFoundError("Contract not found.");
    }

    const updateData = {
      status: 'REJECTED',
      rejectionReason: reason || null,
      rejectedBy: userId,
      rejectedByName: editorName,
      rejectedAt: new Date().toISOString(),
      updatedBy: userId,
      updatedByName: editorName,
      updatedAt: new Date().toISOString()
    };

    await docRef.update(updateData);
    return { message: 'Contract rejected successfully', uid, status: 'REJECTED' };
  }

  async getContractByUid(uid, requesterData) {
    if (!uid) throw new ValidationError("Contract ID (UID) is required.");
    const docRef = db.collection('contracts').doc(uid);
    const doc = await docRef.get();
    if (!doc.exists) throw new NotFoundError("Contract not found.");
    const data = doc.data();
    if (requesterData?.userType === 'contractor') {
      if (requesterData?.entityId && data.entityId !== requesterData.entityId) {
        throw new ForbiddenError('You can only access your own company contracts');
      }
      const role = (requesterData?.role || '').toUpperCase().replace(/\s+/g, '_');
      const restrictedRoles = ['CONTRACTOR_SUPERVISOR', 'CONTRACTOR_WORKER', 'WORKER'];
      if (restrictedRoles.includes(role) && requesterData?.contractId && data.uid !== requesterData.contractId) {
        throw new ForbiddenError('You can only access your assigned contract');
      }
    }
    return data;
  }

  async getContractByNumber(contractNumber) {
    if (!contractNumber) throw new ValidationError("Contract Number is required.");
    const snapshot = await db.collection('contracts').where('contractNumber', '==', contractNumber).limit(1).get();
    if (snapshot.empty) throw new NotFoundError("Contract not found with this number.");
    return snapshot.docs[0].data();
  }

  async getContractsForDropdown(requesterData, queryParams) {
    const { userType, zone: userZone, division: userDivision, entityId, role, domain } = requesterData;
    const { entityId: queryEntityId, contractType: queryContractType } = queryParams || {};
    const userRole = (role || '').trim().toLowerCase().replace(/_/g, ' ');

    let query = db.collection('contracts').where('status', '==', 'Active');

    const restrictedRoles = ['contractor supervisor', 'contractor worker', 'worker'];
    if (restrictedRoles.includes(userRole) && requesterData.contractId) {
      query = query.where('uid', '==', requesterData.contractId);
    } else {
      const effectiveEntityId = queryEntityId || entityId;
      if (effectiveEntityId) {
        query = query.where('entityId', '==', effectiveEntityId);
      }
    }

    const effectiveContractType = queryContractType || (userType === 'contractor' ? domain : null);
    if (effectiveContractType) {
      query = query.where('contractType', '==', effectiveContractType);
    }

    const snapshot = await query.limit(200).get();
    if (snapshot.empty) return { count: 0, contracts: [] };

    const contracts = [];
    snapshot.forEach(doc => {
      const data = doc.data();
      contracts.push({
        uid: doc.id,
        contractNumber: data.contractNumber,
        contractName: data.contractName,
        contractType: data.contractType,
        entityId: data.entityId,
        entityName: data.entityName,
        zone: data.zone,
        division: data.division,
        stationIds: data.stationIds || [],
        stationNames: data.stationNames || []
      });
    });

    return { count: contracts.length, contracts };
  }

  async getContractsByEntity(entityId, query) {
    if (!entityId) throw new ValidationError("Entity ID is required.");
    const { status, stationId, category, contractType } = query || {};
    let firestoreQuery = db.collection('contracts').where('entityId', '==', entityId);
    if (status) firestoreQuery = firestoreQuery.where('status', '==', status);
    if (contractType) firestoreQuery = firestoreQuery.where('contractType', '==', contractType);
    const snapshot = await firestoreQuery.limit(200).get();
    if (snapshot.empty) return { count: 0, contracts: [] };
    const contracts = [];
    snapshot.forEach(doc => {
      const data = doc.data();
      let include = true;
      if (category) {
        const cats = data.workCategories;
        if (Array.isArray(cats)) {
          if (!cats.some(c => c.toLowerCase().includes(category.toLowerCase()))) include = false;
        } else if (typeof cats === 'string') {
          if (!cats.toLowerCase().includes(category.toLowerCase())) include = false;
        } else {
          include = false;
        }
      }
      if (include) {
        contracts.push(data);
      }
    });
    return { count: contracts.length, contracts };
  }
}

export const contractService = new ContractService();
