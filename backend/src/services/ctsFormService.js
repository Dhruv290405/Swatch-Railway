import { db } from '../database/index.js';
import { NotFoundError, ValidationError } from '../errors/index.js';
import { generateFormId } from '../utils/helpers.js';

class CtsFormService {
  async submitCtsForm(userData, body) {
    const contractorSupervisor = userData;
    const {
      trainId, formDateTime, platform, actArrival, actDeparture,
      workStart, workEnd, allowedWindow, lateYN, coachesInRake, coachesAttended,
      attendanceStaff, garbageDisposed, nominatedLocation, occupiedToilets, notes,
      submittedTo, signature, contractId
    } = body;
    const effectiveContractId = String(contractId || contractorSupervisor.contractId || '').trim();
    const effectiveTrainId = String(trainId || '').trim();

    if (!effectiveTrainId || !effectiveContractId || !formDateTime) {
      throw new ValidationError("Missing mandatory fields (Train or Contract).");
    }

    const [contractDoc, trainDoc, userDoc] = await Promise.all([
      db.collection('contracts').doc(effectiveContractId).get(),
      db.collection('trains').doc(effectiveTrainId).get(),
      submittedTo?.railwayEmployeeId ? db.collection('users').doc(submittedTo.railwayEmployeeId).get() : Promise.resolve(null)
    ]);

    if (!contractDoc.exists) throw new NotFoundError("Contract not found.");
    if (!trainDoc.exists) throw new NotFoundError("Train not found.");

    const contractData = contractDoc.data();
    const trainData = trainDoc.data();
    const railwayEmployeeName = userDoc?.exists ? (userDoc.data().fullName || userDoc.data().name || "Unknown") : "N/A";

    const stationName = contractorSupervisor.division || "Unknown Station";
    const agreementNo = contractData.contractNumber || "N/A";
    const agreementDate = contractData.startDate || "N/A";
    const contractorName = contractData.agencyName || contractData.entityName || "N/A";
    const jobDate = new Date().toISOString().split('T')[0];

    const applicableFor = trainData.TrainApplicableFor || [];
    if (!applicableFor.includes('CTS')) {
      throw new ValidationError("This Train is not applicable for CTS service.");
    }

    const newFormId = await generateFormId('cts', contractorSupervisor.division);

    const ctsFormData = {
      uid: newFormId, formId: newFormId, contractId: effectiveContractId,
      station: stationName, agreementNo, agreementDate, contractorName, jobDate,
      trainId: effectiveTrainId, trainNumber: trainData.trainNo || "", trainName: trainData.trainName || "",
      formDateTime, actArrival, actDeparture, workStart, workEnd,
      platform: platform || null, allowedWindow: allowedWindow || null,
      lateYN: lateYN || "No", coachesInRake: coachesInRake || 0,
      coachesAttended: coachesAttended || 0, attendanceStaff: attendanceStaff || [],
      garbageDisposed: garbageDisposed || false, nominatedLocation: nominatedLocation || null,
      occupiedToilets: occupiedToilets || 0, notes: notes || "",
      submittedTo: {
        railwayEmployeeId: submittedTo?.railwayEmployeeId || null,
        railwayEmployeeName,
        division: submittedTo?.division || contractorSupervisor.division,
        depot: submittedTo?.depot || contractorSupervisor.depot
      },
      signature: { name: signature?.name || null, date: signature?.date || new Date().toISOString() },
      status: 'SUBMITTED',
      submittedById: contractorSupervisor.uid,
      submittedByName: contractorSupervisor.fullName || contractorSupervisor.name,
      submittedByZone: contractorSupervisor.zone || null,
      submittedByDivision: contractorSupervisor.division || null,
      submittedByDepot: contractorSupervisor.depot || null,
      submittedByEntityId: contractorSupervisor.entityId || null,
      submittedByEntityName: contractorSupervisor.entityName || contractorName,
      createdAt: db.Timestamp()
    };

    await db.collection('ctsForms').doc(newFormId).set(ctsFormData);
    return { message: 'CTS Form submitted successfully.', uid: newFormId, railwayEmployeeName };
  }

  async getCtsForms(filters) {
    const { user, query } = filters;
    const { uid, role, userType, zone, division, entityId } = user;
    const { status, type } = query;

    let firestoreQuery = db.collection('ctsForms');
    const userRole = (role || "").toLowerCase().replace(/_/g, " ");
    const isMaster = userRole.includes('master') || userRole === 'company master';
    const isAdmin = (!userRole.includes("super admin") && userRole.includes("admin"));

    if (userType === 'railway') {
      if (isMaster) {
        if (zone) firestoreQuery = firestoreQuery.where('submittedByZone', '==', zone);
      } else if (isAdmin) {
        firestoreQuery = firestoreQuery.where('submittedByDivision', '==', division);
      } else {
        firestoreQuery = firestoreQuery.where('submittedTo.railwayEmployeeId', '==', uid);
      }
    } else if (userType === 'contractor') {
      if (!entityId) throw new ValidationError("Company ID missing.");
      firestoreQuery = firestoreQuery.where('submittedByEntityId', '==', entityId);
      if (isMaster) {
      } else if (isAdmin) {
        firestoreQuery = firestoreQuery.where('submittedByDivision', '==', division);
      } else {
        firestoreQuery = firestoreQuery.where('submittedById', '==', uid);
      }
    }

    if (status) {
      firestoreQuery = firestoreQuery.where('status', '==', status);
    } else if (type === 'history') {
      firestoreQuery = firestoreQuery.where('status', 'in', ['SCORED', 'LOCKED', 'AUTO-APPROVED', 'REJECTED_BY_RAILWAY']);
    } else {
      firestoreQuery = firestoreQuery.where('status', 'in', ['SUBMITTED', 'RE-SUBMITTED', 'APPROVED_BY_RAILWAY', 'SCORING_IN_PROGRESS']);
    }

    try {
      const snapshot = await firestoreQuery.limit(200).get();
      const list = [];
      snapshot.forEach(doc => { list.push({ id: doc.id, ...doc.data() }); });
      list.sort((a, b) => {
        const dateA = a.createdAt ? (a.createdAt.toDate ? a.createdAt.toDate() : new Date(a.createdAt)) : new Date(0);
        const dateB = b.createdAt ? (b.createdAt.toDate ? b.createdAt.toDate() : new Date(b.createdAt)) : new Date(0);
        return dateB - dateA;
      });
      return { count: list.length, forms: list };
    } catch (error) {
      if (error.code === 'FAILED_PRECONDITION') {
        throw new ValidationError('Index Missing. Check Firebase Console.');
      }
      throw error;
    }
  }

  async getCtsFormById(uid) {
    if (!uid) throw new ValidationError("Form ID is required.");
    const doc = await db.collection('ctsForms').doc(uid).get();
    if (!doc.exists) throw new NotFoundError("Form not found.");
    return doc.data();
  }

  async approveManpower(user, formId) {
    const formDocRef = db.collection('ctsForms').doc(formId);
    const doc = await formDocRef.get();

    if (!doc.exists) throw new NotFoundError('CTS Form not found.');

    const formData = doc.data();
    if (formData.submittedTo.railwayEmployeeId !== user.uid) {
      throw new ValidationError('You are not authorized to approve this form.');
    }
    if (formData.status !== 'SUBMITTED' && formData.status !== 'RE-SUBMITTED') {
      throw new ValidationError(`Form status is already ${formData.status}.`);
    }

    await formDocRef.update({
      status: 'APPROVED_BY_RAILWAY',
      manpowerApprovedAt: db.Timestamp()
    });

    return { message: 'CTS Form approved for scoring.' };
  }

  async rejectForm(user, formId, body) {
    const { rejectionComments } = body;
    if (!rejectionComments) {
      throw new ValidationError('Rejection comments are required.');
    }

    const formDocRef = db.collection('ctsForms').doc(formId);
    const doc = await formDocRef.get();

    if (!doc.exists) throw new NotFoundError('CTS Form not found.');

    const formData = doc.data();
    if (formData.submittedTo.railwayEmployeeId !== user.uid) {
      throw new ValidationError('You are not authorized to reject this form.');
    }

    const allowedStatuses = ['SUBMITTED', 'RE-SUBMITTED', 'APPROVED_BY_RAILWAY', 'SCORING_IN_PROGRESS'];
    if (!allowedStatuses.includes(formData.status)) {
      throw new ValidationError(`Cannot reject a form with status: ${formData.status}`);
    }

    await formDocRef.update({
      status: 'REJECTED_BY_RAILWAY',
      rejectionComments,
      rejectedAt: db.Timestamp(),
      rejectedByName: user.fullName || user.name
    });

    return { message: 'Form successfully rejected.' };
  }

  async submitScoring(user, formId, body) {
    const {
      inspectionHeader, coachEvaluationTable, machinesUsed,
      chemicals, railwaySignatureName, railwaySignatureDate
    } = body;

    if (!inspectionHeader || !coachEvaluationTable || !railwaySignatureName || !chemicals) {
      throw new ValidationError('Inspection Header, Evaluation Table, Chemicals, and Signature are required.');
    }

    const formDocRef = db.collection('ctsForms').doc(formId);
    const doc = await formDocRef.get();

    if (!doc.exists) throw new NotFoundError('CTS Form not found.');

    const formData = doc.data();
    if (formData.submittedTo.railwayEmployeeId !== user.uid) {
      throw new ValidationError('You are not authorized to score this form.');
    }
    if (formData.status !== 'APPROVED_BY_RAILWAY' && formData.status !== 'SCORING_IN_PROGRESS') {
      throw new ValidationError(`Cannot score form. Status is ${formData.status}.`);
    }

    let totalAllCoachesScore = 0;
    const processedEvaluation = coachEvaluationTable.map(coach => {
      const coachTotal = (Number(coach.jetCleaningScore) || 0) +
        (Number(coach.basinCleaningScore) || 0) +
        (Number(coach.disposalScore) || 0);

      totalAllCoachesScore += coachTotal;

      let coachGrade = 'D';
      if (coachTotal >= 8) coachGrade = 'A';
      else if (coachTotal >= 6) coachGrade = 'B';
      else if (coachTotal >= 4) coachGrade = 'C';

      return { ...coach, totalScore: coachTotal, grade: coachGrade };
    });

    const averageScore = processedEvaluation.length > 0
      ? (totalAllCoachesScore / processedEvaluation.length).toFixed(2)
      : 0;

    let overallGrade = 'Fail';
    if (averageScore >= 8) overallGrade = 'A';
    else if (averageScore >= 6) overallGrade = 'B';
    else if (averageScore >= 4) overallGrade = 'C';
    else overallGrade = 'D';

    await formDocRef.update({
      status: 'SCORED',
      scoringInProgress: false,
      ratingDetails: {
        inspectionHeader,
        coachEvaluationTable: processedEvaluation,
        machinesUsed: Array.isArray(machinesUsed) ? machinesUsed : [],
        chemicals: Array.isArray(chemicals) ? chemicals : [],
        totalPenalty: 0,
        summary: {
          averageScore: Number(averageScore),
          overallGrade
        }
      },
      railwaySignature: {
        name: railwaySignatureName || user.fullName,
        date: railwaySignatureDate || new Date().toISOString()
      },
      ratedAt: db.Timestamp()
    });

    return { message: 'CTS Scoring submitted successfully with chemical details.', averageScore, overallGrade };
  }

  async acceptRating(user, formId) {
    const formDocRef = db.collection('ctsForms').doc(formId);
    const doc = await formDocRef.get();

    if (!doc.exists) throw new NotFoundError('CTS Form not found.');

    const formData = doc.data();
    if (formData.submittedById !== user.uid) {
      throw new ValidationError('You are not authorized to accept this rating.');
    }

    if (formData.status === 'LOCKED' || formData.status === 'AUTO-APPROVED') {
      throw new ValidationError('This form is already locked.');
    }
    if (formData.status !== 'SCORED') {
      throw new ValidationError(`Cannot accept rating. Form status is ${formData.status}`);
    }

    await formDocRef.update({
      status: 'LOCKED',
      contractorAcceptedAt: db.Timestamp(),
      completedAt: db.Timestamp()
    });

    return { message: 'Rating accepted. CTS Form is now locked.' };
  }

  async resubmit(user, formId, body) {
    const {
      trainId, formDateTime, platform, actArrival, actDeparture,
      workStart, workEnd, allowedWindow, lateYN, coachesInRake, coachesAttended,
      attendanceStaff, garbageDisposed, nominatedLocation, occupiedToilets, notes,
      signature, contractorRemarks, resubmitSign
    } = body;

    if (!resubmitSign) {
      throw new ValidationError('Resubmit Signature is required to submit the form again.');
    }

    const formDocRef = db.collection('ctsForms').doc(formId);
    const doc = await formDocRef.get();

    if (!doc.exists) throw new NotFoundError('CTS Form not found.');

    const existingData = doc.data();
    if (existingData.submittedById !== user.uid) {
      throw new ValidationError('You are not authorized to resubmit this form.');
    }
    if (existingData.status !== 'REJECTED_BY_RAILWAY') {
      throw new ValidationError(`Cannot resubmit form. Current status is ${existingData.status}`);
    }

    let trainName = existingData.trainName;
    let trainNumber = existingData.trainNumber;

    if (trainId && trainId !== existingData.trainId) {
      const trainDoc = await db.collection('trains').doc(trainId).get();
      if (trainDoc.exists) {
        const tData = trainDoc.data();
        trainName = tData.trainName || trainName;
        trainNumber = tData.trainNo || tData.trainNumber || trainNumber;
      }
    }

    const updateData = {
      trainId: trainId || existingData.trainId,
      trainName,
      trainNumber,
      formDateTime: formDateTime || existingData.formDateTime,
      actArrival: actArrival || existingData.actArrival,
      actDeparture: actDeparture || existingData.actDeparture,
      workStart: workStart || existingData.workStart,
      workEnd: workEnd || existingData.workEnd,
      platform: platform || existingData.platform,
      allowedWindow: allowedWindow || existingData.allowedWindow,
      lateYN: lateYN || existingData.lateYN,
      coachesInRake: coachesInRake || existingData.coachesInRake,
      coachesAttended: coachesAttended || existingData.coachesAttended,
      attendanceStaff: attendanceStaff || existingData.attendanceStaff,
      garbageDisposed: garbageDisposed !== undefined ? garbageDisposed : existingData.garbageDisposed,
      nominatedLocation: nominatedLocation || existingData.nominatedLocation,
      occupiedToilets: occupiedToilets || existingData.occupiedToilets,
      notes: notes || existingData.notes,
      signature: signature || existingData.signature,
      resubmitSignature: resubmitSign,
      status: 'RE-SUBMITTED',
      resubmittedAt: db.Timestamp()
    };

    if (contractorRemarks) {
      updateData.contractorRemarks = contractorRemarks;
    }

    await formDocRef.update(updateData);

    return { message: 'CTS Form has been re-submitted successfully.', uid: formId };
  }
}

export const ctsFormService = new CtsFormService();
