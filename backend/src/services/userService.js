import { db, admin } from '../database/index.js';
import { ValidationError, NotFoundError, ForbiddenError, ConflictError } from '../errors/index.js';
import { BaseRepository } from '../repositories/BaseRepository.js';
import { safeFormat } from '../utils/helpers.js';

class UserService {
  async createUser(creatorData, userData) {
    let { email, password, role, userType, fullName, designation, mobile, aadhaarNumber, zone, division, depot, entityId, contractId, stations, trainId, trainIds, worker_type, stationId, platformId, areaId } = userData;
    let domain = userData.domain;
    const normalizedEmail = email ? email.trim().toLowerCase() : null;
    const normalizedUserType = (userType || '').toLowerCase();
    const { uid: creatorId, name, fullName: creatorNameAuth, role: creatorRole } = creatorData;
    const creatorName = creatorNameAuth || name || creatorRole || 'Admin';

    if (!email || !password || !role || !userType) {
      throw new ValidationError("Email, Password, Role, and UserType are required.");
    }

    // Contractor principals can only ever create Contractor users — never
    // Railway ones (mirrors the app's contractor-only user type dropdown and
    // the existing approve/reject hierarchy in this service).
    const creatorRoleUpper = (creatorRole || '').toUpperCase().replace(/\s+/g, '_');
    if ((creatorRoleUpper === 'CONTRACTOR_ADMIN' || creatorRoleUpper === 'CONTRACTOR_MASTER') && normalizedUserType !== 'contractor') {
      throw new ForbiddenError('Contractor Admin / Contractor Master can only create Contractor users.');
    }

    const emailQuery = await db.collection('users').where('email', '==', normalizedEmail).limit(1).get();
    if (!emailQuery.empty) {
      throw new ValidationError("Email already registered.");
    }

    if (mobile) {
      const mobileQuery = await db.collection('users').where('mobile', '==', mobile).limit(1).get();
      if (!mobileQuery.empty) {
        throw new ValidationError("Mobile Number already registered.");
      }
      if (!/^[6-9]\d{9}$/.test(String(mobile).trim())) {
        throw new ValidationError('Please enter a valid 10-digit Indian mobile number. It must start with 6, 7, 8 or 9.');
      }
    }

    if (aadhaarNumber) {
      if (!/^\d{12}$/.test(String(aadhaarNumber).trim())) {
        throw new ValidationError('Invalid Aadhaar number. Must be 12 digits.');
      }
      const aadhaarQuery = await db.collection('users').where('aadhaarNumber', '==', aadhaarNumber).limit(1).get();
      if (!aadhaarQuery.empty) {
        throw new ValidationError("Aadhaar Number already registered.");
      }
    }

    const roleUpper = role.toUpperCase().replace(/\s+/g, '_');
    const isContractorMaster = roleUpper === 'CONTRACTOR_MASTER';

    if (normalizedUserType === 'contractor' && !isContractorMaster) {
      if (!contractId) {
        throw new ValidationError("Contract is mandatory for all Contractor users.");
      }
    }

    // Resolve station names in the stations list to actual station document IDs
    if (stations && stations.length > 0) {
      const resolvedStations = [];
      for (const stationName of stations) {
        if (!stationName || typeof stationName !== 'string') continue;
        const trimmed = stationName.trim();
        if (!trimmed) continue;
        // If it looks like a Firestore document ID (>=20 alphanum), check directly
        if (/^[a-zA-Z0-9]{20,}$/.test(trimmed)) {
          const directSnap = await db.collection('stations').doc(trimmed).get();
          if (directSnap.exists) {
            resolvedStations.push(trimmed);
            continue;
          }
        }
        // Try exact match on stationName
        let snap = await db.collection('stations')
          .where('stationName', '==', trimmed)
          .limit(1)
          .get();
        if (snap.empty) {
          snap = await db.collection('stations')
            .where('stationName', '>=', trimmed)
            .where('stationName', '<=', trimmed + '\uf8ff')
            .limit(1)
            .get();
        }
        if (!snap.empty) {
          resolvedStations.push(snap.docs[0].id);
        } else {
          // Try matching by stationCode
          const codeSnap = await db.collection('stations')
            .where('stationCode', '==', trimmed.toUpperCase())
            .limit(1)
            .get();
          if (!codeSnap.empty) {
            resolvedStations.push(codeSnap.docs[0].id);
          } else {
            throw new ValidationError(`Station "${stationName}" not found. Please check the station name.`);
          }
        }
      }
      stations = resolvedStations;
    }

    const isWorkerRole = roleUpper.includes('WORKER') || roleUpper === 'JANITOR' || roleUpper === 'ATTENDANT';
    if (isWorkerRole) {
      const explicitWorkerType = worker_type || (roleUpper === 'JANITOR' ? 'Janitor' : (roleUpper === 'ATTENDANT' ? 'Attendant' : null));
      if (!explicitWorkerType || !['Janitor', 'Attendant'].includes(explicitWorkerType)) {
        throw new ValidationError("Invalid worker category. Only 'Janitor' and 'Attendant' categories are permitted for workers.");
      }
      userData.worker_type = explicitWorkerType; // ensure it is set correctly
    }

    let entityData = null;
    let resolvedContractType = null;
    if (normalizedUserType === 'contractor' && !isContractorMaster) {
      const contractDoc = await db.collection('contracts').doc(contractId).get();
      if (!contractDoc.exists) {
        throw new NotFoundError("Contract not found.");
      }
      const contractData = contractDoc.data();
      entityData = contractData.entityName ? { companyName: contractData.entityName } : null;
      resolvedContractType = contractData.contractType || null;
      entityId = contractData.entityId || entityId;
      userData.entityId = entityId;
      const userRoleLower = role.toLowerCase().replace(/_/g, " ");
      const creatorRoleUpper = (creatorRole || '').toUpperCase().replace(/\s+/g, '_');
      const bypassRoles = ['SUPER_ADMIN', 'COMPANY_MASTER', 'ADMIN'];
      const isCreatorSuperAdmin = bypassRoles.includes(creatorRoleUpper);
      if ((!userRoleLower.includes("super admin") && userRoleLower.includes("admin")) || userRoleLower.includes('supervisor')) {
        if (!isCreatorSuperAdmin) {
          if (!zone || !division) {
            throw new ValidationError("Zone and Division are mandatory to check Active Contracts.");
          }
          console.log(`(CreateUser) Checking Active Contract for Entity: ${entityId}`);
          const contractSnapshot = await db.collection('contracts')
            .where('entityId', '==', entityId)
            .get();
            
          const invalidStatuses = ['Expired', 'EXPIRED', 'REJECTED', 'rejected', 'SUSPENDED', 'suspended'];
          const hasValidContract = contractSnapshot.docs.some(doc => {
            const d = doc.data();
            return !invalidStatuses.includes(d.status) && d.zone === zone && d.division === division;
          });

          if (!hasValidContract) {
            throw new ForbiddenError(`Cannot create ${role}. No valid Contract found for this Company in Zone: ${zone}, Division: ${division}. Please ensure a contract exists and is not expired or rejected.`);
          }
        }
      }

      if (!domain) {
        const contractDoc = await db.collection('contracts').doc(contractId).get();
        if (contractDoc.exists) {
          const contractData = contractDoc.data();
          if (contractData.contractType === 'station_cleaning' || contractData.contractType === 'obhs') {
            domain = contractData.contractType;
          }
        }
      }
      
      // If we still don't have a domain, but the creator specifies it or it can be derived, ensure it matches
      if (domain && !['station_cleaning', 'obhs'].includes(domain)) {
        domain = null;
      }
    }

    // Railway Inspector is always scoped to the Station Cleaning contract
    if (roleUpper === 'RAILWAY INSPECTOR') {
      domain = 'station_cleaning';
    }

    if (roleUpper === 'CTS' || roleUpper === 'CONTRACTOR SUPERVISOR') {
      if (!division) {
        throw new ValidationError("Division is mandatory for Contractor Supervisor.");
      }
      if (resolvedContractType !== 'station_cleaning') {
        if (!trainId) {
          throw new ValidationError("Train ID is mandatory for Contractor Supervisor on this contract type.");
        }
        if (trainIds && trainIds.length > 1) {
          throw new ValidationError("Contractor Supervisor can only be mapped to ONE train.");
        }
      }
    }

    if (roleUpper === 'RAILWAY SUPERVISOR') {
      if (!division || (!trainId && (!trainIds || trainIds.length === 0))) {
        throw new ValidationError("Division and at least one Train ID are mandatory for Railway Supervisor.");
      }
    }

    let userRecord;
    try {
      userRecord = await admin.auth().createUser({ email: normalizedEmail, password, displayName: fullName, disabled: false });
    } catch (error) {
      if (error.code === 'auth/email-already-exists') {
        throw new ValidationError("Email is already in use (Auth).");
      }
      throw error;
    }

    const newUid = userRecord.uid;
      const lowerCreatorRole = (creatorRole || '').toLowerCase();
      // Ensure all users go for approval, even if created by a super admin
      const initialStatus = 'PENDING';

      await db.collection('users').doc(newUid).set({
        uid: newUid,
        email: normalizedEmail,
        password,
        role,
        userType: normalizedUserType,
        fullName: fullName || null,
        mobile: mobile || null,
        aadhaarNumber: aadhaarNumber || null,
        designation: designation || null,
        zone: zone || null,
        division: division || null,
        depot: depot || null,
        entityId: entityId || null,
        entityDetails: entityData,
        contractId: contractId || null,
        contractType: resolvedContractType || domain || null,
        stations: stations || [],
        trainId: trainId || null,
        trainIds: trainIds || (trainId ? [trainId] : []),
        worker_type: worker_type || null,
        stationId: stationId || null,
        platformId: platformId || null,
        areaId: areaId || null,
        domain: domain || null,
        createdBy: creatorId,
        createdByName: creatorName,
        status: initialStatus,
        createdAt: new Date().toISOString(),
        submitted_at: new Date().toISOString()
      });

      console.log(`(Admin) User Created: ${fullName} by ${creatorName} with status ${initialStatus}`);
    return { message: 'User created successfully.', uid: newUid };
  }

  async updateUser(editorData, uid, updates) {
    const { fullName, designation, mobile, aadhaarNumber, zone, division, depot, role, userType, password, entityId, contractId, stations, trainId, trainIds, worker_type, stationId, platformId, areaId } = updates;
    const { uid: editorId, name, fullName: editorAuthName, role: editorRole } = editorData;
    const editorName = editorAuthName || name || editorRole || 'Admin';

    if (!uid) {
      throw new ValidationError("User ID is required.");
    }

    const userDocRef = db.collection('users').doc(uid);
    const doc = await userDocRef.get();
    if (!doc.exists) {
      throw new NotFoundError("User not found.");
    }

    const currentData = doc.data();
    const targetUserName = fullName || currentData.fullName || 'Unknown User';
    const finalRole = role || currentData.role;
    const finalRoleUpper = finalRole ? finalRole.toUpperCase() : '';
    const finalDivision = division || currentData.division;
    const finalTrainId = trainId || currentData.trainId;
    const finalTrainIds = trainIds || currentData.trainIds;

    if (finalRoleUpper === 'CTS' || finalRoleUpper === 'CONTRACTOR SUPERVISOR') {
      if (!finalDivision) {
        throw new ValidationError("Division is mandatory for Contractor Supervisor.");
      }
      const finalContractId = contractId || currentData.contractId;
      const finalContractType = currentData.contractType;
      const isStationCleaning = finalContractType === 'station_cleaning';
      if (!isStationCleaning && !finalTrainId) {
        throw new ValidationError("Train ID is mandatory for Contractor Supervisor on this contract type.");
      }
      if (Array.isArray(finalTrainId) || (finalTrainIds && finalTrainIds.length > 1)) {
        throw new ValidationError("Contractor Supervisor can only be mapped to ONE train.");
      }
    }

    if (finalRoleUpper === 'RAILWAY SUPERVISOR') {
      if (!finalDivision || (!finalTrainId && (!finalTrainIds || finalTrainIds.length === 0))) {
        throw new ValidationError("Division and at least one Train ID are mandatory for Railway Supervisor.");
      }
    }

    const updateData = {};
    if (fullName !== undefined) updateData.fullName = fullName;
    if (designation !== undefined) updateData.designation = designation;
    if (mobile !== undefined) {
      if (!/^[6-9]\d{9}$/.test(String(mobile).trim())) {
        throw new ValidationError('Please enter a valid 10-digit Indian mobile number. It must start with 6, 7, 8 or 9.');
      }
      const mobileQuery = await db.collection('users').where('mobile', '==', mobile).limit(1).get();
      if (!mobileQuery.empty && mobileQuery.docs[0].id !== uid) {
        throw new ValidationError("Mobile Number already registered.");
      }
      updateData.mobile = mobile;
    }
    if (aadhaarNumber !== undefined) {
      if (!/^\d{12}$/.test(String(aadhaarNumber).trim())) {
        throw new ValidationError('Invalid Aadhaar number. Must be 12 digits.');
      }
      const aadhaarQuery = await db.collection('users').where('aadhaarNumber', '==', aadhaarNumber).limit(1).get();
      if (!aadhaarQuery.empty && aadhaarQuery.docs[0].id !== uid) {
        throw new ValidationError("Aadhaar Number already registered.");
      }
      updateData.aadhaarNumber = aadhaarNumber;
    }
    if (zone !== undefined) updateData.zone = zone;
    if (division !== undefined) updateData.division = division;
    if (depot !== undefined) updateData.depot = depot;
    if (role !== undefined) updateData.role = role;
    if (userType !== undefined) updateData.userType = userType.toLowerCase();
    if (trainId !== undefined) updateData.trainId = trainId;
    if (trainIds !== undefined) updateData.trainIds = trainIds;
    if (worker_type !== undefined) {
      const targetRoleUpper = finalRoleUpper;
      const isWorkerRole = targetRoleUpper.includes('WORKER') || targetRoleUpper === 'JANITOR' || targetRoleUpper === 'ATTENDANT';
      if (isWorkerRole) {
        if (!['Janitor', 'Attendant'].includes(worker_type)) {
          throw new ValidationError("Invalid worker category. Only 'Janitor' and 'Attendant' categories are permitted for workers.");
        }
        updateData.worker_type = worker_type;
      }
    }
    if (stationId !== undefined) updateData.stationId = stationId;
    if (platformId !== undefined) updateData.platformId = platformId;
    if (areaId !== undefined) updateData.areaId = areaId;
    
    // Auto-resolve domain if entity changes or updates domain
    if (updates.domain !== undefined) {
      updateData.domain = updates.domain;
    } else if (entityId !== undefined && entityId) {
      const contractSnapshot = await db.collection('contracts')
        .where('entityId', '==', entityId)
        .where('status', '==', 'Active')
        .limit(1).get();
      if (!contractSnapshot.empty) {
        const firstContract = contractSnapshot.docs[0].data();
        if (firstContract.contractType === 'station_cleaning' || firstContract.contractType === 'obhs') {
          updateData.domain = firstContract.contractType;
        }
      }
    }
    updateData.status = 'PENDING';
    updateData.updatedAt = new Date().toISOString();
    updateData.updatedBy = editorId;
    updateData.updatedByName = editorName;

    if (password) {
      try {
        await admin.auth().updateUser(uid, { password });
        console.log(`(Admin) Password updated for user: ${uid}`);
      } catch (authError) {
        console.error('Error updating password in Auth:', authError);
        throw new ValidationError("Failed to update password. Password must be strong.");
      }
    }

    if (entityId !== undefined) {
      updateData.entityId = entityId;
      if (entityId) {
        const entityDoc = await db.collection('entities').doc(entityId).get();
        if (!entityDoc.exists) {
          throw new NotFoundError("Entity (Company) not found with this ID.");
        }
        updateData.entityDetails = entityDoc.data();
      } else {
        updateData.entityDetails = null;
      }
    }

    if (contractId !== undefined) {
      updateData.contractId = contractId;
      if (contractId) {
        const contractDoc = await db.collection('contracts').doc(contractId).get();
        if (contractDoc.exists) {
          const contractData = contractDoc.data();
          updateData.contractType = contractData.contractType || null;
          if (!updateData.entityDetails) {
            updateData.entityDetails = contractData.entityName ? { companyName: contractData.entityName } : null;
          }
        }
      } else {
        updateData.contractType = null;
      }
    }

    if (stations !== undefined) {
      if (stations && stations.length > 0) {
        const resolvedStations = [];
        for (const stationName of stations) {
          if (!stationName || typeof stationName !== 'string') continue;
          const trimmed = stationName.trim();
          if (!trimmed) continue;
          // If it looks like a Firestore document ID, check directly
          if (/^[a-zA-Z0-9]{20,}$/.test(trimmed)) {
            const directSnap = await db.collection('stations').doc(trimmed).get();
            if (directSnap.exists) {
              resolvedStations.push(trimmed);
              continue;
            }
          }
          let snap = await db.collection('stations')
            .where('stationName', '==', trimmed)
            .limit(1)
            .get();
          if (snap.empty) {
            snap = await db.collection('stations')
              .where('stationName', '>=', trimmed)
              .where('stationName', '<=', trimmed + '\uf8ff')
              .limit(1)
              .get();
          }
          if (!snap.empty) {
            resolvedStations.push(snap.docs[0].id);
          } else {
            const codeSnap = await db.collection('stations')
              .where('stationCode', '==', trimmed.toUpperCase())
              .limit(1)
              .get();
            if (!codeSnap.empty) {
              resolvedStations.push(codeSnap.docs[0].id);
            } else {
              throw new ValidationError(`Station "${stationName}" not found.`);
            }
          }
        }
        updateData.stations = resolvedStations;
      } else {
        updateData.stations = stations;
      }
    }

    if (Object.keys(updateData).length === 0 && !password) {
      throw new ValidationError("No fields to update provided.");
    }

    await userDocRef.update(updateData);
    console.log(`(Admin) User "${targetUserName}" updated by ${editorName}.`);
    return { message: `User "${targetUserName}" has been updated successfully.`, updates: updateData };
  }

  async approveUser(approverData, uid) {
    const { uid: approverId, name, fullName, role, entityId } = approverData;
    const approverName = fullName || name || role || 'Master Admin';
    const normalizeRole = (r) => (r || '').toUpperCase().replace(/\s+/g, '_');
    const approverRole = normalizeRole(role);

    if (!uid) {
      throw new ValidationError("User ID is required.");
    }

    const userDocRef = db.collection('users').doc(uid);
    const doc = await userDocRef.get();
    if (!doc.exists) {
      throw new NotFoundError("User not found.");
    }

    const userData = doc.data();
    const userName = userData.fullName || "User";
    const targetRole = normalizeRole(userData.role);

    if (approverRole === 'CONTRACTOR_ADMIN') {
      if (targetRole !== 'CONTRACTOR_SUPERVISOR') {
        throw new ForbiddenError('Contractor Admin can only approve Contractor Supervisor users.');
      }
      if (entityId && userData.entityId && entityId !== userData.entityId) {
        throw new ForbiddenError('You can only approve users under your own entity.');
      }
    }

    if (approverRole === 'CONTRACTOR_MASTER') {
      if (targetRole !== 'CONTRACTOR_ADMIN') {
        throw new ForbiddenError('Contractor Master can only approve Contractor Admin users.');
      }
      if (!approverData.entityId || !userData.entityId || approverData.entityId !== userData.entityId) {
        throw new ForbiddenError('You can only approve Contractor Admin users created under your own entity.');
      }
      if (approverData.contractId && userData.contractId && approverData.contractId !== userData.contractId) {
        throw new ForbiddenError('You can only approve Contractor Admin users created under your own contract.');
      }
      if (userData.contractId) {
        const targetContractDoc = await db.collection('contracts').doc(userData.contractId).get();
        if (!targetContractDoc.exists) {
          throw new ForbiddenError('Contract assigned to the Contractor Admin no longer exists.');
        }
        const targetContractData = targetContractDoc.data();
        if (targetContractData.entityId && targetContractData.entityId !== approverData.entityId) {
          throw new ForbiddenError('You can only approve Contractor Admin users created under your own contract.');
        }
      }
      if (approverData.zone && userData.zone && approverData.zone !== userData.zone) {
        throw new ForbiddenError('You can only approve Contractor Admin users under your own zone.');
      }
    }

    await userDocRef.update({
      status: 'APPROVED',
      approvedBy: approverId,
      approvedByName: approverName,
      approvedAt: new Date().toISOString(),
      approved_at: null,
      rejectedBy: null,
      rejectedByName: null,
      rejectedAt: null
    });

    console.log(`(Master) User ${userName} (${uid}) APPROVED by ${approverName}.`);
    return { message: `User ${userName} has been approved successfully.`, approvedBy: approverName };
  }

  async getPendingUsers(requesterData) {
    const requesterRole = (requesterData?.role || '').toUpperCase().replace(/\s+/g, '_');
    const usersRef = db.collection('users');
    let snapshot;
    if (requesterRole === 'CONTRACTOR_MASTER' && requesterData?.entityId) {
      snapshot = await usersRef
        .where('status', '==', 'PENDING')
        .where('entityId', '==', requesterData.entityId)
        .limit(200)
        .get();
    } else {
      snapshot = await usersRef.where('status', '==', 'PENDING').limit(200).get();
    }

    if (snapshot.empty) {
      return { count: 0, users: [], message: 'No pending users found.' };
    }

    const pendingUsers = [];
    snapshot.forEach(doc => {
      const userData = doc.data();
      const userRole = (userData.role || '').toUpperCase().replace(/\s+/g, '_');
      if (requesterRole === 'CONTRACTOR_MASTER' && userRole !== 'CONTRACTOR_ADMIN') {
        return;
      }
      delete userData.password;
      userData.createdAt = safeFormat(userData.createdAt);
      userData.submitted_at = safeFormat(userData.submitted_at);
      pendingUsers.push({ ...userData, uid: doc.id });
    });

    console.log(`(Master) Fetched ${pendingUsers.length} pending users.`);
    return { count: pendingUsers.length, users: pendingUsers };
  }

  async rejectUser(rejectorData, uid) {
    const { uid: adminId, name, fullName, role, entityId } = rejectorData;
    const adminName = fullName || name || role || 'Master Admin';
    const normalizeRole = (r) => (r || '').toUpperCase().replace(/\s+/g, '_');
    const rejectorRole = normalizeRole(role);

    if (!uid) {
      throw new ValidationError("User ID is required.");
    }

    const userDocRef = db.collection('users').doc(uid);
    const doc = await userDocRef.get();
    if (!doc.exists) {
      throw new NotFoundError("User not found.");
    }

    const userData = doc.data();
    const userName = userData.fullName || "User";
    const targetRole = normalizeRole(userData.role);

    if (rejectorRole === 'CONTRACTOR_ADMIN') {
      if (targetRole !== 'CONTRACTOR_SUPERVISOR') {
        throw new ForbiddenError('Contractor Admin can only reject Contractor Supervisor users.');
      }
      if (entityId && userData.entityId && entityId !== userData.entityId) {
        throw new ForbiddenError('You can only reject users under your own entity.');
      }
    }

    if (rejectorRole === 'CONTRACTOR_MASTER') {
      if (targetRole !== 'CONTRACTOR_ADMIN') {
        throw new ForbiddenError('Contractor Master can only reject Contractor Admin users.');
      }
      if (!rejectorData.entityId || !userData.entityId || rejectorData.entityId !== userData.entityId) {
        throw new ForbiddenError('You can only reject Contractor Admin users created under your own entity.');
      }
      if (rejectorData.contractId && userData.contractId && rejectorData.contractId !== userData.contractId) {
        throw new ForbiddenError('You can only reject Contractor Admin users created under your own contract.');
      }
    }

    await userDocRef.update({
      status: 'REJECTED',
      rejectedBy: adminId,
      rejectedByName: adminName,
      rejectedAt: new Date().toISOString(),
      updatedBy: adminId,
      updatedByName: adminName,
      updatedAt: new Date().toISOString(),
      approvedBy: null,
      approvedByName: null,
      approvedAt: null,
      approved_at: null,
      suspendedBy: null,
      suspendedByName: null,
      suspendedAt: null,
      suspended_at: null,
      reviewed_at: null
    });

    console.log(`(Master) User ${userName} (${uid}) REJECTED by ${adminName}.`);
    return { message: `User ${userName} has been rejected.`, rejectedBy: adminName };
  }

  async suspendUser(adminData, uid, reason) {
    const { uid: adminId, name, fullName, role } = adminData;
    const adminName = fullName || name || role || 'Admin';

    if (!uid) {
      throw new ValidationError("User ID is required.");
    }

    const userDocRef = db.collection('users').doc(uid);
    const doc = await userDocRef.get();
    if (!doc.exists) {
      throw new NotFoundError("User not found.");
    }

    const userData = doc.data();
    if (userData.status !== 'APPROVED') {
      throw new ValidationError(`Cannot suspend a user with status: ${userData.status}`);
    }

    const suspensionReason = reason || 'No reason provided';

    await userDocRef.update({
      status: 'SUSPENDED',
      suspensionReason,
      suspendedBy: adminId,
      suspendedByName: adminName,
      suspendedAt: new Date().toISOString(),
      updatedBy: adminId,
      updatedByName: adminName,
      updatedAt: new Date().toISOString(),
      approvedBy: null,
      approvedByName: null,
      approvedAt: null,
      approved_at: null,
      rejectedBy: null,
      rejectedByName: null,
      rejectedAt: null,
      suspended_at: null
    });

    console.log(`(Admin) User ${userData.fullName} (${uid}) SUSPENDED by ${adminName}.`);
    return { message: `User ${userData.fullName} has been suspended.`, suspendedBy: adminName };
  }

  // List responses are consumed on slow mobile networks (the user list loads right
  // after login), so keep them small: the password hash never leaves the database
  // and the embedded entity is reduced to the fields the list UI actually renders.
  _toListUserDoc(docId, data, includeEntityDetails) {
    const out = { ...data, uid: docId };
    delete out.password;
    const entityDetails = out.entityDetails;
    if (entityDetails && typeof entityDetails === 'object' && !Array.isArray(entityDetails)) {
      out.entityDetails = includeEntityDetails
        ? entityDetails
        : {
            uid: entityDetails.uid,
            companyName: entityDetails.companyName,
            contractorName: entityDetails.contractorName
          };
    }
    return out;
  }

  async getUsers(requesterData, filters) {
    const { status: filterStatus, division, zone, depot, entityId } = filters;
    const { uid: requesterUid, role, zone: userZone, division: userDivision } = requesterData;
    const includeEntityDetails = String(filters.includeEntityDetails) === 'true';
    const userRole = (role || "").trim().toUpperCase().replace(/\s+/g, '_');

    const ROLE_HIERARCHY = {
      'SUPER_ADMIN': 100, 'COMPANY_MASTER': 90, 'RAILWAY_MASTER': 80,
      'ADMIN': 70, 'RAILWAY_ADMIN': 60,
      'RAILWAY_INSPECTOR': 52,
      'RAILWAY_SUPERVISOR': 50, 'CONTRACTOR_MASTER': 47, 'CONTRACTOR_ADMIN': 45,
      'CONTRACTOR_SUPERVISOR': 40, 'CTS': 30,
      'WORKER': 10, 'RAILWAY_WORKER': 10, 'JANITOR': 10, 'ATTENDANT': 10, 'PASSENGER': 1
    };
    const requesterLevel = ROLE_HIERARCHY[userRole] || 0;

    let query = db.collection('users');

    if (requesterLevel >= 70) {
      if (zone) query = query.where('zone', '==', zone);
      if (division) query = query.where('division', '==', division);
    } else if (requesterLevel >= 60 || userRole === 'CONTRACTOR_MASTER') {
      query = query.where('zone', '==', userZone);
      if (division) query = query.where('division', '==', division);
    } else {
      query = query.where('division', '==', userDivision);
    }

    if (filters.domain) {
      query = query.where('domain', '==', filters.domain);
    } else if (requesterData.userType === 'contractor' && requesterData.domain) {
      query = query.where('domain', '==', requesterData.domain);
    }

    if (requesterData.contractId) {
      query = query.where('contractId', '==', requesterData.contractId);
    }

    if (entityId) {
      query = query.where('entityId', '==', entityId);
    }

    const snapshot = await query.limit(5000).get();
    let userList = [];
    let stats = { pending: 0, approved: 0, rejected: 0 };

    snapshot.forEach(doc => {
      const d = doc.data();
      const targetRole = (d.role || '').toUpperCase().replace(/\s+/g, '_');
      const targetLevel = ROLE_HIERARCHY[targetRole] || 0;
      
      if (doc.id === requesterUid) return;

      if (targetLevel > requesterLevel) return;

      const s = (d.status || '').toUpperCase();
      if (s === 'PENDING') stats.pending++;
      if (s === 'APPROVED') stats.approved++;
      if (s === 'REJECTED') stats.rejected++;

      if (filterStatus) {
        if (s === filterStatus.toUpperCase()) {
          userList.push(this._toListUserDoc(doc.id, d, includeEntityDetails));
        }
      } else {
        userList.push(this._toListUserDoc(doc.id, d, includeEntityDetails));
      }
    });

    // Newest first so paging through the list is stable and predictable.
    userList.sort((a, b) => {
      const aTime = (a.createdAt && a.createdAt.toDate) ? a.createdAt.toDate().getTime() : (a.createdAt || a.submitted_at || '');
      const bTime = (b.createdAt && b.createdAt.toDate) ? b.createdAt.toDate().getTime() : (b.createdAt || b.submitted_at || '');
      if (typeof aTime === 'number' && typeof bTime === 'number') return bTime - aTime;
      return String(bTime).localeCompare(String(aTime));
    });

    // Chunked delivery: callers that only need a screenful pass limit=... and
    // page through with hasMore instead of downloading the whole list at once.
    const total = userList.length;
    const DEFAULT_LIMIT = 200;
    const MAX_LIMIT = 500;
    const requestedLimit = parseInt(filters.limit, 10);
    const pageSize = Number.isFinite(requestedLimit) && requestedLimit > 0
      ? Math.min(requestedLimit, MAX_LIMIT)
      : DEFAULT_LIMIT;
    const requestedPage = parseInt(filters.page, 10);
    const currentPage = Number.isFinite(requestedPage) && requestedPage > 0 ? requestedPage : 1;
    const start = (currentPage - 1) * pageSize;
    const pagedUsers = userList.slice(start, start + pageSize);

    return {
      success: true,
      count: pagedUsers.length,
      total,
      page: currentPage,
      limit: pageSize,
      hasMore: start + pagedUsers.length < total,
      stats,
      users: pagedUsers
    };
  }

  async getRailwayWorkers(requesterData, filters) {
    const { status: filterStatus, division, zone } = filters;
    const { role: requesterRole, zone: requesterZone, division: requesterDivision } = requesterData;
    const userRole = (requesterRole || '').trim().toUpperCase().replace(/\s+/g, '_');

    const ROLE_HIERARCHY = {
      'SUPER_ADMIN': 100, 'COMPANY_MASTER': 90, 'RAILWAY_MASTER': 80,
      'ADMIN': 70, 'RAILWAY_ADMIN': 60,
      'RAILWAY_INSPECTOR': 52,
      'RAILWAY_SUPERVISOR': 50, 'CONTRACTOR_ADMIN': 45,
      'CONTRACTOR_SUPERVISOR': 40, 'CTS': 30,
      'WORKER': 10, 'RAILWAY_WORKER': 10, 'JANITOR': 10, 'ATTENDANT': 10, 'PASSENGER': 1
    };
    const requesterLevel = ROLE_HIERARCHY[userRole] || 0;

    console.log(`[GET /api/admin/railway-workers] userRole: ${userRole}, requesterDivision: ${requesterDivision}`);

    let query = db.collection('users');

    if (requesterLevel >= 70) {
      if (zone) query = query.where('zone', '==', zone);
      if (division) query = query.where('division', '==', division);
    } else if (requesterLevel >= 60 || userRole === 'CONTRACTOR_MASTER') {
      if (requesterZone) query = query.where('zone', '==', requesterZone);
      if (division) query = query.where('division', '==', division);
    } else {
      if (requesterDivision) {
        query = query.where('division', '==', requesterDivision);
      } else if (requesterZone) {
        query = query.where('zone', '==', requesterZone);
      }
    }
    if (filters.domain) {
      query = query.where('domain', '==', filters.domain);
    } else if (requesterData.userType === 'contractor' && requesterData.domain) {
      query = query.where('domain', '==', requesterData.domain);
    }
    let snapshot = await query.get();
    console.log(`[GET /api/admin/railway-workers] Firestore query returned ${snapshot.size} users`);

    if (snapshot.empty && requesterLevel < 70) {
      if (requesterZone) {
        console.log(`[GET /api/admin/railway-workers] Initial query was empty. Trying zone fallback: ${requesterZone}`);
        let fallbackQuery = db.collection('users').where('zone', '==', requesterZone);
        if (requesterData.userType === 'contractor' && requesterData.entityId) {
          fallbackQuery = fallbackQuery.where('entityId', '==', requesterData.entityId);
        }
        snapshot = await fallbackQuery.get();
        console.log(`[GET /api/admin/railway-workers] Zone fallback query returned ${snapshot.size} users`);
      }
    }

    let workerList = [];
    let stats = { pending: 0, approved: 0, rejected: 0 };
    const validRoles = ['worker', 'railway worker', 'janitor', 'attendant', 'contractor worker', 'obhs staff', 'staff'];

    snapshot.forEach(doc => {
      const d = doc.data();
      const r = (d.role || '').toLowerCase();
      if (!validRoles.includes(r)) return;

      const s = (d.status || '').toUpperCase();
      if (s === 'PENDING') stats.pending++;
      if (s === 'APPROVED') stats.approved++;
      if (s === 'REJECTED') stats.rejected++;

      if (filterStatus) {
        if (s === filterStatus.toUpperCase()) {
          workerList.push({ ...d, uid: doc.id });
        }
      } else {
        workerList.push({ ...d, uid: doc.id });
      }
    });

    return { success: true, count: workerList.length, stats, workers: workerList };
  }

  async getWorkerProfile(uid) {
    const userDoc = await db.collection('users').doc(uid).get();
    if (!userDoc.exists) {
      throw new NotFoundError('Worker profile not found.');
    }

    const userData = userDoc.data();

    const allRunsSnapshot = await db.collection('RunInstance')
      .where('status', 'in', ['PLANNED', 'ALLOCATED', 'READY', 'Active', 'ACTIVE', 'active', 'Scheduled', 'scheduled', 'Running', 'running'])
      .limit(200).get();

    let assignedRuns = [];
    allRunsSnapshot.forEach(doc => {
      const runData = doc.data();
      const assignedCoach = runData.coaches.find(c => c.workerId === uid);
      if (assignedCoach) {
        assignedRuns.push({
          runInstanceId: runData.runInstanceId,
          instanceId: runData.instanceId,
          trainNo: runData.trainNo,
          trainName: runData.trainName,
          departureDate: runData.departureDate,
          outboundTrainNo: runData.outboundTrainNo,
          inboundTrainNo: runData.inboundTrainNo,
          status: runData.status,
          myCoach: {
            coachPosition: assignedCoach.coachPosition,
            coachType: assignedCoach.coachType,
            attendanceStatus: assignedCoach.attendanceStatus
          }
        });
      }
    });

    assignedRuns.sort((a, b) => new Date(b.departureDate) - new Date(a.departureDate));

    return {
      success: true,
      profile: {
        fullName: userData.fullName,
        email: userData.email,
        mobile: userData.mobile,
        designation: userData.designation,
        division: userData.division,
        zone: userData.zone,
        status: userData.status,
        uid: userData.uid,
        userType: userData.userType
      },
      assignedRuns
    };
  }

  async getWorkerStatistics(uid) {
    const now = new Date();
    const runsSnapshot = await db.collection('RunInstance')
      .where('status', 'in', ['PLANNED', 'ALLOCATED', 'READY', 'Active', 'ACTIVE', 'active', 'Scheduled', 'scheduled', 'Running', 'running'])
      .limit(200).get();

    let activeRun = null;
    runsSnapshot.forEach(doc => {
      const runData = doc.data();
      const assignedCoach = runData.coaches.find(c => c.workerId === uid);
      if (assignedCoach && !activeRun) {
        activeRun = { ...runData, runInstanceId: runData.runInstanceId || doc.id, coachType: assignedCoach.coachType };
      }
    });

    let dueTasks = 0, overdueTasks = 0, completedTasks = 0, upcomingTasks = 0;

    if (activeRun) {
      const runInstanceId = activeRun.runInstanceId;
      const coachType = activeRun.coachType || 'S2';

      const completedSnapshot = await db.collection('obhs_tasks').where('runInstanceId', '==', runInstanceId).limit(200).get();
      const completedTaskIds = new Set();
      completedSnapshot.forEach(doc => {
        completedTaskIds.add(doc.data().uid);
      });

      const tripStartDate = new Date(activeRun.createdAt || now);
      const toiletFreqs = [
        { freq: 'Hour 1', startRel: 0, duration: 1 },
        { freq: 'Hour 2', startRel: 1, duration: 1 },
        { freq: 'Hour 3', startRel: 2, duration: 1 },
        { freq: 'Hour 5', startRel: 4, duration: 2 },
        { freq: 'Hour 7', startRel: 6, duration: 2 },
        { freq: 'Hour 9', startRel: 8, duration: 2 }
      ];
      const coachCleaningFreqs = [
        { freq: 'Train Start', startRel: 0, duration: 3 },
        { freq: 'Mid Journey', startRel: 6, duration: 4 },
        { freq: 'Train End', startRel: 12, duration: 3 }
      ];
      const linenFreqs = [
        { freq: 'Initial Distribution', startRel: 0, duration: 4 },
        { freq: 'Night Return Check', startRel: 10, duration: 4 }
      ];
      const taskDefs = [];
      for (const coach of [coachType]) {
        for (const f of toiletFreqs) taskDefs.push({ type: 'Toilet Cleaning', coach, ...f });
        for (const f of coachCleaningFreqs) taskDefs.push({ type: 'Coach Cleaning', coach, ...f });
        for (const f of linenFreqs) taskDefs.push({ type: 'Linen Distribution', coach, ...f });
      }

      taskDefs.forEach(task => {
        const startTime = new Date(tripStartDate.getTime() + task.startRel * 60 * 60 * 1000);
        const endTime = new Date(startTime.getTime() + task.duration * 60 * 60 * 1000);
        const suffix = task.freq ? `_${task.freq.replace(/\s+/g, '')}` : '';
        const generatedTaskId = `${runInstanceId}_${task.coach}_${task.type.replace(/\s+/g, '')}${suffix}`;
        if (completedTaskIds.has(generatedTaskId)) {
          completedTasks++;
        } else if (now > endTime) {
          overdueTasks++;
        } else if (now >= startTime) {
          dueTasks++;
        } else {
          upcomingTasks++;
        }
      });
    }

    const today = now.toISOString().split('T')[0];
    let attendancePercentage = 0;
    try {
      const attendanceSnapshot = await db.collection('obhs_attendance').where('workerId', '==', uid).limit(200).get();
      let markedCount = 0;
      attendanceSnapshot.forEach(doc => {
        const d = doc.data();
        const docDate = d.createdAt ? d.createdAt.split('T')[0] : '';
        if (docDate !== today) return;
        if (d.isStartMarked) markedCount++;
        if (d.isMidMarked) markedCount++;
        if (d.isEndMarked) markedCount++;
      });
      attendancePercentage = Math.round((markedCount / 3) * 100);
    } catch (_) {
      // Silently handle attendance error
    }

    let complaintsRaised = 0;
    try {
      const complaintsSnapshot = await db.collection('obhs_complaints').where('submittedBy.uid', '==', uid).limit(200).get();
      complaintsRaised = complaintsSnapshot.size;
    } catch (_) {
      // Silently handle complaints error
    }

    let averageRating = 0;
    try {
      const ratingSnapshot = await db.collection('ratings').where('workerId', '==', uid).limit(200).get();
      let total = 0, count = 0;
      ratingSnapshot.forEach(doc => {
        const r = doc.data().rating || 0;
        total += r;
        count++;
      });
      averageRating = count > 0 ? Math.round((total / count) * 10) / 10 : 0;
    } catch (_) {
      // Silently handle ratings error
    }

    return {
      success: true,
      statistics: {
        dueTasks,
        overdueTasks,
        completedTasks,
        upcomingTasks,
        tasksCompleted: completedTasks,
        attendancePercentage,
        complaintsRaised,
        averageRating
      }
    };
  }

  async getWorkers(requesterData = {}, filters = {}) {
    let query = db.collection('users');

    if (filters.domain) {
      query = query.where('domain', '==', filters.domain);
    } else if (requesterData.userType === 'contractor' && requesterData.domain) {
      query = query.where('domain', '==', requesterData.domain);
    }

    const snapshot = await query.get();

    const validRoles = ['worker', 'railway worker', 'janitor', 'attendant', 'contractor worker', 'obhs staff', 'staff', 'supervisor', 'railway supervisor', 'contractor supervisor'];
    const workersList = [];
    snapshot.forEach(doc => {
      const data = doc.data();
      if (doc.id === requesterData.uid) return;
      const role = (data.role || '').toLowerCase().replace(/_/g, ' ');
      if (!validRoles.includes(role)) return;
      if (requesterData.userType === 'contractor' && role.includes('railway supervisor')) return;
      if (requesterData.userType === 'contractor' && requesterData.contractId && data.contractId && data.contractId !== requesterData.contractId) return;
      workersList.push({
        uid: data.uid || doc.id,
        fullName: data.fullName || '',
        email: data.email || '',
        mobile: data.mobile || '',
        role: data.role || '',
        designation: data.designation || '',
        status: data.status || 'PENDING',
        userType: data.userType || '',
        stationId: data.stationId || '',
        depot: data.depot || '',
        zone: data.zone || '',
        division: data.division || '',
        domain: data.domain || ''
      });
    });

    // Also fetch workers from supervisorWorkers collection (created via station cleaning module)
    try {
      let supQuery = db.collection('supervisorWorkers')
        .where('isActive', '==', true);
      if (requesterData.userType === 'contractor' && requesterData.contractId) {
        supQuery = supQuery.where('contractId', '==', requesterData.contractId);
      }
      const supSnapshot = await supQuery.limit(300).get();
      supSnapshot.forEach(doc => {
        const data = doc.data();
        const uid = data.uid || doc.id;
        if (workersList.some(w => w.uid === uid)) return;
        workersList.push({
          uid,
          fullName: data.fullName || '',
          email: data.email || data.phone || '',
          mobile: data.phone || '',
          role: 'worker',
          designation: 'Worker',
          status: 'APPROVED',
          userType: 'worker',
          stationId: data.stationId || '',
          depot: '',
          zone: '',
          division: '',
          domain: ''
        });
      });
    } catch (e) {
      console.error('Error fetching supervisorWorkers:', e.message);
    }

    return { count: workersList.length, workers: workersList };
  }

  async getRailwaySupervisors(zone, division, role, module, requesterData = {}) {
    const userRole = (role || "").toUpperCase().replace(/\s+/g, '_');
    
    const ROLE_HIERARCHY = {
      'SUPER_ADMIN': 100, 'COMPANY_MASTER': 90, 'RAILWAY_MASTER': 80,
      'ADMIN': 70, 'RAILWAY_ADMIN': 60,
      'RAILWAY_INSPECTOR': 52,
      'RAILWAY_SUPERVISOR': 50, 'CONTRACTOR_ADMIN': 45,
      'CONTRACTOR_SUPERVISOR': 40, 'CTS': 30,
      'WORKER': 10, 'RAILWAY_WORKER': 10, 'JANITOR': 10, 'ATTENDANT': 10, 'PASSENGER': 1
    };
    const requesterLevel = ROLE_HIERARCHY[userRole] || 0;
    
    const isMaster = requesterLevel >= 60;

    let query = db.collection('users')
      .where('status', '==', 'APPROVED');

    if (module) {
      query = query.where('domain', '==', module);
    } else if (requesterData.domain) {
      query = query.where('domain', '==', requesterData.domain);
    }

    if (isMaster) {
      if (zone) {
        query = query.where('zone', '==', zone);
      }
      if (division) {
        query = query.where('division', '==', division);
      }
      console.log(`(GetSupervisors) Master access: Fetching zone=${zone || 'ALL'} division=${division || 'ALL'}`);
    } else {
      if (!zone) {
        throw new ValidationError("Your user profile is missing Zone.");
      }
      if (!division) {
        throw new ValidationError("Your user profile is missing Division.");
      }
      query = query.where('zone', '==', zone).where('division', '==', division);
      console.log(`(GetSupervisors) Admin/Sup access: Fetching Division ${division}`);
    }

    let snapshot;
    try {
      snapshot = await query.limit(500).get();
    } catch (error) {
      if (error.code === 'FAILED_PRECONDITION') {
        throw new ValidationError(`Query requires an index. Firebase Console check karo. ${error.message}`);
      }
      throw error;
    }

    if (snapshot.empty) {
      return { count: 0, supervisors: [] };
    }

    const allowedRoles = ['RAILWAY_SUPERVISOR', 'RAILWAY_ADMIN', 'RAILWAY_MASTER', 'CONTRACTOR_ADMIN', 'CONTRACTOR_MASTER'];
    const supervisorList = [];

    snapshot.forEach(doc => {
      const data = doc.data();
      const normalizedRole = (data.role || '').toUpperCase().replace(/\s+/g, '_');
      
      if (!allowedRoles.includes(normalizedRole)) return;

      supervisorList.push({
          uid: data.uid,
          fullName: data.fullName,
          division: data.division,
          depot: data.depot
        });
    });

    return { count: supervisorList.length, supervisors: supervisorList };
  }

  async getWorkersPerformance(adminUser) {
    if (!adminUser || !adminUser.uid) {
      throw new ForbiddenError("Unauthorized. Session expired.");
    }

    const allowedRoles = ['Admin', 'Railway Supervisor', 'Company Master'];
    if (!allowedRoles.includes(adminUser.role)) {
      throw new ForbiddenError("Access Denied. Admin privilege required.");
    }

    const workersSnapshot = await db.collection('users')
      .where('status', '==', 'APPROVED')
      .where('role', '==', 'Railway Worker')
      .limit(200).get();

    if (workersSnapshot.empty) {
      return { success: true, message: "No active workers found.", data: [] };
    }

    let workerPerformanceMap = {};
    workersSnapshot.docs.forEach(doc => {
      const uData = doc.data();
      if (uData.uid) {
        workerPerformanceMap[uData.uid] = {
          workerId: uData.uid,
          workerName: uData.fullName || "Unknown Worker",
          email: uData.email || "",
          designation: uData.designation || "OBHS Staff",
          passengerFeedbackCount: 0,
          passengerSumRating: 0,
          passengerAvgRating: 0.0,
          officialFeedbackCount: 0,
          officialSumRating: 0,
          officialAvgRating: 0.0,
          combinedOverallRating: 0.0,
          totalFeedbackCount: 0,
          parametersBreakdown: {
            cleanlinessSum: 0,
            toiletHygieneSum: 0,
            linenQualitySum: 0,
            securitySum: 0,
            staffBehaviourSum: 0
          }
        };
      }
    });

    const feedbackSnapshot = await db.collection('obhs_feedbacks').limit(200).get();
    feedbackSnapshot.docs.forEach(doc => {
      const fData = doc.data();
      if (!fData) return;

      let assignedWorkerId = null;
      if (fData.feedbackType === 'OFFICIAL') {
        assignedWorkerId = fData.targetWorker?.uid;
      } else {
        assignedWorkerId = fData.collectedBy?.uid;
      }

      if (assignedWorkerId && workerPerformanceMap[assignedWorkerId]) {
        let workerNode = workerPerformanceMap[assignedWorkerId];
        const overallScore = Number(fData.overallRating || 0);
        workerNode.totalFeedbackCount += 1;
        if (fData.feedbackType === 'OFFICIAL') {
          workerNode.officialFeedbackCount += 1;
          workerNode.officialSumRating += overallScore;
        } else {
          workerNode.passengerFeedbackCount += 1;
          workerNode.passengerSumRating += overallScore;
        }
        if (fData.ratings) {
          workerNode.parametersBreakdown.cleanlinessSum += Number(fData.ratings.cleanliness || 0);
          workerNode.parametersBreakdown.toiletHygieneSum += Number(fData.ratings.toiletHygiene || 0);
          workerNode.parametersBreakdown.linenQualitySum += Number(fData.ratings.linenQuality || 0);
          workerNode.parametersBreakdown.securitySum += Number(fData.ratings.security || 0);
          workerNode.parametersBreakdown.staffBehaviourSum += Number(fData.ratings.staffBehaviour || 0);
        }
      }
    });

    let finalPerformanceList = Object.values(workerPerformanceMap).map(worker => {
      if (worker.passengerFeedbackCount > 0) {
        worker.passengerAvgRating = parseFloat((worker.passengerSumRating / worker.passengerFeedbackCount).toFixed(2));
      }
      if (worker.officialFeedbackCount > 0) {
        worker.officialAvgRating = parseFloat((worker.officialSumRating / worker.officialFeedbackCount).toFixed(2));
      }
      if (worker.totalFeedbackCount > 0) {
        const grandSum = worker.passengerSumRating + worker.officialSumRating;
        worker.combinedOverallRating = parseFloat((grandSum / worker.totalFeedbackCount).toFixed(2));
        worker.parameters = {
          cleanliness: parseFloat((worker.parametersBreakdown.cleanlinessSum / worker.totalFeedbackCount).toFixed(2)),
          toiletHygiene: parseFloat((worker.parametersBreakdown.toiletHygieneSum / worker.totalFeedbackCount).toFixed(2)),
          linenQuality: parseFloat((worker.parametersBreakdown.linenQualitySum / worker.totalFeedbackCount).toFixed(2)),
          security: parseFloat((worker.parametersBreakdown.securitySum / worker.totalFeedbackCount).toFixed(2)),
          staffBehaviour: parseFloat((worker.parametersBreakdown.staffBehaviourSum / worker.totalFeedbackCount).toFixed(2))
        };
      } else {
        worker.parameters = { cleanliness: 0, toiletHygiene: 0, linenQuality: 0, security: 0, staffBehaviour: 0 };
      }
      delete worker.passengerSumRating;
      delete worker.officialSumRating;
      delete worker.parametersBreakdown;
      return worker;
    });

    finalPerformanceList.sort((a, b) => b.combinedOverallRating - a.combinedOverallRating);

    return { success: true, totalWorkersEvaluated: finalPerformanceList.length, data: finalPerformanceList };
  }

  async getUserById(requesterData, uid) {
    if (!uid) {
      throw new ValidationError("User ID (UID) is required.");
    }

    const docRef = db.collection('users').doc(uid);
    const doc = await docRef.get();
    if (!doc.exists) {
      throw new NotFoundError("User not found.");
    }

    const targetUser = doc.data();

    if (requesterData.userType === 'railway') {
      const reqRole = (requesterData.role || '').toLowerCase();
      if (!reqRole.includes('master')) {
        if (targetUser.division !== requesterData.division) {
          throw new ForbiddenError("Access Denied: You cannot view users of another Division.");
        }
      } else {
        if (targetUser.zone !== requesterData.zone) {
          throw new ForbiddenError("Access Denied: You cannot view users of another Zone.");
        }
      }
    } else if (requesterData.userType === 'contractor') {
      if (targetUser.entityId !== requesterData.entityId) {
        throw new ForbiddenError("Access Denied: Different Company.");
      }
    }

    delete targetUser.password;
    return targetUser;
  }

  async getWorkerTasks(workerId, query = {}) {
    const snapshot = await db.collection('obhs_tasks').where('assignedTo', '==', workerId).limit(50).get();
    const tasks = [];
    snapshot.forEach(doc => tasks.push({ id: doc.id, ...doc.data() }));
    return { count: tasks.length, tasks };
  }

  async submitWorkerComplaint(user, body) {
    const { title, description, category, priority } = body;
    if (!title || !description) throw new ValidationError('Title and description are required.');
    const complaintId = `cmp_${Date.now()}`;
    const complaint = {
      complaintId,
      title,
      description,
      category: category || 'General',
      priority: priority || 'MEDIUM',
      status: 'OPEN',
      raisedBy: user.uid,
      raisedByName: user.fullName || 'Unknown',
      division: user.division || null,
      zone: user.zone || null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
    await db.collection('complaints').doc(complaintId).set(complaint);
    return { success: true, message: 'Complaint submitted successfully', complaintId };
  }

  async getContractorSupervisors(requesterData, queryParams = {}) {
    const entityId = requesterData.entityId;
    if (!entityId) throw new ValidationError("Your profile is missing entityId");
    const { stationId } = queryParams;
    const snapshot = await db.collection('users')
      .where('entityId', '==', entityId)
      .where('status', '==', 'APPROVED')
      .limit(200)
      .get();
    const supervisors = [];
    snapshot.forEach(doc => {
      const d = doc.data();
      const role = (d.role || '').toUpperCase().replace(/\s+/g, '_');
      if (role !== 'CONTRACTOR_SUPERVISOR') return;
      const userStations = d.stations || [];
      if (stationId && !userStations.includes(stationId)) return;
      supervisors.push({
        uid: doc.id,
        fullName: d.fullName || '',
        email: d.email || '',
        mobile: d.mobile || '',
        stations: userStations,
        contractId: d.contractId || null,
        contractType: d.contractType || null,
      });
    });
    return { supervisors };
  }
}

export const userService = new UserService();
