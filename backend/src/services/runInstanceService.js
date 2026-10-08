import { db, admin } from '../database/index.js';
import logger from '../logger/index.js';
import { ValidationError, NotFoundError, ConflictError, FirestoreError } from '../errors/index.js';
import { GARBAGE_TIMES, WATER_CHECK_TIMES, SAFETY_INSPECTION_TIMES, PETTY_REPAIR_TIMES, BERTH_INSPECTION_TIMES, AC_COACH_PREFIXES } from '../config/constants.js';
import { isACCoach } from '../utils/helpers.js';

async function generateTaskInstancesForRun(runData) {
  const CHUNK_SIZE = 400;
  let batch = db.batch();
  let taskCount = 0;
  let opCount = 0;
  const departureDate = runData.departureDate || new Date().toISOString().split('T')[0];
  for (const coach of runData.coaches) {
    if (!coach.workerId) continue;
    const coachNo = coach.coachPosition || coach.coachNo || 'N/A';
    const workerId = coach.workerId;
    const workerName = coach.workerName || 'Unknown';
    
    const DYNAMIC_CLEANING_TIMES = [
      '00:00', '02:00', '04:00', '06:00', '07:00', '08:00', '09:00',
      '11:00', '13:00', '15:00', '17:00', '19:00', '20:00', '21:00', '22:00'
    ];
    for (const timeSlot of DYNAMIC_CLEANING_TIMES) {
      const hour = parseInt(timeSlot.split(':')[0]);
      let taskTypeName = 'toilet_cleaning';
      let displayName = 'Toilet Cleaning & Disinfection';
      if (hour >= 9 && hour < 20) { taskTypeName = 'coach_cleaning'; displayName = 'Compartment Cleaning'; }
      const headerId = `${runData.runInstanceId}_${taskTypeName}_${timeSlot.replace(':', '')}`;
      const headerRef = db.collection('task_headers').doc(headerId);
      batch.set(headerRef, { headerId, runInstanceId: runData.runInstanceId, trainNo: runData.trainNo, taskType: taskTypeName, displayName, scheduledTime: timeSlot, scheduledDate: departureDate, status: 'PLANNED', taskSource: 'SYSTEM', workerId, workerName, coachNo, childTaskIds: [], createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() });
      opCount++;
      const detailId = `${headerId}_${coachNo}`;
      const detailRef = db.collection('task_details').doc(detailId);
      batch.set(detailRef, { detailId, headerId, runInstanceId: runData.runInstanceId, trainNo: runData.trainNo, coachNo, workerId, workerName, taskType: taskTypeName, scheduledTime: timeSlot, scheduledDate: departureDate, toiletStatus: null, washBasinStatus: null, dustbinStatus: null, consumableStatus: null, status: 'PLANNED', beforePhoto: null, afterPhoto: null, gpsLatitude: null, gpsLongitude: null, employeeId: workerId, deviceId: null, mobileNumber: null, checklist: null, remarks: null, completionTime: null, createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() });
      opCount++;
      const oldTaskRef1 = db.collection('task_instances').doc(detailId);
      batch.set(oldTaskRef1, { taskId: detailId, runInstanceId: runData.runInstanceId, isParentTask: false, trainNo: runData.trainNo, coachNo, workerId, workerName, taskType: taskTypeName, taskName: displayName, frequencyIndex: timeSlot, scheduledTime: timeSlot, status: 'PENDING', createdAt: new Date().toISOString() });
      opCount++;
      batch.update(headerRef, { childTaskIds: admin.firestore.FieldValue.arrayUnion(detailId) });
      opCount++;
      taskCount++;
      if (opCount >= CHUNK_SIZE) { await batch.commit(); batch = db.batch(); opCount = 0; }
    }
    for (const timeSlot of GARBAGE_TIMES) {
      const garbageId = `${runData.runInstanceId}_garbage_${timeSlot.replace(':', '')}_${coachNo}`;
      const garbageRef = db.collection('garbage_tasks').doc(garbageId);
      batch.set(garbageRef, { id: garbageId, runInstanceId: runData.runInstanceId, trainNo: runData.trainNo, coachNo, workerId, workerName, scheduledTime: timeSlot, scheduledDate: departureDate, isPreTerminal: false, status: 'PENDING', beforePhoto: null, afterPhoto: null, gpsLatitude: null, gpsLongitude: null, completedAt: null, createdAt: new Date().toISOString() });
      opCount++;
      const oldTaskRef2 = db.collection('task_instances').doc(garbageId);
      batch.set(oldTaskRef2, { taskId: garbageId, runInstanceId: runData.runInstanceId, isParentTask: false, trainNo: runData.trainNo, coachNo, workerId, workerName, taskType: 'garbage', taskName: 'Garbage Collection', frequencyIndex: timeSlot, scheduledTime: timeSlot, status: 'PENDING', createdAt: new Date().toISOString() });
      opCount++;
      taskCount++;
      if (opCount >= CHUNK_SIZE) { await batch.commit(); batch = db.batch(); opCount = 0; }
    }
    for (const timeSlot of WATER_CHECK_TIMES) {
      const waterId = `${runData.runInstanceId}_water_${timeSlot.replace(':', '')}_${coachNo}`;
      const waterRef = db.collection('water_checks').doc(waterId);
      batch.set(waterRef, { id: waterId, runInstanceId: runData.runInstanceId, trainNo: runData.trainNo, coachNo, workerId, workerName, checkTime: timeSlot, checkDate: departureDate, waterStatus: 'pending', lowWaterAlert: false, wateringPointSchedule: null, status: 'PENDING', photoUrl: null, completedAt: null, createdAt: new Date().toISOString() });
      opCount++;
      const oldTaskRef3 = db.collection('task_instances').doc(waterId);
      batch.set(oldTaskRef3, { taskId: waterId, runInstanceId: runData.runInstanceId, isParentTask: false, trainNo: runData.trainNo, coachNo, workerId, workerName, taskType: 'water', taskName: 'Water Check', frequencyIndex: timeSlot, scheduledTime: timeSlot, status: 'PENDING', createdAt: new Date().toISOString() });
      opCount++;
      taskCount++;
      if (opCount >= CHUNK_SIZE) { await batch.commit(); batch = db.batch(); opCount = 0; }
    }
    for (const timeSlot of SAFETY_INSPECTION_TIMES) {
      const supervisorId = runData.supervisorId || runData.contractorSupervisorId || null;
      if (!supervisorId) continue;
      const supervisorName = runData.supervisorName || 'Supervisor';

      const safetyId = `${runData.runInstanceId}_safety_${timeSlot.replace(':', '')}_${coachNo}`;
      const safetyRef = db.collection('safety_checks').doc(safetyId);
      batch.set(safetyRef, { id: safetyId, runInstanceId: runData.runInstanceId, trainNo: runData.trainNo, coachNo, workerId: supervisorId, workerName: supervisorName, scheduledTime: timeSlot, scheduledDate: departureDate, fireExtinguisherStatus: null, fsdsStatus: null, cctvStatus: null, emergencyEquipmentStatus: null, photos: [], deficiencyReports: [], status: 'PENDING', remarks: null, completedAt: null, createdAt: new Date().toISOString() });
      opCount++;
      const oldTaskRef4 = db.collection('task_instances').doc(safetyId);
      batch.set(oldTaskRef4, { taskId: safetyId, runInstanceId: runData.runInstanceId, isParentTask: false, trainNo: runData.trainNo, coachNo, workerId: supervisorId, workerName: supervisorName, taskType: 'safety', taskName: 'Safety Inspection', frequencyIndex: timeSlot, scheduledTime: timeSlot, status: 'PENDING', createdAt: new Date().toISOString() });
      opCount++;
      taskCount++;
      if (opCount >= CHUNK_SIZE) { await batch.commit(); batch = db.batch(); opCount = 0; }
    }
    for (const timeSlot of PETTY_REPAIR_TIMES) {
      const supervisorId = runData.supervisorId || runData.contractorSupervisorId || null;
      if (!supervisorId) continue;
      const supervisorName = runData.supervisorName || 'Supervisor';

      const repairId = `${runData.runInstanceId}_repair_${timeSlot.replace(':', '')}_${coachNo}`;
      const repairRef = db.collection('petty_repairs').doc(repairId);
      batch.set(repairRef, { id: repairId, runInstanceId: runData.runInstanceId, trainNo: runData.trainNo, coachNo, workerId: supervisorId, workerName: supervisorName, inspectionTime: timeSlot, inspectionDate: departureDate, items: { latches: 'ok', windows: 'ok', doors: 'ok', seats: 'ok', lights: 'ok', fans: 'ok', taps: 'ok', flush: 'ok' }, isEscalated: false, escalatedTo: null, status: 'PENDING', remarks: null, createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() });
      opCount++;
      const oldTaskRef5 = db.collection('task_instances').doc(repairId);
      batch.set(oldTaskRef5, { taskId: repairId, runInstanceId: runData.runInstanceId, isParentTask: false, trainNo: runData.trainNo, coachNo, workerId: supervisorId, workerName: supervisorName, taskType: 'repair', taskName: 'Petty Repair', frequencyIndex: timeSlot, scheduledTime: timeSlot, status: 'PENDING', createdAt: new Date().toISOString() });
      opCount++;
      taskCount++;
      if (opCount >= CHUNK_SIZE) { await batch.commit(); batch = db.batch(); opCount = 0; }
    }
  }
  for (const coach of runData.coaches) {
    const isAC = /^[ABHME]/i.test(coach.coachPosition || '') || (coach.coachType && coach.coachType.toUpperCase().includes('AC'));
    if (!isAC || !coach.attendantId) continue;
    const coachNo = coach.coachPosition || coach.coachNo || 'N/A';
    const attendantId = coach.attendantId;
    const attendantName = coach.attendantName || 'Unknown Attendant';
    const LINEN_SCHEDULE = [
      { task: 'Linen distribution', time: '06:00' },
      { task: 'Linen verification', time: '14:00' },
      { task: 'Linen collection', time: '20:00' },
      { task: 'Stock confirmation', time: '21:00' },
      { task: 'Coach handover', time: '22:00' }
    ];
    for (const schedule of LINEN_SCHEDULE) {
      const timeSlot = schedule.time;
      const displayName = schedule.task;
      const linenId = `${runData.runInstanceId}_linen_${displayName.replace(/\s+/g, '')}_${coachNo}`;
      const linenRef = db.collection('linen_tasks').doc(linenId);
      batch.set(linenRef, { id: linenId, runInstanceId: runData.runInstanceId, trainNo: runData.trainNo, coachNo, coachType: coach.coachType || 'AC', assignedTo: attendantId, assignedToName: attendantName, workerType: 'ATTENDANT', taskType: 'LINEN_CHANGE', displayName, scheduledTime: timeSlot, scheduledDate: departureDate, status: 'PENDING', linenItemsChecklist: { bedsheet: false, pillowCover: false, blanket: false, towel: false }, beforePhoto: null, afterPhoto: null, remarks: null, completedAt: null, createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() });
      opCount++;
      const oldTaskRef6 = db.collection('task_instances').doc(linenId);
      batch.set(oldTaskRef6, { taskId: linenId, runInstanceId: runData.runInstanceId, isParentTask: false, trainNo: runData.trainNo, coachNo, workerId: attendantId, workerName: attendantName, taskType: 'LINEN_CHANGE', taskName: displayName, frequencyIndex: timeSlot, scheduledTime: timeSlot, status: 'PENDING', createdAt: new Date().toISOString() });
      opCount++;
      taskCount++;
      if (opCount >= CHUNK_SIZE) { await batch.commit(); batch = db.batch(); opCount = 0; }
    }
    for (const timeSlot of BERTH_INSPECTION_TIMES) {
      const berthId = `${runData.runInstanceId}_berth_${timeSlot.replace(':', '')}_${coachNo}`;
      const berthRef = db.collection('berth_inspections').doc(berthId);
      batch.set(berthRef, { id: berthId, runInstanceId: runData.runInstanceId, trainNo: runData.trainNo, coachNo, coachType: coach.coachType || 'AC', assignedTo: attendantId, assignedToName: attendantName, workerType: 'ATTENDANT', taskType: 'BERTH_INSPECTION', displayName: 'Berth & Cabin Inspection', scheduledTime: timeSlot, scheduledDate: departureDate, status: 'PENDING', berthChecklist: { cushionCondition: null, berthLatch: null, readingLight: null, acVent: null, windowBlind: null }, deficiencies: [], beforePhoto: null, afterPhoto: null, remarks: null, completedAt: null, createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() });
      opCount++;
      const oldTaskRef7 = db.collection('task_instances').doc(berthId);
      batch.set(oldTaskRef7, { taskId: berthId, runInstanceId: runData.runInstanceId, isParentTask: false, trainNo: runData.trainNo, coachNo, workerId: attendantId, workerName: attendantName, taskType: 'BERTH_INSPECTION', taskName: 'Berth & Cabin Inspection', frequencyIndex: timeSlot, scheduledTime: timeSlot, status: 'PENDING', createdAt: new Date().toISOString() });
      opCount++;
      taskCount++;
      if (opCount >= CHUNK_SIZE) { await batch.commit(); batch = db.batch(); opCount = 0; }
    }
  }
  if (taskCount > 0) { await batch.commit(); logger.info('RunInstance', `[New Engine] Generated ${taskCount} tasks for Run ${runData.runInstanceId}`); }
}

async function generatePreTerminalGarbageTasks(runInstanceId) {
  try {
    const runDoc = await db.collection('RunInstance').doc(runInstanceId).get();
    if (!runDoc.exists) return;
    const runData = runDoc.data();
    const CHUNK_SIZE = 400;
    let batch = db.batch();
    let count = 0;
    let opCount = 0;
    for (const coach of (runData.coaches || [])) {
      const effectiveWorkerId = coach.workerId || coach.janitorId || null;
      if (!effectiveWorkerId) continue;
      const coachNo = coach.coachPosition || coach.coachNo || 'N/A';
      const timeSlot = 'terminal';
      const garbageId = `${runInstanceId}_garbage_${timeSlot}_${coachNo}`;
      const garbageRef = db.collection('garbage_tasks').doc(garbageId);
      batch.set(garbageRef, { id: garbageId, runInstanceId, trainNo: runData.trainNo, coachNo, workerId: effectiveWorkerId, workerName: coach.workerName || coach.janitorName || 'Unknown', scheduledTime: timeSlot, scheduledDate: new Date().toISOString().split('T')[0], isPreTerminal: true, status: 'PENDING', beforePhoto: null, afterPhoto: null, gpsLatitude: null, gpsLongitude: null, completedAt: null, createdAt: new Date().toISOString() });
      opCount++;
      const oldTaskRef = db.collection('task_instances').doc(garbageId);
      batch.set(oldTaskRef, { taskId: garbageId, runInstanceId: runData.runInstanceId, isParentTask: false, trainNo: runData.trainNo, coachNo, workerId: effectiveWorkerId, workerName: coach.workerName || coach.janitorName || 'Unknown', taskType: 'garbage', taskName: 'Garbage Collection (Pre-Terminal)', frequencyIndex: timeSlot, scheduledTime: timeSlot, status: 'PENDING', createdAt: new Date().toISOString() });
      opCount++;
      count++;
      if (opCount >= CHUNK_SIZE) { await batch.commit(); batch = db.batch(); opCount = 0; }
    }
    if (count > 0) { await batch.commit(); logger.info('RunInstance', `Generated ${count} pre-terminal garbage tasks for ${runInstanceId}`); }
  } catch (error) { logger.error('RunInstance', '(PreTerminalGarbage) Error:', error); }
}

async function generateTasksFromMasters(runData) {
  // Placeholder for CM/CA configurable task generation
}

async function generateClosureTasks(runInstanceId, arrivalTime, currentData) {
  // Placeholder for journey closure task generation
}

async function logAudit(params) {
  try {
    await db.collection('audit_logs').add({ ...params, timestamp: admin.firestore.FieldValue.serverTimestamp() });
  } catch (_) {}
}

class RunInstanceService {
  async createRunInstance(creatorData, body) {
    const { instanceId, coaches, departureDate } = body;
    if (!instanceId || !coaches || !Array.isArray(coaches) || !departureDate) {
      throw new ValidationError('Missing required fields', 'instanceId, coaches array, and departureDate are mandatory.');
    }

    const existingCheck = await db.collection('RunInstance').where('instanceId', '==', instanceId).where('departureDate', '==', departureDate).limit(1).get();
    if (!existingCheck.empty) {
      throw new ConflictError(`Instance '${instanceId}' is already assigned to a run on ${departureDate}.`);
    }

    const trainPairDoc = await db.collection('TrainPairs').doc(instanceId).get();
    if (!trainPairDoc.exists) {
      throw new NotFoundError('Train Instance (Rake) not found in Pool');
    }
    const pairData = trainPairDoc.data();
    const parentTrainDoc = await db.collection('trains').doc(pairData.parentTrainId).get();
    const trainData = parentTrainDoc.exists ? parentTrainDoc.data() : {};

    const coachesWithNames = await Promise.all(coaches.map(async (c) => {
      const actualJanitorId = c.janitorId || c.workerId || null;
      let janitorName = c.janitorName || "Unknown Worker";
      if (actualJanitorId && (!c.janitorName || c.janitorName === "Unknown Worker")) {
        const workerDoc = await db.collection('users').doc(actualJanitorId).get();
        if (workerDoc.exists) { janitorName = workerDoc.data().fullName || workerDoc.data().name || "Unknown Worker"; }
      }
      let actualAttendantName = c.attendantName || null;
      if (c.attendantId && !actualAttendantName) {
        const attDoc = await db.collection('users').doc(c.attendantId).get();
        if (attDoc.exists) { actualAttendantName = attDoc.data().fullName || attDoc.data().name || 'Unknown'; }
      }
      return { coachPosition: c.coachPosition || null, coachType: c.coachType || null, janitorId: actualJanitorId, janitorName, workerId: actualJanitorId, workerName: janitorName, attendantId: c.attendantId || null, attendantName: actualAttendantName, janitorTasks: c.janitorTasks || [], attendantTasks: c.attendantTasks || [], tasks: c.tasks || c.janitorTasks || [], attendanceStatus: 'Pending' };
    }));

    const { uid, name, email, role, division: userDivision, zone: userZone } = creatorData;
    const workerCoachCount = {};
    // The mobile UI allows up to 3 coaches per worker (obhs_create_run_screen),
    // so match that limit here instead of rejecting valid assignments.
    const MAX_COACHES_PER_WORKER = 3;
    for (const c of coachesWithNames) {
      if (c.workerId) {
        workerCoachCount[c.workerId] = (workerCoachCount[c.workerId] || 0) + 1;
        if (workerCoachCount[c.workerId] > MAX_COACHES_PER_WORKER) {
          throw new ValidationError('Coach Assignment Limit', `Worker ${c.workerId} has been assigned to more than ${MAX_COACHES_PER_WORKER} coaches. Maximum ${MAX_COACHES_PER_WORKER} coaches per worker allowed.`);
        }
      }
      if (c.attendantId) {
        workerCoachCount[c.attendantId] = (workerCoachCount[c.attendantId] || 0) + 1;
        if (workerCoachCount[c.attendantId] > MAX_COACHES_PER_WORKER) {
          throw new ValidationError('Coach Assignment Limit', `Worker ${c.attendantId} has been assigned to more than ${MAX_COACHES_PER_WORKER} coaches. Maximum ${MAX_COACHES_PER_WORKER} coaches per worker allowed.`);
        }
      }

      if (c.coachPosition || c.coachType) {
        // coachPosition is often a number (1, 2, ...) and coachType carries the
        // real class (A1, B1, CC, ...). Mirror the app's AC test exactly so a
        // coach the UI treats as AC is never rejected as non-AC here.
        const typeUpper = String(c.coachType || '').toUpperCase();
        const isAC = isACCoach(c.coachType) ||
          typeUpper.includes('AC') || typeUpper.includes('A1') ||
          typeUpper.includes('A2') || typeUpper.includes('A3') ||
          typeUpper.includes('B1') || typeUpper.includes('CC') ||
          /^[ABHMCE]/i.test(String(c.coachPosition || ''));

        if (!isAC && c.attendantId) {
          throw new ValidationError('Assignment Error', `Attendants can only be assigned to AC coaches. Coach ${c.coachPosition || c.coachType} is not an AC coach.`);
        }

        if (isAC && (!c.attendantId || !c.workerId)) {
          throw new ValidationError('Train Formation Error', `AC Coach ${c.coachPosition || c.coachType} must have BOTH an Attendant and a Janitor assigned for their distinct tasks.`);
        }
      }
    }

    const userName = name || email || role || 'Unknown';
    const runInstanceRef = db.collection('RunInstance').doc();
    const newRunData = {
      runInstanceId: runInstanceRef.id, instanceId, departureDate, trainNo: pairData.trainNo,
      trainName: pairData.trainName, inboundTrainNo: pairData.inboundTrainNo, outboundTrainNo: pairData.outboundTrainNo,
      parentTrainId: pairData.parentTrainId, division: trainData.division || userDivision || null, zone: trainData.zone || userZone || null,
      depot: trainData.depot || null, journeyStartTime: pairData.journeyStartTime || null,
      journeyEndTime: pairData.journeyEndTime || null,
      scheduledDeparture: `${departureDate}T${pairData.journeyStartTime || '00:00:00'}.000Z`,
      numberOfCoaches: coachesWithNames.length, coaches: coachesWithNames, status: 'Active',
      attendanceCaptured: false, taskExecutionScore: 0, actualDeparture: new Date().toISOString(), actualArrival: null,
      createdAt: new Date().toISOString(), createdBy: uid, createdByName: userName
    };
    await runInstanceRef.set(newRunData);
    await db.collection('TrainPairs').doc(instanceId).update({ status: 'Active', lastAssignedDate: departureDate });

    // Generate tasks immediately for all assigned workers
    try {
      await generateTaskInstancesForRun(newRunData);
      await generatePreTerminalGarbageTasks(runInstanceRef.id);
      await generateTasksFromMasters(newRunData);
      logger.info('RunInstance', `Tasks generated on creation for run ${runInstanceRef.id}`);
    } catch (taskErr) {
      logger.error('RunInstance', `Task generation failed for run ${runInstanceRef.id}:`, taskErr.message);
    }

    return { message: 'Run Instance (Run Calendar Entry) created successfully', id: runInstanceRef.id, data: newRunData };
  }

  async updateRunInstance(editorData, uid, body) {
    const { coaches, status } = body;
    if (!uid) {
      throw new ValidationError('runInstanceId is required.');
    }
    const runInstanceRef = db.collection('RunInstance').doc(uid);
    const doc = await runInstanceRef.get();
    if (!doc.exists) {
      throw new NotFoundError('Run Instance not found.');
    }

    const { uid: editorId, name, email, role } = editorData;
    const userName = name || email || role || 'Unknown';
    const updateData = { updatedBy: editorId, updatedByName: userName, updatedAt: new Date().toISOString() };

    if (coaches && Array.isArray(coaches)) {
      const workerNamesCache = new Map();
      const uniqueWorkerIds = new Set();
      coaches.forEach(c => { if (c.janitorId || c.workerId) uniqueWorkerIds.add(c.janitorId || c.workerId); if (c.attendantId) uniqueWorkerIds.add(c.attendantId); });
      const workerIdList = Array.from(uniqueWorkerIds).filter(id => id && typeof id === 'string');
      if (workerIdList.length > 0) {
        const batches = [];
        for (let i = 0; i < workerIdList.length; i += 30) { batches.push(workerIdList.slice(i, i + 30)); }
        await Promise.all(batches.map(async (batch) => {
          const workersSnap = await db.collection('users').where(admin.firestore.FieldPath.documentId(), 'in', batch).limit(200).get();
          workersSnap.forEach(snapDoc => { workerNamesCache.set(snapDoc.id, snapDoc.data().fullName || snapDoc.data().name || "Unknown Worker"); });
        }));
      }
      const coachesWithNames = await Promise.all(coaches.map(async (c) => {
        const actualJanitorId = c.janitorId || c.workerId || null;
        let janitorName = c.janitorName || "Unknown Worker";
        if (actualJanitorId) {
          if (workerNamesCache.has(actualJanitorId)) { janitorName = workerNamesCache.get(actualJanitorId); }
          else if (!c.janitorName || c.janitorName === "Unknown Worker") {
            try { const workerDoc = await db.collection('users').doc(actualJanitorId).get(); if (workerDoc.exists) { janitorName = workerDoc.data().fullName || workerDoc.data().name || "Unknown Worker"; workerNamesCache.set(actualJanitorId, janitorName); } } catch (err) { logger.error('RunInstance', `Error fetching janitor ${actualJanitorId}:`, err.message); }
          }
        }
        let actualAttendantName = c.attendantName || null;
        if (c.attendantId) {
          if (workerNamesCache.has(c.attendantId)) { actualAttendantName = workerNamesCache.get(c.attendantId); }
          else if (!actualAttendantName || actualAttendantName === 'Unknown') {
            try { const attDoc = await db.collection('users').doc(c.attendantId).get(); if (attDoc.exists) { actualAttendantName = attDoc.data().fullName || attDoc.data().name || 'Unknown'; workerNamesCache.set(c.attendantId, actualAttendantName); } } catch (err) { logger.error('RunInstance', `Error fetching attendant ${c.attendantId}:`, err.message); }
          }
        }
        const cType = c.coachType || '';
        const cPos = c.coachPosition || '';
        const isAC = isACCoach(cType) || /^[ABHMC]/i.test(cPos);
        if (c.attendantId && !isAC) { logger.warn('RunInstance', `[Assignment Warning] Attendant ${c.attendantId} assigned to non-AC coach ${cPos}`); }
        if (isAC && !c.attendantId && (status === 'Active' || status === 'Ready')) { logger.warn('RunInstance', `[Assignment Warning] AC Coach ${cPos} has no attendant in ${status} journey`); }
        return { coachPosition: cPos || null, coachNo: c.coachNo || cPos || null, coachType: cType || null, janitorId: actualJanitorId, janitorName, workerId: actualJanitorId, workerName: janitorName, attendantId: c.attendantId || null, attendantName: actualAttendantName, janitorTasks: c.janitorTasks || [], attendantTasks: c.attendantTasks || [], tasks: c.tasks || c.janitorTasks || [], attendanceStatus: c.attendanceStatus || 'Pending' };
      }));
      updateData.numberOfCoaches = coachesWithNames.length;
      updateData.coaches = coachesWithNames;
    }

    if (status) {
      if (status.toUpperCase() === 'CLOSED' || status.toUpperCase() === 'COMPLETED') {
        const pendingTasksSnapshot = await db.collection('task_instances').where('runInstanceId', '==', uid).where('status', 'in', ['PENDING', 'SUBMITTED']).limit(200).get();
        if (!pendingTasksSnapshot.empty) {
          throw new ValidationError(`Cannot close run instance. There are still ${pendingTasksSnapshot.size} pending or unreviewed tasks.`);
        }
      }
      updateData.status = status;
    }

    await runInstanceRef.update(updateData);
    const updatedDoc = await runInstanceRef.get();
    return { message: 'Run Instance updated successfully', runInstanceId: uid, data: { id: updatedDoc.id, ...updatedDoc.data() } };
  }

  async getRunInstancesByDivision(division, status, isSuperAdmin = false) {
    let query = db.collection('RunInstance');
    if (division) {
      query = query.where('division', '==', division);
    } else if (!isSuperAdmin) {
      return { success: false, error: 'Division is required' };
    }
    if (status) { query = query.where('status', '==', status); }
    const snapshot = await query.limit(5000).get();
    const instances = [];
    snapshot.forEach(doc => { instances.push({ id: doc.id, ...doc.data() }); });
    instances.sort((a, b) => ((b.createdAt || '') > (a.createdAt || '') ? 1 : -1));
    return { success: true, count: instances.length, data: instances };
  }

  async getRunInstancesByZone(zone, status) {
    let query = db.collection('RunInstance').where('zone', '==', zone);
    if (status) { query = query.where('status', '==', status); }
    const snapshot = await query.limit(5000).get();
    const instances = [];
    snapshot.forEach(doc => { instances.push({ id: doc.id, ...doc.data() }); });
    instances.sort((a, b) => ((b.createdAt || '') > (a.createdAt || '') ? 1 : -1));
    return { success: true, count: instances.length, data: instances };
  }

  async getRunInstanceById(uid) {
    if (!uid) {
      throw new ValidationError('runInstanceId is required.');
    }
    const doc = await db.collection('RunInstance').doc(uid).get();
    if (!doc.exists) {
      throw new NotFoundError('Run Instance not found.');
    }
    return { id: doc.id, ...doc.data() };
  }

  async getRunInstancesByDate(date) {
    if (!date) {
      throw new ValidationError('date is required (YYYY-MM-DD).');
    }
    const snapshot = await db.collection('RunInstance').where('departureDate', '==', date).limit(200).get();
    const instances = [];
    snapshot.forEach(doc => { instances.push({ id: doc.id, ...doc.data() }); });
    instances.sort((a, b) => ((b.createdAt || '') > (a.createdAt || '') ? 1 : -1));
    return { success: true, count: instances.length, data: instances };
  }

  async getRunInstanceByTrainNo(trainNo) {
    if (!trainNo) {
      throw new ValidationError('trainNo is required.');
    }
    const snapshot = await db.collection('RunInstance').where('trainNo', '==', trainNo).limit(1).get();
    if (snapshot.empty) {
      return null;
    }
    const doc = snapshot.docs[0];
    return { id: doc.id, ...doc.data() };
  }

  async activateJourney(uid, body) {
    const { actualDeparture } = body || {};
    if (!uid) {
      throw new ValidationError('runInstanceId is required.');
    }
    const runInstanceRef = db.collection('RunInstance').doc(uid);
    const doc = await runInstanceRef.get();
    if (!doc.exists) {
      throw new NotFoundError('Run Instance not found.');
    }
    const currentData = doc.data();
    if (!['ALLOCATED', 'READY'].includes(currentData.status)) {
      throw new ValidationError('Invalid State Transition', `Cannot activate a journey with status '${currentData.status}'. Must be 'ALLOCATED' or 'READY'.`);
    }
    const departureTime = actualDeparture || new Date().toISOString();
    await runInstanceRef.update({ actualDeparture: departureTime, status: 'Active', journeyStartedAt: new Date().toISOString(), updatedAt: new Date().toISOString() });

    const runDocAfter = await runInstanceRef.get();
    const activatedRunData = runDocAfter.data();
    await generateTaskInstancesForRun(activatedRunData);
    await generatePreTerminalGarbageTasks(uid);
    await generateTasksFromMasters(activatedRunData);

    return { message: 'Journey activated successfully', runInstanceId: uid, actualDeparture: departureTime, status: 'Active' };
  }

  async completeJourney(uid, body) {
    const { actualArrival, delayMinutes } = body || {};
    if (!uid) {
      throw new ValidationError('runInstanceId is required.');
    }
    const runInstanceRef = db.collection('RunInstance').doc(uid);
    const doc = await runInstanceRef.get();
    if (!doc.exists) {
      throw new NotFoundError('Run Instance not found.');
    }
    const currentData = doc.data();
    if (currentData.status !== 'Active') {
      throw new ValidationError('Invalid State Transition', `Cannot complete a journey with status '${currentData.status}'. Must be 'Active'.`);
    }
    const arrivalTime = actualArrival || new Date().toISOString();
    const updateData = { actualArrival: arrivalTime, status: 'Completed', journeyCompletedAt: new Date().toISOString(), updatedAt: new Date().toISOString() };
    if (delayMinutes !== undefined) { updateData.delayMinutes = delayMinutes; }
    await runInstanceRef.update(updateData);
    await generateClosureTasks(uid, arrivalTime, currentData);

    return { message: 'Journey completed successfully', runInstanceId: uid, actualArrival: arrivalTime, status: 'Completed' };
  }

  async getActiveRunForWorker(workerId, trainNo) {
    if (!workerId) {
      throw new ValidationError('workerId is required.');
    }
    const activeStatuses = ['PLANNED', 'ALLOCATED', 'READY', 'Active', 'ACTIVE', 'active', 'Scheduled', 'scheduled', 'Running', 'running'];
    let query = db.collection('RunInstance').where('status', 'in', activeStatuses);
    if (trainNo) {
      query = query.where('trainNo', '==', trainNo);
    }
    const snapshot = await query.limit(200).get();
    if (snapshot.empty) { return null; }

    let found = null;
    snapshot.forEach(doc => {
      if (found) return;
      const runData = doc.data();
      if (runData.coaches && Array.isArray(runData.coaches)) {
        const assigned = runData.coaches.some(c => c.workerId === workerId || c.janitorId === workerId);
        if (assigned) {
          found = { id: doc.id, ...runData };
        }
      }
    });
    return found;
  }
  async deleteRunInstance(uid) {
    if (!uid) {
      throw new ValidationError('runInstanceId is required.');
    }
    const runInstanceRef = db.collection('RunInstance').doc(uid);
    const doc = await runInstanceRef.get();
    if (!doc.exists) {
      throw new NotFoundError('Run Instance not found.');
    }
    const data = doc.data();
    const validStatuses = ['PLANNED', 'ALLOCATED'];
    if (!validStatuses.includes(data.status)) {
      throw new ValidationError(
        'Invalid State Transition',
        `Cannot delete a run instance with status '${data.status}'. Only 'PLANNED' or 'ALLOCATED' can be deleted.`
      );
    }

    const collections = ['task_headers', 'task_details'];
    for (const collectionName of collections) {
      const snapshot = await db.collection(collectionName).where('runInstanceId', '==', uid).limit(200).get();
      if (!snapshot.empty) {
        const batch = db.batch();
        snapshot.forEach(doc => batch.delete(doc.ref));
        await batch.commit();
      }
    }

    if (data.instanceId) {
      try {
        await db.collection('TrainPairs').doc(data.instanceId).update({ status: 'Available' });
      } catch (_) {}
    }

    await runInstanceRef.delete();

    return { success: true, message: 'Run instance deleted successfully' };
  }
}

export const runInstanceService = new RunInstanceService();
