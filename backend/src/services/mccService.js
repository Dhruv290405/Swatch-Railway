import { db } from '../database/index.js';
import { NotFoundError, ValidationError, ForbiddenError } from '../errors/index.js';

/* ==========================================================================
   MCC (Mechanised Coach Cleaning) — Washing Plant / Depot module.
   A washing depot schedules a rake for a mechanised wash, assigns coach tasks
   to the crew, and a supervisor verifies each completed coach wash.
   Scoped by contract type `mcc` (enforced at route level).
   ========================================================================== */

const RUN_STATUSES = ['SCHEDULED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'];
const TASK_STATUSES = ['OPEN', 'IN_PROGRESS', 'SUBMITTED', 'APPROVED', 'REJECTED'];

class MccService {
  /* ─── DEPOTS (washing plants) ──────────────────────────────────────────── */

  async createDepot(userData, body) {
    const { name, stationId, stationName, capacity, machines, contractId, address } = body;
    if (!name) throw new ValidationError('Depot name is required.');
    const managerRoles = ['SUPER_ADMIN', 'ADMIN', 'RAILWAY_ADMIN', 'RAILWAY_MASTER', 'COMPANY_MASTER', 'CONTRACTOR_MASTER', 'CONTRACTOR_ADMIN'];
    if (!managerRoles.includes((userData.role || '').toUpperCase().replace(/\s+/g, '_'))) {
      throw new ForbiddenError('Only master/admin roles can create depots.');
    }
    const ref = db.collection('mcc_depots').doc();
    await ref.set({
      uid: ref.id,
      name,
      stationId,
      stationName: stationName || '',
      capacity: Number(capacity) || 0,
      machines: Number(machines) || 0,
      contractId: contractId || null,
      entityId: userData.entityId || userData.entityDetails?.companyName || null,
      address: address || '',
      status: 'active',
      createdBy: userData.uid || null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });
    return { success: true, message: 'Depot created', depotId: ref.id };
  }

  async listDepots(filters = {}) {
    const snapshot = await db.collection('mcc_depots').limit(200).get();
    const depots = [];
    snapshot.forEach(doc => depots.push({ id: doc.id, ...doc.data() }));
    depots.sort((a, b) => ((b.createdAt || '') > (a.createdAt || '') ? 1 : -1));
    return { success: true, count: depots.length, depots };
  }

  async getDepot(depotId) {
    const doc = await db.collection('mcc_depots').doc(depotId).get();
    if (!doc.exists) throw new NotFoundError('Depot not found.');
    return { success: true, depot: { id: doc.id, ...doc.data() } };
  }

  /* ─── WASHING RUNS ─────────────────────────────────────────────────────── */

  async createWashingRun(userData, body) {
    const { depotId, trainNo, trainName, scheduledDate, scheduledTime, coachNos, assignedWorkers, remarks } = body;
    if (!depotId || !trainNo) throw new ValidationError('depotId and trainNo are required.');
    const managerRoles = ['SUPER_ADMIN', 'ADMIN', 'RAILWAY_ADMIN', 'RAILWAY_MASTER', 'COMPANY_MASTER', 'CONTRACTOR_MASTER', 'CONTRACTOR_ADMIN'];
    if (!managerRoles.includes((userData.role || '').toUpperCase().replace(/\s+/g, '_'))) {
      throw new ForbiddenError('Only master/admin roles can create washing runs.');
    }
    const depotDoc = await db.collection('mcc_depots').doc(depotId).get();
    if (!depotDoc.exists) throw new NotFoundError('Depot not found.');
    const depot = depotDoc.data();

    const coaches = (coachNos && coachNos.length) ? coachNos : ['A1', 'A2', 'A3', 'B1', 'B2'];
    const workerMap = (assignedWorkers && assignedWorkers.length) ? assignedWorkers : coaches.map((_, i) => ({ coachNo: coaches[i] }));

    const ref = db.collection('mcc_washing_runs').doc();
    const taskRefs = [];
    for (const c of coaches) {
      const worker = workerMap.find(w => w.coachNo === c);
      const tRef = db.collection('mcc_washing_tasks').doc();
      taskRefs.push({
        uid: tRef.id,
        runId: ref.id,
        depotId,
        coachNo: c,
        assignedWorkerId: worker?.workerId || null,
        assignedWorkerName: worker?.workerName || '',
        status: 'OPEN',
        beforePhoto: null,
        afterPhoto: null,
        submittedAt: null,
        approvedAt: null,
        approvedBy: null,
        rejectionReason: null,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      });
    }

    await ref.set({
      uid: ref.id,
      runNumber: `MCC-${ref.id.slice(-6).toUpperCase()}`,
      depotId,
      depotName: depot.name || '',
      stationId: depot.stationId || null,
      trainNo,
      trainName: trainName || '',
      scheduledDate: scheduledDate || null,
      scheduledTime: scheduledTime || null,
      coachNos: coaches,
      taskCount: taskRefs.length,
      completedTaskCount: 0,
      approvedTaskCount: 0,
      status: 'SCHEDULED',
      remarks: remarks || '',
      entityId: userData.entityId || depot.entityId || null,
      createdBy: userData.uid || null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });
    for (const t of taskRefs) await db.collection('mcc_washing_tasks').doc(t.uid).set(t);
    return { success: true, message: 'Washing run created', runId: ref.id, tasks: taskRefs.map(t => t.uid) };
  }

  async listWashingRuns(filters = {}) {
    const { depotId, status, runId } = filters;
    let query = db.collection('mcc_washing_runs');
    if (depotId) query = query.where('depotId', '==', depotId);
    if (status) query = query.where('status', '==', status);
    const snapshot = await query.limit(200).get();
    const runs = [];
    snapshot.forEach(doc => runs.push({ id: doc.id, ...doc.data() }));
    runs.sort((a, b) => ((b.createdAt || '') > (a.createdAt || '') ? 1 : -1));
    return { success: true, count: runs.length, runs };
  }

  async getWashingRun(runId) {
    const doc = await db.collection('mcc_washing_runs').doc(runId).get();
    if (!doc.exists) throw new NotFoundError('Washing run not found.');
    const taskSnap = await db.collection('mcc_washing_tasks').where('runId', '==', runId).limit(200).get();
    const tasks = [];
    taskSnap.forEach(d => tasks.push({ id: d.id, ...d.data() }));
    tasks.sort((a, b) => (a.coachNo || '').localeCompare(b.coachNo || ''));
    return { success: true, run: { id: doc.id, ...doc.data() }, tasks };
  }

  async startWashingRun(userData, runId) {
    const doc = await db.collection('mcc_washing_runs').doc(runId).get();
    if (!doc.exists) throw new NotFoundError('Washing run not found.');
    const data = doc.data();
    if (!['SCHEDULED'].includes(data.status)) throw new ValidationError(`Run cannot be started from status ${data.status}.`);
    await db.collection('mcc_washing_runs').doc(runId).update({
      status: 'IN_PROGRESS',
      startedAt: new Date().toISOString(),
      startedBy: userData.uid || null,
      updatedAt: new Date().toISOString()
    });
    return { success: true, message: 'Washing run started', runId };
  }

  async completeWashingRun(runId) {
    const doc = await db.collection('mcc_washing_runs').doc(runId).get();
    if (!doc.exists) throw new NotFoundError('Washing run not found.');
    if (!['IN_PROGRESS', 'SCHEDULED'].includes(doc.data().status)) {
      throw new ValidationError(`Run cannot be completed from status ${doc.data().status}.`);
    }
    await db.collection('mcc_washing_runs').doc(runId).update({
      status: 'COMPLETED',
      completedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });
    return { success: true, message: 'Washing run completed', runId };
  }

  /* ─── WASHING TASKS (per coach) ─────────────────────────────────────────── */

  async getWorkerTasks(userData, filters = {}) {
    const { status } = filters;
    const uid = userData.uid;
    let query = db.collection('mcc_washing_tasks').where('assignedWorkerId', '==', uid);
    if (status) query = query.where('status', '==', status);
    const snapshot = await query.limit(200).get();
    const tasks = [];
    snapshot.forEach(doc => tasks.push({ id: doc.id, ...doc.data() }));
    tasks.sort((a, b) => ((b.createdAt || '') > (a.createdAt || '') ? 1 : -1));
    return { success: true, count: tasks.length, tasks };
  }

  async submitTask(userData, body) {
    const { taskId, beforePhoto, afterPhoto, remarks } = body;
    if (!taskId) throw new ValidationError('taskId is required.');
    const doc = await db.collection('mcc_washing_tasks').doc(taskId).get();
    if (!doc.exists) throw new NotFoundError('Washing task not found.');
    const data = doc.data();
    const uid = userData.uid;
    if ((data.assignedWorkerId && data.assignedWorkerId !== uid) && !['SUPER_ADMIN', 'ADMIN', 'RAILWAY_ADMIN', 'COMPANY_MASTER', 'CONTRACTOR_MASTER', 'CONTRACTOR_ADMIN'].includes((userData.role || '').toUpperCase().replace(/\s+/g, '_'))) {
      throw new ForbiddenError('This task is not assigned to you.');
    }
    if (!['OPEN', 'IN_PROGRESS', 'REJECTED'].includes(data.status)) {
      throw new ValidationError(`Task cannot be submitted from status ${data.status}.`);
    }
    await db.collection('mcc_washing_tasks').doc(taskId).update({
      status: 'SUBMITTED',
      beforePhoto: beforePhoto || data.beforePhoto || null,
      afterPhoto: afterPhoto || null,
      remarks: remarks || data.remarks || null,
      submittedBy: uid || null,
      submittedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });
    await this._rollupRunTaskCounts(data.runId);
    return { success: true, message: 'Washing task submitted', taskId };
  }

  async approveTask(userData, taskId, body = {}) {
    const doc = await db.collection('mcc_washing_tasks').doc(taskId).get();
    if (!doc.exists) throw new NotFoundError('Washing task not found.');
    const data = doc.data();
    if (!['SUBMITTED'].includes(data.status)) throw new ValidationError(`Only SUBMITTED tasks can be approved (current: ${data.status}).`);
    await db.collection('mcc_washing_tasks').doc(taskId).update({
      status: 'APPROVED',
      approvedBy: userData.uid || null,
      approvedAt: new Date().toISOString(),
      remarks: body.remarks || data.remarks || null,
      updatedAt: new Date().toISOString()
    });
    await this._rollupRunTaskCounts(data.runId);
    return { success: true, message: 'Washing task approved', taskId };
  }

  async rejectTask(userData, taskId, body = {}) {
    const doc = await db.collection('mcc_washing_tasks').doc(taskId).get();
    if (!doc.exists) throw new NotFoundError('Washing task not found.');
    const data = doc.data();
    if (!['SUBMITTED'].includes(data.status)) throw new ValidationError(`Only SUBMITTED tasks can be rejected (current: ${data.status}).`);
    await db.collection('mcc_washing_tasks').doc(taskId).update({
      status: 'REJECTED',
      rejectedBy: userData.uid || null,
      rejectedAt: new Date().toISOString(),
      rejectionReason: body.reason || 'Work not satisfactory',
      updatedAt: new Date().toISOString()
    });
    await this._rollupRunTaskCounts(data.runId);
    return { success: true, message: 'Washing task rejected', taskId };
  }

  /* ─── ATTENDANCE (depot) ────────────────────────────────────────────────── */

  async markAttendance(userData, body) {
    const { runId, depotId, attendanceType, imageUrl, deviceTimestamp } = body;
    if (!attendanceType) throw new ValidationError('attendanceType is required.');
    if (!['start', 'mid', 'end'].includes(attendanceType)) {
      throw new ValidationError("attendanceType must be 'start', 'mid', or 'end'");
    }
    const uid = userData.uid;
    const scopeKey = runId ? `run_${runId}` : (depotId ? `depot_${depotId}` : 'depot_general');
    const todayIST = new Date(Date.now() + 5.5 * 60 * 60 * 1000).toISOString().slice(0, 10);
    const docId = `mcc_${scopeKey}_${todayIST}_${uid}`;
    const ref = db.collection('mcc_attendance').doc(docId);
    const doc = await ref.get();

    const entry = {
      attendanceType,
      imageUrl: imageUrl || null,
      deviceTimestamp: deviceTimestamp || new Date().toISOString(),
      serverTimestamp: new Date().toISOString()
    };

    if (!doc.exists) {
      if (attendanceType !== 'start') throw new ValidationError("You must submit 'start' attendance first.");
      await ref.set({
        uid: docId,
        workerId: uid,
        workerName: userData.fullName || 'Unknown',
        runId: runId || null,
        depotId: depotId || null,
        isStartMarked: true,
        isMidMarked: false,
        isEndMarked: false,
        startAttendance: entry,
        midAttendance: null,
        endAttendance: null,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      });
    } else {
      const current = doc.data();
      const updateData = { updatedAt: new Date().toISOString() };
      if (attendanceType === 'start') throw new ValidationError('Start attendance already submitted.');
      if (attendanceType === 'mid') {
        if (current.midAttendance) throw new ValidationError('Mid attendance already submitted.');
        updateData.midAttendance = entry;
        updateData.isMidMarked = true;
      }
      if (attendanceType === 'end') {
        if (current.endAttendance) throw new ValidationError('End attendance already submitted.');
        updateData.endAttendance = entry;
        updateData.isEndMarked = true;
      }
      await ref.update(updateData);
    }
    return { success: true, message: `${attendanceType.toUpperCase()} attendance processed.`, uid: docId };
  }

  async getAttendanceStatus(userData, query = {}) {
    const { runId, depotId } = query;
    const uid = userData.uid;
    const scopeKey = runId ? `run_${runId}` : (depotId ? `depot_${depotId}` : 'depot_general');
    const todayIST = new Date(Date.now() + 5.5 * 60 * 60 * 1000).toISOString().slice(0, 10);
    const docId = `mcc_${scopeKey}_${todayIST}_${uid}`;
    const doc = await db.collection('mcc_attendance').doc(docId).get();
    if (!doc.exists) return { success: true, exists: false, isStartMarked: false, isMidMarked: false, isEndMarked: false };
    const d = doc.data();
    return {
      success: true,
      exists: true,
      isStartMarked: d.isStartMarked || false,
      isMidMarked: d.isMidMarked || false,
      isEndMarked: d.isEndMarked || false,
      startAttendance: d.startAttendance || null,
      midAttendance: d.midAttendance || null,
      endAttendance: d.endAttendance || null
    };
  }

  async listAttendance(filters = {}) {
    const { runId, depotId } = filters;
    let query = db.collection('mcc_attendance');
    const snapshot = await query.limit(200).get();
    const records = [];
    snapshot.forEach(doc => records.push({ id: doc.id, ...doc.data() }));
    if (runId) records.push(); // no-op keeps filter simple below
    const filtered = records.filter(r => (runId ? r.runId === runId : true) && (depotId ? r.depotId === depotId : true));
    filtered.sort((a, b) => ((b.createdAt || '') > (a.createdAt || '') ? 1 : -1));
    return { success: true, count: filtered.length, records: filtered };
  }

  /* ─── DASHBOARD ─────────────────────────────────────────────────────────── */

  async getDashboard(userData) {
    const runsSnap = await db.collection('mcc_washing_runs').limit(200).get();
    const tasksSnap = await db.collection('mcc_washing_tasks').limit(200).get();
    const depotsSnap = await db.collection('mcc_depots').limit(200).get();

    let totalRuns = 0, scheduledRuns = 0, inProgressRuns = 0, completedRuns = 0;
    runsSnap.forEach(doc => {
      totalRuns++;
      const s = doc.data().status;
      if (s === 'SCHEDULED') scheduledRuns++;
      else if (s === 'IN_PROGRESS') inProgressRuns++;
      else if (s === 'COMPLETED') completedRuns++;
    });

    let totalTasks = 0, approvedTasks = 0, submittedTasks = 0, openTasks = 0, rejectedTasks = 0;
    const workerTasks = { total: 0, approved: 0, pending: 0 };
    tasksSnap.forEach(doc => {
      const t = doc.data();
      totalTasks++;
      if (t.status === 'APPROVED') approvedTasks++;
      else if (t.status === 'SUBMITTED') submittedTasks++;
      else if (t.status === 'OPEN' || t.status === 'IN_PROGRESS') openTasks++;
      else if (t.status === 'REJECTED') rejectedTasks++;
      if (t.assignedWorkerId === userData.uid) {
        workerTasks.total++;
        if (t.status === 'APPROVED') workerTasks.approved++;
        else workerTasks.pending++;
      }
    });

    return {
      success: true,
      dashboard: {
        depots: depotsSnap.size,
        runs: { total: totalRuns, scheduled: scheduledRuns, inProgress: inProgressRuns, completed: completedRuns },
        tasks: { total: totalTasks, approved: approvedTasks, submitted: submittedTasks, open: openTasks, rejected: rejectedTasks },
        myTasks: userData.uid ? workerTasks : { total: 0, approved: 0, pending: 0 },
        lastUpdated: new Date().toISOString()
      }
    };
  }

  /* ─── INTERNAL ──────────────────────────────────────────────────────────── */

  async _rollupRunTaskCounts(runId) {
    if (!runId) return;
    const snap = await db.collection('mcc_washing_tasks').where('runId', '==', runId).limit(500).get();
    let completed = 0, approved = 0;
    snap.forEach(doc => {
      const s = doc.data().status;
      if (['SUBMITTED', 'APPROVED'].includes(s)) completed++;
      if (s === 'APPROVED') approved++;
    });
    await db.collection('mcc_washing_runs').doc(runId).update({
      completedTaskCount: completed,
      approvedTaskCount: approved,
      updatedAt: new Date().toISOString()
    });
  }
}

export const mccService = new MccService();