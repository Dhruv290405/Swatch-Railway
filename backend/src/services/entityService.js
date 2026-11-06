import { db } from '../database/index.js';
import { NotFoundError, ConflictError, ValidationError } from '../errors/index.js';
import { safeFormat } from '../utils/helpers.js';
import { assertFormat } from '../utils/validators.js';

class EntityService {
  async createEntity(creatorData, body) {
    const { companyName, registrationType, panNumber, gstinNumber, registeredAddress, contactNumber, email, alternateContact, website, yearOfEstablishment, gemId } = body;
    const { uid, name, fullName, email: userEmail, role } = creatorData;
    const creatorName = fullName || name || userEmail || role || 'Unknown';

    if (!companyName || !registrationType) {
      throw new ValidationError('companyName and registrationType are required.');
    }

    // Format checks apply only to values actually provided; PAN/GSTIN are stored upper-cased.
    const panNormalized = assertFormat('pan', panNumber, 'PAN');
    const gstinNormalized = assertFormat('gstin', gstinNumber, 'GSTIN');
    assertFormat('mobile', contactNumber, 'Contact number');
    assertFormat('mobile', alternateContact, 'Alternate contact');
    assertFormat('email', email, 'Email');

    const existing = await db.collection('entities').where('companyName', '==', companyName).limit(1).get();
    if (!existing.empty) {
      throw new ConflictError('Company with this name already exists.');
    }

    const docRef = db.collection('entities').doc();
    const newEntity = {
      uid: docRef.id,
      companyName,
      registrationType,
      panNumber: panNormalized || null,
      gstinNumber: gstinNormalized || null,
      registeredAddress: registeredAddress || null,
      contactNumber: contactNumber || null,
      email: email || null,
      alternateContact: alternateContact || null,
      website: website || null,
      yearOfEstablishment: yearOfEstablishment || null,
      gemId: gemId || null,
      // Entities are created by authorised admins only, so they need no second approval step.
      status: 'APPROVED',
      createdBy: uid,
      createdByName: creatorName,
      createdAt: new Date().toISOString(),
      updatedBy: null,
      updatedByName: null,
      updatedAt: null,
      approvedBy: uid,
      approvedByName: creatorName,
      approvedAt: new Date().toISOString(),
      rejectedBy: null,
      rejectedByName: null,
      rejectedAt: null,
    };

    await docRef.set(newEntity);
    console.log(`(Entity) Created: ${companyName} by ${creatorName}`);
    return { uid: docRef.id, entity: newEntity };
  }

  async updateEntity(editorData, uid, updates, body) {
    const { uid: userId, name, fullName, email, role } = editorData;
    const editorName = fullName || name || email || role || 'Unknown';

    const docRef = db.collection('entities').doc(uid);
    const doc = await docRef.get();
    if (!doc.exists) throw new NotFoundError('Entity not found.');

    const currentData = doc.data();
    if (updates.panNumber !== undefined) updates.panNumber = assertFormat('pan', updates.panNumber, 'PAN');
    if (updates.gstinNumber !== undefined) updates.gstinNumber = assertFormat('gstin', updates.gstinNumber, 'GSTIN');
    if (updates.contactNumber !== undefined) assertFormat('mobile', updates.contactNumber, 'Contact number');
    if (updates.email !== undefined) assertFormat('email', updates.email, 'Email');
    updates.updatedBy = userId;
    updates.updatedByName = editorName;
    updates.updatedAt = new Date().toISOString();

    if (!updates.status && currentData.status === 'APPROVED') {
      // A plain edit of an approved entity must not send it back to the approval queue.
      updates.status = 'APPROVED';
    } else if (!updates.status || (updates.status !== 'APPROVED' && updates.status !== 'REJECTED')) {
      updates.status = 'PENDING';
    }

    if (updates.status) {
      if (updates.status === 'APPROVED' && currentData.status !== 'APPROVED') {
        updates.approvedBy = userId;
        updates.approvedByName = editorName;
        updates.approvedAt = new Date().toISOString();
        updates.rejectedBy = null;
        updates.rejectedByName = null;
        updates.rejectedAt = null;
        updates.suspendedBy = null;
        updates.suspendedByName = null;
        updates.suspendedAt = null;
        updates.approved_at = null;
        console.log(`(Entity) Approved: ${currentData.companyName} by ${editorName}`);
      } else if (updates.status === 'REJECTED') {
        updates.rejectedBy = userId;
        updates.rejectedByName = editorName;
        updates.rejectedAt = new Date().toISOString();
        updates.approvedBy = null;
        updates.approvedByName = null;
        updates.approvedAt = null;
        updates.approved_at = null;
      } else if (updates.status === 'SUSPENDED') {
        console.log(`(Entity) Suspending Entity: ${currentData.companyName}`);
        updates.suspendedBy = userId;
        updates.suspendedByName = editorName;
        updates.suspendedAt = new Date().toISOString();

        const usersSnapshot = await db.collection('users').where('entityId', '==', uid).limit(200).get();
        if (!usersSnapshot.empty) {
          const batch = db.batch();
          usersSnapshot.forEach(doc => batch.update(doc.ref, { status: 'SUSPENDED' }));
          await batch.commit();
        }

        const contractsSnapshot = await db.collection('contracts').where('entityId', '==', uid).limit(200).get();
        if (!contractsSnapshot.empty) {
          const batch2 = db.batch();
          contractsSnapshot.forEach(doc => batch2.update(doc.ref, { status: 'SUSPENDED' }));
          await batch2.commit();
        }
      }
    }

    await docRef.update(updates);
    console.log(`(Entity) Updated: ${uid} | Status: ${updates.status || 'Edited'} | By: ${editorName}`);
    return updates;
  }

  async getEntities(requesterData, query) {
    const queryStatus = query.status;
    const queryContractType = query.contractType;
    const { userType, entityId, division, zone, role } = requesterData;
    const userRole = (role || "").trim().toLowerCase().replace(/_/g, " ");

    let finalEntityIds = [];
    let isFilteredByContract = false;

    if (userType === 'railway') {
      let contractQuery = db.collection('contracts');
      if (userRole === 'railway master') {
        if (!zone) throw new ValidationError('Zone missing in profile.');
        contractQuery = contractQuery.where('zone', '==', zone);
        isFilteredByContract = true;
      } else if ((!userRole.includes("super admin") && userRole.includes("admin")) || userRole.includes('supervisor')) {
        if (!division) throw new ValidationError('Division missing in profile.');
        contractQuery = contractQuery.where('division', '==', division);
        isFilteredByContract = true;
      }

      if (queryContractType) {
        contractQuery = contractQuery.where('contractType', '==', queryContractType);
      }

      if (isFilteredByContract) {
        const contractSnap = await contractQuery.limit(200).get();
        if (!contractSnap.empty) {
          finalEntityIds = [...new Set(contractSnap.docs.map(doc => doc.data().entityId))];
        }
      }
    }

    let entityQuery = db.collection('entities');

    if (userType === 'contractor') {
      if (!entityId) throw new ValidationError('Entity ID missing.');
      entityQuery = entityQuery.where('uid', '==', entityId);
    } else if (isFilteredByContract && finalEntityIds.length > 0) {
      entityQuery = entityQuery.where('uid', 'in', finalEntityIds.slice(0, 30));
    }

    if (queryStatus) {
      entityQuery = entityQuery.where('status', '==', queryStatus);
    } else if (userType === 'railway') {
      entityQuery = entityQuery.where('status', '==', 'APPROVED');
    }

    const snapshot = await entityQuery.limit(200).get();
    if (snapshot.empty) return { count: 0, contractors: [] };

    const contractorList = [];
    snapshot.forEach(doc => {
      const data = doc.data();
      contractorList.push({
        ...data,
        uid: doc.id,
        createdAt: safeFormat(data.createdAt),
        submitted_at: safeFormat(data.submitted_at),
        approved_at: safeFormat(data.approvedAt || data.approved_at),
        updatedAt: safeFormat(data.updatedAt),
      });
    });

    return { count: contractorList.length, contractors: contractorList };
  }

  async approveEntity(approverData, uid) {
    const { uid: adminId, name, fullName, role } = approverData;
    const adminName = fullName || name || role || 'Master Admin';

    if (!uid) throw new ValidationError('Entity ID is required.');

    const docRef = db.collection('entities').doc(uid);
    const doc = await docRef.get();
    if (!doc.exists) throw new NotFoundError('Entity not found.');

    const entityName = doc.data().companyName;
    await docRef.update({
      status: 'APPROVED',
      approvedBy: adminId,
      approvedByName: adminName,
      approvedAt: new Date().toISOString(),
      updatedBy: adminId,
      updatedByName: adminName,
      updatedAt: new Date().toISOString(),
      rejectedBy: null,
      rejectedByName: null,
      rejectedAt: null,
      suspendedBy: null,
      suspendedByName: null,
      suspendedAt: null,
      approved_at: null,
    });

    console.log(`(Master) Entity ${entityName} (${uid}) APPROVED by ${adminName}.`);
    return { entityName, approvedBy: adminName };
  }

  async rejectEntity(rejectorData, uid) {
    const { uid: adminId, name, fullName, role } = rejectorData;
    const adminName = fullName || name || role || 'Master Admin';

    if (!uid) throw new ValidationError('Entity ID is required.');

    const docRef = db.collection('entities').doc(uid);
    const doc = await docRef.get();
    if (!doc.exists) throw new NotFoundError('Entity not found.');

    const entityName = doc.data().companyName;
    await docRef.update({
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
      suspendedAt: null,
      reviewed_at: null,
    });

    console.log(`(Master) Entity ${entityName} (${uid}) REJECTED by ${adminName}.`);
    return { entityName, rejectedBy: adminName };
  }

  async suspendEntity(uid, suspensionReason) {
    if (!uid) throw new ValidationError('Entity ID is required.');

    const docRef = db.collection('entities').doc(uid);
    const doc = await docRef.get();
    if (!doc.exists) throw new NotFoundError('Entity not found.');

    if (doc.data().status !== 'APPROVED') {
      throw new ValidationError(`Cannot suspend an entity with status: ${doc.data().status}`);
    }

    await docRef.update({
      status: 'SUSPENDED',
      suspended_at: db.Timestamp(),
      suspensionReason: suspensionReason || null,
    });

    console.log(`(Admin) Entity ${uid} has been SUSPENDED.`);
    return { message: `Entity ${uid} has been suspended.` };
  }

  async getEntityDetails(uid) {
    if (!uid) throw new ValidationError('Entity ID (UID) is required.');

    const entityRef = db.collection('entities').doc(uid);
    const contractsRef = db.collection('contracts');

    const entityDoc = await entityRef.get();
    if (!entityDoc.exists) throw new NotFoundError('Entity not found.');

    const entityData = entityDoc.data();
    const contractsSnapshot = await contractsRef.where('entityId', '==', uid).limit(200).get();

    const contractsList = [];
    if (!contractsSnapshot.empty) {
      contractsSnapshot.forEach(doc => { contractsList.push(doc.data()); });
    }

    return { details: entityData, contracts: contractsList };
  }
}

export const entityService = new EntityService();
