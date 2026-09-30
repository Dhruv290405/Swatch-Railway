import { db, admin } from '../database/index.js';
import { NotFoundError, ValidationError, ForbiddenError } from '../errors/index.js';

const getISTDateStr = (offset = 0) => {
  const shifted = new Date(Date.now() + offset * 86400000);
  return shifted.toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' });
};

// Roles that may only ever see their OWN tasks (their own shift), never every
// task across a station/date. Contractor supervisors/workers, cleaners etc.
// Stored in normalized form (spaces/underscores stripped, upper-cased) so
// 'Contractor Supervisor', 'contractor_supervisor', ... all match.
const _OWN_TASK_ROLES = new Set([
  'CONTRACTORSUPERVISOR',
  'CONTRACTORWORKER',
  'CONTRACTORCLEANER',
  'SUPERVISOR',
  'WORKER',
  'CLEANER',
]);

const _normalizeRole = (role) => String(role || '').toUpperCase().replace(/[\s_-]/g, '');

// Supervisors only ever see tasks for THEIR shift. Enforced at list time for
// these roles (on top of the worker/supervisor-id scoping).
const _SHIFT_SCOPED_ROLES = new Set([
  'CONTRACTORSUPERVISOR',
  'SUPERVISOR',
]);

class TaskManagementService {
  async generateFrequencyBasedTasks(targetDate) {
    if (!targetDate) targetDate = new Date().toISOString().split('T')[0];

    const assignmentsQuery = await db.collection('areaWorkerAssignments')
      .where('isActive', '==', true)
      .limit(500).get();

    if (assignmentsQuery.empty) return { message: 'No active assignments found', count: 0, taskIds: [] };

    const allTaskIds = [];
    let totalCount = 0;
    let cancelledTotal = 0;

    // Idempotent auto-generation: reconcile against tasks already present for
    // the target date so repeated runs (midnight cron + 6/18 refresh + manual
    // "By Frequency") never duplicate or overshoot. One generic task per
    // frequency slot, per assigned worker. Activities are intentionally NOT
    // expanded here — the responsible person/override is handled elsewhere.
    for (const doc of assignmentsQuery.docs) {
      const assignment = doc.data();
      let areaDoc = await db.collection('areas').doc(assignment.areaId).get();
      if (!areaDoc.exists) {
        areaDoc = await db.collection('stationAreas').doc(assignment.areaId).get();
      }
      if (!areaDoc.exists) continue;
      const area = areaDoc.data();

      // Station-cleaning contract scope: only generate tasks for areas that
      // belong to an active station-cleaning contract. All other contract
      // types (OBHS, catering, linen, ...) are left untouched by this job.
      const stationId = area.stationId || assignment.stationId || '';
      const contract = await this._getActiveStationCleaningContract(stationId);
      if (!contract.uid) continue;

      // In the station-cleaning flow the contractor supervisor performs the
      // tasks (workers are manual roster records with no login). Each frequency
      // slot is TAG-GED to the shift window its time falls in (morning/evening/
      // night) and assigned to the supervisor recorded for that shift, so a
      // morning supervisor never receives 14:00/18:00/22:00 tasks. Slots whose
      // shift has no recorded supervisor are skipped (task is not generated).
      const preferredSupervisorId = area.supervisorId || assignment.supervisorId || null;
      const supervisor = await this._getContractSupervisors(contract.uid, stationId, preferredSupervisorId);
      const assignedSupervisorId = supervisor.uid || preferredSupervisorId;
      const assignedSupervisorName = supervisor.fullName || (area.supervisorName || assignment.supervisorName || '');
      const supervisorShiftMap = await this._stationSupervisorShifts(contract.uid, stationId);
      const supervisorByShift = new Map();
      for (const sup of supervisorShiftMap.values()) {
        if (!supervisorByShift.has(sup.shift)) supervisorByShift.set(sup.shift, sup);
      }
      const pickSupervisorForSlot = (slotShift) => {
        const byShift = supervisorByShift.get(slotShift);
        if (byShift) return byShift;
        // Backwards-compatible default: the station's primary supervisor owns
        // the morning window when nothing is recorded yet.
        if (slotShift === 'morning') {
          const primary = supervisorShiftMap.get(assignedSupervisorId) || supervisorShiftMap.values().next().value;
          return primary || null;
        }
        return null;
      };

      const cleaningFrequency = area.cleaningFrequency || area.frequency || 'daily';
      let frequencyTimes = area.frequencyTimes || this._getDefaultFrequencyTimes(cleaningFrequency);
      const areaName = area.areaName || area.name || assignment.areaName || '';
      const areaCode = area.areaCode || '';
      const mainArea = area.mainArea || '';
      const platformId = assignment.platformId || area.platformId || null;

      // Existing active tasks for this area on the target date (regardless of
      // worker) so we can reconcile to the configured slot set.
      const existingSnap = await db.collection('cleaningTasks')
        .where('date', '==', targetDate)
        .where('areaId', '==', assignment.areaId)
        .select('workerId', 'scheduledTime', 'status', 'shift')
        .get();
      const existingByTime = new Map(); // scheduledTime -> {id, workerId, status, shift}
      const TERMINAL = new Set(['completed', 'approved', 'rejected', 'cancelled']);
      existingSnap.forEach(tDoc => {
        const d = tDoc.data();
        if (d.status === 'cancelled') return;
        if (!d.scheduledTime) return;
        existingByTime.set(d.scheduledTime, {
          id: tDoc.id,
          workerId: d.workerId,
          status: d.status,
          shift: d.shift ? String(d.shift).trim().toLowerCase() : '',
        });
      });

      const batch = db.batch();
      let batchCount = 0;

      // Cancel active tasks whose slot is no longer in the configured set
      // (frequency reduced), then reconcile existing slots:
      //   - reassign to the current shift-holder if they moved
      //   - retag the shift label so supervisor-screen filtering is accurate
      //   - create missing slots
      const slotSet = new Set(frequencyTimes);
      for (const [scheduledTime, existing] of existingByTime.entries()) {
        if (!slotSet.has(scheduledTime)) {
          batch.update(db.collection('cleaningTasks').doc(existing.id), {
            status: 'cancelled',
            updatedAt: new Date().toISOString(),
          });
          batchCount++;
          cancelledTotal++;
        }
      }

      for (const scheduledTime of frequencyTimes) {
        const slotShift = this._shiftForTime(scheduledTime) || 'morning';
        const slotSupervisor = pickSupervisorForSlot(slotShift);
        const existing = existingByTime.get(scheduledTime);

        // Self-healing: reassign stale tasks to the current shift-holder
        // so the supervisor-screen count always matches the actual task list.
        if (existing && slotSupervisor && !TERMINAL.has(existing.status)) {
          const patches = {};
          if ((existing.workerId || '') !== slotSupervisor.uid) {
            patches.workerId     = slotSupervisor.uid;
            patches.workerName   = slotSupervisor.fullName;
            patches.supervisorId = slotSupervisor.uid;
            patches.supervisorName = slotSupervisor.fullName;
          }
          if (existing.shift !== slotShift) {
            patches.shift = slotShift;
          }
          if (Object.keys(patches).length > 0) {
            patches.updatedAt = new Date().toISOString();
            batch.update(db.collection('cleaningTasks').doc(existing.id), patches);
            batchCount++;
          }
          continue;
        }
        if (existing) continue;
        if (!slotSupervisor) continue;
        const taskRef = db.collection('cleaningTasks').doc();
        const displayName = [mainArea, areaName].filter(Boolean).join(' - ');
        const task = {
          uid: taskRef.id,
          stationId: area.stationId || assignment.stationId,
          platformId,
          areaId: assignment.areaId,
          areaName: displayName,
          areaCode,
          mainArea,
          workerId: slotSupervisor.uid,
          workerName: slotSupervisor.fullName,
          supervisorId: slotSupervisor.uid,
          supervisorName: slotSupervisor.fullName,
          assignmentId: assignment.uid,
          activityType: area.areaType || 'Cleaning',
          frequency: cleaningFrequency,
          date: targetDate,
          scheduledDate: targetDate,
          scheduledTime,
          priority: area.priority || 3,
          shift: slotShift,
          status: 'pending',
          source: 'auto',
          generationKey: `${area.stationId || assignment.stationId}|${assignment.areaId}|${targetDate}|${slotShift}`,
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
        allTaskIds.push(taskRef.id);
        batchCount++;
      }

      if (batchCount > 0) {
        await batch.commit();
        totalCount += batchCount;
      }
    }

    const normMsg = cancelledTotal > 0 ? `, cancelled ${cancelledTotal} extra` : '';
    return {
      message: `Generated ${totalCount} tasks for ${targetDate}${normMsg}`,
      count: totalCount,
      cancelled: cancelledTotal,
      taskIds: allTaskIds,
    };
  }

  async _getActiveStationCleaningContract(stationId) {
    if (!stationId) return {};
    const snap = await db.collection('contracts')
      .where('contractType', '==', 'station_cleaning')
      .where('stationIds', 'array-contains', stationId)
      .limit(10)
      .get();
    if (snap.empty) return {};
    const active = snap.docs.find(d => {
      const s = String(d.data().status || '').toLowerCase();
      return s === 'active' || s === 'approved' || s === 'running' || s === 'ongoing' || s === '';
    });
    if (!active) return {};
    const d = active.data();
    return { uid: active.id, entityId: d.entityId, contractType: d.contractType };
  }

  async _getContractSupervisors(contractId, stationId, preferredId) {
    if (!contractId) return {};
    const snap = await db.collection('users')
      .where('contractId', '==', contractId)
      .where('role', 'in', ['Contractor Supervisor', 'CONTRACTOR_SUPERVISOR'])
      .where('status', 'in', ['APPROVED', 'Approved', 'approve'])
      .limit(25)
      .get();
    const list = snap.docs
      .map(d => ({ uid: d.id, fullName: d.data().fullName || d.data().name || '', stations: d.data().stations || [] }))
      .filter(u => !stationId || u.stations.includes(stationId));
    if (preferredId) {
      const preferred = list.find(u => u.uid === preferredId);
      if (preferred) return preferred;
    }
    return list[0] || {};
  }

  // Map a task slot time ("HH:MM") to the shift window it belongs to.
  // morning: 04:00-11:59 · evening: 12:00-19:59 · night: 20:00-03:59.
  _shiftForTime(timeStr) {
    if (!timeStr) return null;
    const m = /^(\d{1,2}):/.exec(String(timeStr));
    if (!m) return null;
    const h = parseInt(m[1], 10);
    if (h >= 4 && h < 12) return 'morning';
    if (h >= 12 && h < 20) return 'evening';
    return 'night';
  }

  // The recorded shift of a contractor supervisor (null when never recorded).
  // Recording happens whenever tasks are generated for that supervisor + shift.
  async _getSupervisorShift(supervisorId) {
    if (!supervisorId) return null;
    try {
      const doc = await db.collection('stationSupervisorShifts').doc(supervisorId).get();
      if (doc.exists && doc.data().shift) return String(doc.data().shift).trim().toLowerCase();
    } catch (_) {}
    return null;
  }

  // Own shift for any contractor worker/supervisor: the recorded supervisor
  // shift first, else their active area-worker assignment's shift.
  async _getOwnShift(userId) {
    if (!userId) return null;
    const recorded = await this._getSupervisorShift(userId);
    if (recorded) return recorded;
    const assigned = await this._resolveAssignedShift(userId);
    return assigned ? String(assigned).trim().toLowerCase() : null;
  }

  // Contract supervisors/workers may only ever see/act on TODAY's tasks (IST).
  // This is applied at both list time and start/complete time so they can never
  // pull up tomorrow's (or past) work.
  _isOwnTaskRole(role) {
    return _OWN_TASK_ROLES.has(_normalizeRole(role));
  }

  // Hard guard for contractor supervisors/workers (the ones who actually
  // execute station-cleaning work — workers recorded by the supervisor have no
  // login): the task must be (1) assigned to the calling user, (2) belong to
  // their recorded shift, and (3) be for TODAY (IST). They can never start or
  // complete another shift's task or a task from any other day.
  async _assertOwnTaskAccess(task, user) {
    if (!this._isOwnTaskRole(user?.role)) return;
    const uid = user.uid;
    const isOwner = task.supervisorId === uid || task.workerId === uid;
    if (!isOwner) {
      throw new ForbiddenError('You can only work on tasks assigned to you');
    }
    const taskShift = task.shift ? String(task.shift).trim().toLowerCase() : null;
    if (taskShift) {
      const ownShift = await this._getOwnShift(uid);
      if (ownShift && taskShift !== ownShift) {
        throw new ForbiddenError(`This task belongs to the ${taskShift} shift; you are assigned to ${ownShift}`);
      }
    }
    const taskDate = task.date || task.scheduledDate || '';
    if (taskDate && taskDate !== getISTDateStr()) {
      throw new ForbiddenError('You can only work on today\'s tasks');
    }
  }

  async _setSupervisorShift(supervisorId, shift, stationId, contractId, supervisorName) {
    if (!supervisorId || !shift) return;
    const s = String(shift).trim().toLowerCase();
    if (!s) return;
    await db.collection('stationSupervisorShifts').doc(supervisorId).set({
      shift: s,
      stationId: stationId || '',
      contractId: contractId || '',
      supervisorName: supervisorName || '',
      updatedAt: new Date().toISOString(),
    }, { merge: true });
  }

  // All approved contractor supervisors for a station-cleaning contract+station.
  async _getStationSupervisors(contractId, stationId) {
    if (!contractId) return [];
    const snap = await db.collection('users')
      .where('contractId', '==', contractId)
      .where('role', 'in', ['Contractor Supervisor', 'CONTRACTOR_SUPERVISOR'])
      .where('status', 'in', ['APPROVED', 'Approved', 'approve'])
      .limit(25)
      .get();
    return snap.docs
      .map(d => ({ uid: d.id, fullName: d.data().fullName || d.data().name || '', stations: d.data().stations || [] }))
      .filter(u => !stationId || u.stations.includes(stationId));
  }

  // Map of every station supervisor -> their recorded shift (defaults 'morning'
  // when never recorded, preserving the current auto-generation behaviour for
  // the morning window).
  async _stationSupervisorShifts(contractId, stationId) {
    const supervisors = await this._getStationSupervisors(contractId, stationId);
    const map = new Map();
    for (const sup of supervisors) {
      const recorded = await this._getSupervisorShift(sup.uid);
      map.set(sup.uid, { ...sup, shift: recorded || 'morning', recorded: recorded != null });
    }
    return map;
  }

  _getDefaultFrequencyTimes(frequency) {
    switch (frequency) {
      case 'hourly': return ['06:00', '07:00', '08:00', '09:00', '10:00', '11:00', '12:00', '13:00', '14:00', '15:00', '16:00', '17:00', '18:00', '19:00', '20:00', '21:00', '22:00'];
      case '2hrs': return ['06:00', '08:00', '10:00', '12:00', '14:00', '16:00', '18:00', '20:00', '22:00'];
      case '4hrs': return ['06:00', '10:00', '14:00', '18:00', '22:00'];
      case 'daily': return ['08:00'];
      case 'twice_daily': return ['06:00', '18:00'];
      case 'shift_wise': return ['06:00', '14:00', '22:00'];
      case 'four_times_daily': return ['06:00', '10:00', '14:00', '18:00'];
      case 'week_wise': return ['08:00'];
      case 'fortnightly': return ['08:00'];
      case 'monthly': return ['08:00'];
      default: return ['08:00'];
    }
  }

  // Build a list of `count` evenly spaced time slots across the work window,
  // used when the contractor admin overrides an area's per-day frequency.
  _buildTimeslots(count, frequency) {
    const n = parseInt(count, 10);
    if (!n || n <= 0) return this._getDefaultFrequencyTimes(frequency);
    const base = this._getDefaultFrequencyTimes(frequency);
    if (base.length >= n) return base.slice(0, n);
    const start = 6 * 60;  // 06:00
    const end = 22 * 60;   // 22:00
    const span = end - start;
    const slots = [];
    for (let i = 0; i < n; i++) {
      const m = start + Math.round((span * (i + 0.5)) / n);
      const hh = String(Math.floor(m / 60)).padStart(2, '0');
      const mm = String(m % 60).padStart(2, '0');
      slots.push(`${hh}:${mm}`);
    }
    return slots;
  }

  async generateTasksForDate(targetDate, user) {
    return this.generateFrequencyBasedTasks(targetDate);
  }

  // Resolve a worker's currently-assigned shift from their active area-worker
  // assignments. Returns null when the worker has no assignment on record.
  async _resolveAssignedShift(workerId) {
    if (!workerId) return null;
    const snap = await db.collection('areaWorkerAssignments')
      .where('workerId', '==', workerId)
      .where('isActive', '==', true)
      .limit(1)
      .get();
    if (snap.empty || !snap.docs[0].data().shift) return null;
    return snap.docs[0].data().shift;
  }

  // Build an optional shift-warning payload when a worker acts on a task that
  // belongs to a different shift than the one they are currently assigned to.
  // Warning-only per requirement: the action proceeds, but the caller is told.
  async _shiftWarning(task, workerId) {
    if (!task || !task.shift || !workerId) return null;
    try {
      const assigned = await this._resolveAssignedShift(workerId);
      const attempt = String(task.shift || '').toLowerCase();
      if (assigned && attempt && String(assigned).toLowerCase() !== attempt) {
        return { shiftWarning: true, assignedShift: assigned, taskShift: attempt };
      }
    } catch (_) { /* never block an action due to a lookup failure */ }
    return null;
  }

  // Contractor supervisor/worker roles must mark their START attendance for
  // today (station cleaning) before they may start ANY task — manual or
  // auto-generated. Mirrors the app's attendance tab gate, enforced here too.
  async _assertStartAttendance(user) {
    if (!user || !user.uid) return;
    if (!this._isOwnTaskRole(user?.role)) return;
    const todayIST = getISTDateStr();
    const snapshot = await db.collection('station_cleaning_attendance')
      .where('workerId', '==', user.uid)
      .get();
    let latestDoc = null;
    let latestTime = 0;
    snapshot.forEach(doc => {
      const d = doc.data();
      if (String(d.date || '') !== todayIST) return;
      const time = d.serverTimestamp || d.createdAt || 0;
      const t = new Date(time).getTime() || 0;
      if (t >= latestTime) {
        latestTime = t;
        latestDoc = d;
      }
    });
    const startMarked = latestDoc && latestDoc.isStartMarked === true;
    if (!startMarked) {
      throw new ForbiddenError('Mark your START attendance first before starting any task');
    }
  }

  async startTask(taskId, data, user) {
    const ref = db.collection('cleaningTasks').doc(taskId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Task not found');
    const task = doc.data();
    await this._assertOwnTaskAccess(task, user);
    await this._assertStartAttendance(user);
    if (task.status !== 'pending' && task.status !== 'assigned') {
      throw new ValidationError(`Task cannot be started. Current status: ${task.status}`);
    }

    this._assertStartWindow(task);

    // ─── Activities (station-cleaning only) ────────────────────────────────
    // Auto-generated tasks carry no activities. Starting does NOT require an
    // activity — the supervisor must choose one before COMPLETING the task
    // (enforced in completeTask). If the caller supplies activities now, they
    // are recorded on this single task document — never expanded into
    // multiple task records. Scope: station-cleaning contracts only.
    const rawActivities = data.activities || data.activityIds || [];
    let taskActivities = null;
    if (rawActivities.length > 0) {
      const contract = await this._getActiveStationCleaningContract(task.stationId || '');
      if (!contract.uid) {
        throw new ForbiddenError('Activities can only be set for station-cleaning tasks');
      }
      const normalized = [];
      for (const entry of rawActivities) {
        if (!entry) continue;
        if (typeof entry === 'string') {
          normalized.push({ id: entry });
        } else {
          normalized.push({
            id: entry.id || entry.uid || '',
            name: entry.name || '',
            label: entry.label || entry.name || entry.label || '',
          });
        }
      }
      const resolved = [];
      for (const item of normalized) {
        if (!item.id) continue;
        const tid = String(item.id);
        const typeDoc = await db.collection('taskTypes').doc(tid).get();
        if (typeDoc.exists) {
          const td = typeDoc.data();
          resolved.push({
            id: tid,
            name: td.name || item.name || '',
            label: td.label || td.name || item.label || item.name || '',
          });
        } else if (item.name || item.label) {
          resolved.push({ id: tid, name: item.name || item.label || '', label: item.label || item.name || '' });
        }
      }
      if (resolved.length === 0) {
        throw new ValidationError('Provide at least one valid activity');
      }
      taskActivities = resolved;
    }

    const primary = taskActivities ? taskActivities[0] : null;
    const updates = {
      status: 'in_progress',
      startedAt: new Date().toISOString(),
      beforePhoto: data.beforePhoto || null,
      gpsLat: data.gpsLat || null,
      gpsLng: data.gpsLng || null,
      updatedAt: new Date().toISOString(),
      startedBy: user.uid
    };
    if (taskActivities) {
      updates.taskActivities = taskActivities;
      updates.activityType = primary.label || updates.activityType || 'Cleaning';
      updates.taskTypeId = primary.id || null;
      updates.taskTypeName = primary.name || null;
    }
    await ref.update(updates);
    const warning = await this._shiftWarning(task, user.uid);
    return warning ? { message: 'Task started', taskId, ...warning } : { message: 'Task started', taskId };
  }

  _assertStartWindow(task) {
    // Business rule: a task may be started only inside
    //   scheduledTime <= now < scheduledTime + 1 hour.
    // No starting before the scheduled time, and no starting 1 hour after it.
    const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;
    const scheduledDate = task.scheduledDate || task.date || '';
    const scheduledTime = task.scheduledTime || '';
    if (!scheduledDate || !scheduledTime) return;

    const dateMatch = /^(\d{4})-(\d{2})-(\d{2})$/.exec(scheduledDate);
    const timeMatch = /^(\d{2}):(\d{2})$/.exec(scheduledTime);
    if (!dateMatch || !timeMatch) return;

    const [, y, mo, d] = dateMatch.map(Number);
    const [, hh, mm] = timeMatch.map(Number);
    const scheduledIST = new Date(Date.UTC(y, mo - 1, d, hh, mm, 0));
    const nowIST = new Date(Date.now() + IST_OFFSET_MS);
    const windowEndIST = new Date(scheduledIST.getTime() + 60 * 60 * 1000);

    if (nowIST.getTime() < scheduledIST.getTime()) {
      throw new ValidationError('This task cannot be started yet. You can start it at the scheduled time.');
    }
    if (nowIST.getTime() >= windowEndIST.getTime()) {
      throw new ValidationError('The task start window has expired. This task could only be started within 1 hour of its scheduled time.');
    }
  }

  async _resolveActivities(rawActivities, task, stationId) {
    if (!Array.isArray(rawActivities) || rawActivities.length === 0) return null;
    const contract = await this._getActiveStationCleaningContract(stationId || '');
    if (!contract.uid) {
      throw new ForbiddenError('Activities can only be set for station-cleaning tasks');
    }
    const normalized = [];
    for (const entry of rawActivities) {
      if (!entry) continue;
      if (typeof entry === 'string') {
        normalized.push({ id: entry });
      } else {
        normalized.push({
          id: entry.id || entry.uid || '',
          name: entry.name || '',
          label: entry.label || entry.name || entry.label || '',
        });
      }
    }
    const resolved = [];
    const ids = normalized.map((i) => String(i.id)).filter(Boolean);
    // One batched read for every chosen activity instead of one round trip per
    // activity - starting/submitting a task with several activities selected was
    // paying N sequential Firestore calls.
    const typeDocs = new Map();
    for (let i = 0; i < ids.length; i += 30) {
      const chunk = ids.slice(i, i + 30);
      if (chunk.length === 1) {
        const single = await db.collection('taskTypes').doc(chunk[0]).get();
        if (single.exists) typeDocs.set(chunk[0], single.data());
      } else {
        const snap = await db.collection('taskTypes')
          .where(admin.firestore.n.documentId(), 'in', chunk)
          .get();
        snap.forEach((doc) => typeDocs.set(doc.id, doc.data()));
      }
    }
    for (const item of normalized) {
      if (!item.id) continue;
      const tid = String(item.id);
      const td = typeDocs.get(tid);
      if (td) {
        resolved.push({
          id: tid,
          name: td.name || item.name || '',
          label: td.label || td.name || item.label || item.name || '',
        });
      } else if (item.name || item.label) {
        resolved.push({ id: tid, name: item.name || item.label || '', label: item.label || item.name || '' });
      }
    }
    if (resolved.length === 0) {
      throw new ValidationError('Provide at least one valid activity');
    }
    return resolved;
  }

  async completeTask(taskId, data, user) {
    const ref = db.collection('cleaningTasks').doc(taskId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Task not found');
    const task = doc.data();
    await this._assertOwnTaskAccess(task, user);
    if (task.status !== 'in_progress' && task.status !== 'resubmitted') {
      throw new ValidationError(`Only in-progress or resubmitted tasks can be completed. Current: ${task.status}`);
    }

    // ─── Activity must be chosen before completing (station-cleaning) ───────
    // Manual or auto-generated task: the supervisor must have picked at least
    // one cleaning activity (either when starting, on a previous completion
    // attempt, or now) before the task can be marked done.
    const recordedActivities = Array.isArray(task.taskActivities) && task.taskActivities.length > 0
      ? task.taskActivities
      : null;
    let activities = task.activities && Array.isArray(task.activities) && task.activities.length > 0
      ? task.activities
      : null;
    let resolvedActivities = null;
    if (data && (data.activities || data.activityIds)) {
      resolvedActivities = await this._resolveActivities(data.activities || data.activityIds, task, task.stationId);
    }
    const finalizeActivities = resolvedActivities || recordedActivities || activities;
    let activityUpdates = {};
    if (finalizeActivities) {
      const primary = finalizeActivities[0];
      activityUpdates = {
        taskActivities: finalizeActivities,
        activityType: (primary && (primary.label || primary.name)) || task.activityType || 'Cleaning',
        taskTypeId: (primary && primary.id) || task.taskTypeId || null,
        taskTypeName: (primary && (primary.name || primary.label)) || task.taskTypeName || null,
      };
    } else if (String(task.stationId || '') && (await this._getActiveStationCleaningContract(task.stationId))) {
      throw new ValidationError('Select at least one activity before completing the task');
    }

    // ─── Optional grade: capture a score/grade at completion so dashboards
    // (which aggregate cleaningTasks by `score`/`grade`) reflect the latest
    // value instead of stale 0/D data. ────────────────────────────────────────
    const gradeUpdates = {};
    const rawScore = data.score !== undefined ? Number(data.score) : data.totalScore !== undefined ? Number(data.totalScore) : NaN;
    if (Number.isFinite(rawScore)) {
      const score = Math.max(0, Math.min(100, Math.round(rawScore)));
      gradeUpdates.score = score;
      gradeUpdates.totalScore = score;
      gradeUpdates.grade = (data.grade && String(data.grade).trim()) || (score >= 90 ? 'A' : score >= 75 ? 'B' : score >= 60 ? 'C' : 'D');
      gradeUpdates.gradedAt = new Date().toISOString();
      gradeUpdates.gradedBy = user.uid;
    } else if (data.grade && String(data.grade).trim()) {
      gradeUpdates.grade = String(data.grade).trim();
      gradeUpdates.gradedAt = new Date().toISOString();
      gradeUpdates.gradedBy = user.uid;
    } else {
      // No self-grade was submitted, but the task was completed. Credit it as
      // fully completed so supervisor/admin dashboards (which aggregate
      // cleaningTasks by `score`/`grade`) reflect the completed work instead
      // of treating the task as an unscored 0 that never changes the grade.
      gradeUpdates.score = 100;
      gradeUpdates.totalScore = 100;
      gradeUpdates.grade = 'A';
      gradeUpdates.gradedAt = new Date().toISOString();
      gradeUpdates.gradedBy = user.uid;
    }

    const updates = {
      status: 'completed',
      completedAt: new Date().toISOString(),
      afterPhoto: data.afterPhoto || task.afterPhoto || null,
      gpsLat: data.gpsLat || task.gpsLat || null,
      gpsLng: data.gpsLng || task.gpsLng || null,
      remarks: data.remarks || task.remarks || '',
      updatedAt: new Date().toISOString(),
      ...activityUpdates,
      ...gradeUpdates
    };
    await ref.update(updates);
    const warning = await this._shiftWarning(task, user.uid);
    return warning
      ? { message: 'Task completed', taskId, ...warning }
      : { message: 'Task completed', taskId };
  }

  async resubmitTask(taskId, data, user) {
    const ref = db.collection('cleaningTasks').doc(taskId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Task not found');
    const task = doc.data();
    await this._assertOwnTaskAccess(task, user);
    if (task.status !== 'rejected') throw new ValidationError('Only rejected tasks can be resubmitted');

    // ─── Activity must be chosen before resubmitting ───────────────────────
    // Use whichever activities are available: existing (from first completion
    // attempt) or newly supplied at resubmission.
    const recordedActivities = Array.isArray(task.taskActivities) && task.taskActivities.length > 0
      ? task.taskActivities
      : (task.activities && Array.isArray(task.activities) && task.activities.length > 0 ? task.activities : null);
    let resolvedActivities = null;
    if (data && (data.activities || data.activityIds)) {
      resolvedActivities = await this._resolveActivities(data.activities || data.activityIds, task, task.stationId);
    }
    const finalizeActivities = resolvedActivities || recordedActivities;
    let activityUpdates = {};
    if (finalizeActivities) {
      const primary = finalizeActivities[0];
      activityUpdates = {
        taskActivities: finalizeActivities,
        activityType: (primary && (primary.label || primary.name)) || task.activityType || 'Cleaning',
        taskTypeId: (primary && primary.id) || task.taskTypeId || null,
        taskTypeName: (primary && (primary.name || primary.label)) || task.taskTypeName || null,
      };
    } else if (String(task.stationId || '') && (await this._getActiveStationCleaningContract(task.stationId))) {
      throw new ValidationError('Select at least one activity before resubmitting the task');
    }

    const updates = {
      status: 'resubmitted',
      resubmittedAt: new Date().toISOString(),
      afterPhoto: data.afterPhoto || task.afterPhoto || null,
      gpsLat: data.gpsLat || task.gpsLat || null,
      gpsLng: data.gpsLng || task.gpsLng || null,
      remarks: data.remarks || task.remarks || '',
      rejectionReason: null,
      updatedAt: new Date().toISOString(),
      ...activityUpdates
    };
    await ref.update(updates);
    return { message: 'Task resubmitted for review', taskId };
  }

  async getTasks(query = {}, user) {
    const { stationId, platformId, areaId, workerId, status, date, startDate, endDate, supervisorId, includeOverdue } = query;
    let q = db.collection('cleaningTasks');
    const filters = [];
    if (stationId) { q = q.where('stationId', '==', stationId); filters.push('stationId'); }
    if (workerId) { q = q.where('workerId', '==', workerId); filters.push('workerId'); }
    if (areaId) { q = q.where('areaId', '==', areaId); filters.push('areaId'); }
    if (platformId) { q = q.where('platformId', '==', platformId); filters.push('platformId'); }
    if (supervisorId) { q = q.where('supervisorId', '==', supervisorId); filters.push('supervisorId'); }
    if (status) { q = q.where('status', '==', status); filters.push('status'); }
    if (date) { q = q.where('date', '==', date); filters.push('date'); }
    if (startDate && endDate) {
      q = q.where('date', '>=', startDate).where('date', '<=', endDate);
    } else if (startDate) {
      q = q.where('date', '>=', startDate);
    } else if (endDate) {
      q = q.where('date', '<=', endDate);
    }
    if (user && !['SUPER_ADMIN', 'COMPANY_MASTER', 'RAILWAY_MASTER', 'ADMIN'].includes((user.role || '').toUpperCase())) {
      const userStations = user.stations || (user.stationId ? [user.stationId] : []);
      if (stationId) {
        if (userStations.length > 0 && !userStations.includes(stationId)) {
          throw new ForbiddenError('You can only access tasks for your assigned stations');
        }
      } else if (userStations.length === 1) {
        q = q.where('stationId', '==', userStations[0]);
      } else if (userStations.length > 1) {
        q = q.where('stationId', 'in', userStations);
      }
    }
    const snapshot = await q.limit(300).get();
    let tasks = [];
    const now = new Date();
    snapshot.forEach(doc => {
      const t = { id: doc.id, ...doc.data() };
      const taskDate = t.date || t.scheduledDate || '';
      const taskTime = t.scheduledTime || '23:59';
      const taskDateTime = new Date(`${taskDate}T${taskTime}:00`);
      const actionableStatuses = ['pending', 'assigned', 'in_progress'];
      t.isOverdue = actionableStatuses.includes(t.status) && taskDateTime < now;
      t.isDue = actionableStatuses.includes(t.status) && !t.isOverdue;
      tasks.push(t);
    });

    // Contractor supervisors/workers must only receive their own tasks, even
    // when no workerId/supervisorId filter is supplied (prevents them from
    // seeing other shifts/supervisors at the station).
    if (user && workerId === undefined && supervisorId === undefined && _OWN_TASK_ROLES.has(_normalizeRole(user.role))) {
      tasks = tasks.filter(t => t.workerId === user.uid || t.supervisorId === user.uid);
    }
    // Shift-window enforcement for supervisor roles: they only ever see tasks
    // that belong to their recorded shift.
    if (user && _SHIFT_SCOPED_ROLES.has(_normalizeRole(user.role))) {
      const ownShift = await this._getSupervisorShift(user.uid);
      if (ownShift) {
        tasks = tasks.filter(t => !t.shift || String(t.shift).trim().toLowerCase() === ownShift);
      }
    }
    // Today-only enforcement for contractor roles: they can never see (or
    // pull up) tasks from any other day — only the current IST day.
    if (user && this._isOwnTaskRole(user.role)) {
      const todayIST = getISTDateStr();
      tasks = tasks.filter(t => {
        const d = t.date || t.scheduledDate || '';
        return !d || d === todayIST;
      });
    }

    if (includeOverdue === 'true') {
      tasks = tasks.filter(t => t.isOverdue);
    }

    tasks.sort((a, b) => {
      const aTime = a.createdAt ? new Date(a.createdAt).getTime() : 0;
      const bTime = b.createdAt ? new Date(b.createdAt).getTime() : 0;
      return bTime - aTime;
    });

    return { count: tasks.length, tasks };
  }

  async getTaskById(taskId, user) {
    const doc = await db.collection('cleaningTasks').doc(taskId).get();
    if (!doc.exists) throw new NotFoundError('Task not found');
    const task = { id: doc.id, ...doc.data() };
    const role = (user?.role || '').toUpperCase();
    if (!['SUPER_ADMIN', 'COMPANY_MASTER', 'RAILWAY_MASTER', 'ADMIN'].includes(role)) {
      const userStations = user?.stations || (user?.stationId ? [user.stationId] : []);
      if (userStations.length > 0 && task.stationId && !userStations.includes(task.stationId)) {
        throw new ForbiddenError('You can only access tasks in your assigned stations');
      }
    }
    return task;
  }

  async updateTaskStatus(taskId, status, user) {
    const ref = db.collection('cleaningTasks').doc(taskId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Task not found');

    const allowedStatuses = ['pending', 'assigned', 'in_progress', 'completed', 'approved', 'rejected', 'resubmitted'];
    if (!allowedStatuses.includes(status)) {
      throw new ValidationError(`Invalid status: ${status}. Allowed: ${allowedStatuses.join(', ')}`);
    }

    const updates = { status, updatedAt: new Date().toISOString(), updatedBy: user.uid };
    if (status === 'in_progress') updates.startedAt = new Date().toISOString();
    if (status === 'completed') updates.completedAt = new Date().toISOString();
    if (status === 'approved') updates.approvedAt = new Date().toISOString();
    if (status === 'rejected') updates.rejectedAt = new Date().toISOString();
    if (status === 'resubmitted') updates.resubmittedAt = new Date().toISOString();

    await ref.update(updates);
    return { message: `Task ${status}`, taskId };
  }

  async assignTask(taskId, workerId, workerName, user) {
    const ref = db.collection('cleaningTasks').doc(taskId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Task not found');
    await ref.update({
      workerId, workerName,
      assignedBy: user.uid, assignedByName: user.fullName || user.name || 'Unknown',
      updatedAt: new Date().toISOString()
    });
    return { message: 'Task assigned', taskId };
  }

  async getWorkerTasks(workerId, date) {
    if (!workerId) throw new ValidationError('workerId is required');
    let q = db.collection('cleaningTasks').where('workerId', '==', workerId);
    const snapshot = await q.orderBy('updatedAt', 'desc').limit(100).get();
    let tasks = [];
    snapshot.forEach(doc => tasks.push({ id: doc.id, ...doc.data() }));
    if (date) {
      tasks = tasks.filter(t => t.date === date || t.scheduledDate === date);
    }
    // Contractor workers are locked to today (IST) — they can never pull up
    // other days' work.
    tasks = tasks.filter(t => {
      const d = t.date || t.scheduledDate || '';
      return !d || d === getISTDateStr();
    });
    // Shift-window enforcement: a contractor worker/supervisor only sees tasks
    // belonging to their recorded shift (worker id == supervisor id here).
    const ownShift = await this._getOwnShift(workerId);
    if (ownShift) {
      tasks = tasks.filter(t => !t.shift || String(t.shift).trim().toLowerCase() === ownShift);
    }
    tasks.sort((a, b) => ((a.scheduledTime || '00:00').localeCompare(b.scheduledTime || '00:00')));
    return { count: tasks.length, tasks };
  }

  async getAreaTasks(areaId, date, statusFilter) {
    if (!areaId) throw new ValidationError('areaId is required');
    let q = db.collection('cleaningTasks').where('areaId', '==', areaId);
    const snapshot = await q.orderBy('updatedAt', 'desc').limit(200).get();
    let tasks = [];
    snapshot.forEach(doc => tasks.push({ id: doc.id, ...doc.data() }));
    if (date) {
      tasks = tasks.filter(t => t.date === date || t.scheduledDate === date);
    }
    if (statusFilter) {
      tasks = tasks.filter(t => t.status === statusFilter);
    }
    tasks.sort((a, b) => ((a.scheduledTime || '00:00').localeCompare(b.scheduledTime || '00:00')));
    return { count: tasks.length, tasks };
  }

  async getDailyTasks(date, user) {
    if (!date) date = new Date().toISOString().split('T')[0];
    const role = _normalizeRole(user?.role);
    const isOwnTaskRole = _OWN_TASK_ROLES.has(role);
    let q = db.collection('cleaningTasks').limit(500);
    if (!['SUPER_ADMIN', 'COMPANY_MASTER', 'RAILWAY_MASTER', 'ADMIN'].includes(role)) {
      const userStations = user?.stations || (user?.stationId ? [user.stationId] : []);
      if (userStations.length === 1) {
        q = q.where('stationId', '==', userStations[0]);
      } else if (userStations.length > 1) {
        q = q.where('stationId', 'in', userStations);
      }
    }
    const snapshot = await q.get();
    let tasks = [];
    snapshot.forEach(doc => tasks.push({ id: doc.id, ...doc.data() }));
    // Contractor roles are locked to today (IST): they can never view other
    // days even if an explicit date is requested.
    if (isOwnTaskRole) {
      const todayIST = getISTDateStr();
      tasks = tasks.filter(t => {
        const d = t.date || t.scheduledDate || '';
        return !d || d === todayIST;
      });
    } else {
      tasks = tasks.filter(t => t.date === date || t.scheduledDate === date);
    }
    // Contractor supervisors/workers must only ever see their own tasks
    // (their shift), never other shifts/supervisors on the same station.
    if (isOwnTaskRole) {
      tasks = tasks.filter(t => t.workerId === user?.uid || t.supervisorId === user?.uid);
    }
    // Shift-window enforcement for supervisor roles.
    if (user && _SHIFT_SCOPED_ROLES.has(_normalizeRole(user.role))) {
      const ownShift = await this._getSupervisorShift(user.uid);
      if (ownShift) {
        tasks = tasks.filter(t => !t.shift || String(t.shift).trim().toLowerCase() === ownShift);
      }
    }
    return { count: tasks.length, date, tasks };
  }

  async getSupervisorTasks(supervisorId, date, statusFilter, user) {
    if (!supervisorId) throw new ValidationError('supervisorId is required');
    const role = (user?.role || '').toUpperCase();
    const reqUserIsOwnTaskRole = _OWN_TASK_ROLES.has(_normalizeRole(user?.role));
    if (!['SUPER_ADMIN', 'COMPANY_MASTER', 'RAILWAY_MASTER', 'ADMIN'].includes(role)) {
      const allowedSupervisorIds = [user?.uid];
      if (user?.contractId) {
        const supSnap = await db.collection('users').where('contractId', '==', user.contractId).where('role', '==', 'Contractor Supervisor').get();
        supSnap.forEach(d => allowedSupervisorIds.push(d.id));
      }
      if (!allowedSupervisorIds.includes(supervisorId)) {
        throw new ForbiddenError('You can only view tasks for supervisors in your contract');
      }
    }
    const snapshot = await db.collection('cleaningTasks')
      .where('supervisorId', '==', supervisorId)
      .get();
    let tasks = [];
    const now = new Date();
    snapshot.forEach(doc => {
      const t = { id: doc.id, ...doc.data() };
      const taskDate = t.date || t.scheduledDate || '';
      const taskTime = t.scheduledTime || '23:59';
      const taskDateTime = new Date(`${taskDate}T${taskTime}:00`);
      const actionableStatuses = ['pending', 'assigned', 'in_progress'];
      t.isOverdue = actionableStatuses.includes(t.status) && taskDateTime < now;
      t.isDue = actionableStatuses.includes(t.status) && !t.isOverdue;
      tasks.push(t);
    });
    if (date && !reqUserIsOwnTaskRole) {
      tasks = tasks.filter(t => t.date === date || t.scheduledDate === date);
    }
    // Contractor roles are locked to today (IST) — never other days.
    if (reqUserIsOwnTaskRole) {
      const todayIST = getISTDateStr();
      tasks = tasks.filter(t => {
        const d = t.date || t.scheduledDate || '';
        return !d || d === todayIST;
      });
    }
    // Shift-window enforcement: a contractor supervisor's screen only ever
    // shows tasks belonging to their recorded shift.
    const ownShift = await this._getSupervisorShift(supervisorId);
    if (ownShift) {
      tasks = tasks.filter(t => !t.shift || String(t.shift).trim().toLowerCase() === ownShift);
    }
    if (statusFilter) {
      tasks = tasks.filter(t => t.status === statusFilter);
    }
    tasks.sort((a, b) => ((a.scheduledTime || '00:00').localeCompare(b.scheduledTime || '00:00')));
    return { count: tasks.length, tasks };
  }

  async getAreaFrequencyStatus(areaIds, date, areaFrequencies) {
    if (!areaIds || !Array.isArray(areaIds) || areaIds.length === 0) {
      throw new ValidationError('areaIds array is required');
    }
    const targetDate = date || new Date().toISOString().split('T')[0];
    const result = {};
    const chunkSize = 10;
    for (let i = 0; i < areaIds.length; i += chunkSize) {
      const chunk = areaIds.slice(i, i + chunkSize);
      const [existingTasksSnap, areaDocs] = await Promise.all([
        db.collection('cleaningTasks')
          .where('date', '==', targetDate)
          .where('areaId', 'in', chunk)
          .select('areaId', 'scheduledTime', 'status')
          .get(),
        Promise.all(chunk.map(id =>
          db.collection('areas').doc(id).get()
            .then(d => d.exists ? d : db.collection('stationAreas').doc(id).get())
        )),
      ]);
      const usedTimesByArea = new Map();
      existingTasksSnap.forEach(doc => {
        const d = doc.data();
        if (d.status === 'cancelled') return;
        if (!d.scheduledTime) return;
        if (!usedTimesByArea.has(d.areaId)) usedTimesByArea.set(d.areaId, new Set());
        usedTimesByArea.get(d.areaId).add(d.scheduledTime);
      });
      areaDocs.forEach((doc, idx) => {
        if (!doc.exists) return;
        const areaId = chunk[idx];
        const area = doc.data();
        const frequency = area.cleaningFrequency || area.frequency || 'daily';
        const areaFreq = (areaFrequencies && areaFrequencies[areaId] !== undefined)
          ? parseInt(areaFrequencies[areaId], 10)
          : null;
        let frequencyTimes = areaFreq
          ? this._buildTimeslots(areaFreq, frequency)
          : (area.frequencyTimes || this._getDefaultFrequencyTimes(frequency));
        // Daily total = the area's required count (boq) when set, else the slot list length.
        // When the required total exceeds the default slot list, expand the list to that
        // many evenly spaced slots so every requirement can be scheduled distinctly.
        const totalTimes = areaFreq
          ? frequencyTimes.length
          : ((area.boqTimesPerPeriod && area.boqTimesPerPeriod > 0) ? area.boqTimesPerPeriod : frequencyTimes.length);
        if (!areaFreq && frequencyTimes.length < totalTimes) {
          frequencyTimes = this._buildTimeslots(totalTimes, frequency);
        }
        const usedSet = usedTimesByArea.get(areaId);
        const usedTimes = usedSet ? usedSet.size : 0;
        result[areaId] = {
          areaId,
          frequency,
          totalTimes,
          usedTimes,
          remainingTimes: Math.max(0, totalTimes - usedTimes),
          frequencyTimes,
          scheduledTimes: usedSet ? Array.from(usedSet).sort() : []
        };
      });
    }
    return { date: targetDate, areas: result };
  }

  _resolveActivityForArea(areaId, areaData, data = {}) {
    const { areaActivities, activityType, taskTypeId, taskTypeName } = data;
    const perArea = areaActivities ? areaActivities[areaId] : null;
    if (perArea) {
      if (typeof perArea === 'string') {
        return {
          id: null,
          name: perArea,
          label: perArea.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())
        };
      }
      return {
        id: perArea.uid || perArea.id || taskTypeId || null,
        name: perArea.name || taskTypeName || '',
        label: perArea.label || (perArea.name ? perArea.name.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase()) : taskTypeName || (areaData.areaType || 'Cleaning'))
      };
    }
    if (activityType) {
      return {
        id: taskTypeId || null,
        name: taskTypeName || activityType,
        label: activityType.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())
      };
    }
    return null;
  }

  _resolveActivitiesForArea(areaId, areaData, data = {}) {
    const perArea = data.areaActivities ? data.areaActivities[areaId] : null;
    if (Array.isArray(perArea)) {
      return perArea
        .filter(a => a && (typeof a === 'string' || a.uid || a.id || a.name || a.label))
        .map(a => this._resolveActivityForArea(areaId, areaData, { ...data, areaActivities: { [areaId]: a } }))
        .filter(Boolean);
    }
    const single = this._resolveActivityForArea(areaId, areaData, data);
    return single ? [single] : [];
  }

  async bulkGenerate(data, user) {
    const { areaIds, date, workerId, workerIds, zoneIds, supervisorId, frequency } = data;
    const areaFrequencies = data.areaFrequencies || null;
    const areaTimes = data.areaTimes || null;
    const timesCount = data.timesCount ? parseInt(data.timesCount, 10) || null : null;
    const normalize = data.normalize === true;
    // Canonical (lowercase) shift so attendance / shift-summary comparisons
    // stay consistent regardless of how the caller spell-cases it.
    const genShift = data.shift ? String(data.shift).trim().toLowerCase() : null;
    if (!areaIds || !Array.isArray(areaIds) || areaIds.length === 0) {
      throw new ValidationError('areaIds array is required');
    }
    const targetDate = date || new Date().toISOString().split('T')[0];
    let total = 0;
    let cancelledTotal = 0;
    const allTaskIds = [];

    // Pre-resolve area data so the main loop does not re-fetch each document.
    // When the caller passed activity selections (the task generation screen),
    // every area must resolve to at least one activity BEFORE any writes happen —
    // areas without an activity never generate tasks.
    const activityHintsPresent = data && (
      'taskActivities' in data ||
      'areaActivities' in data ||
      data.activityType ||
      data.taskTypeId ||
      data.taskTypeName
    );
    const activitiesByArea = new Map();
    const missingActivityAreas = [];
    for (const areaId of areaIds) {
      let areaDoc = await db.collection('areas').doc(areaId).get();
      if (!areaDoc.exists) {
        areaDoc = await db.collection('stationAreas').doc(areaId).get();
      }
      const areaData = areaDoc.exists ? areaDoc.data() : {};
      const resolved = this._resolveActivitiesForArea(areaId, areaData, data);
      activitiesByArea.set(areaId, { doc: areaDoc, data: areaData, activities: resolved });
      if (activityHintsPresent && resolved.length === 0) {
        missingActivityAreas.push(areaData.areaName || areaData.name || areaData.areaCode || areaId);
      }
    }
    if (missingActivityAreas.length > 0) {
      throw new ValidationError(
        `No cleaning activity selected for: ${missingActivityAreas.join(', ')}. Select at least one activity per area before generating tasks.`
      );
    }

    // Resolve the supervisor if provided
    let assignedSupervisorId = null;
    let assignedSupervisorName = '';
    if (supervisorId) {
      const supDoc = await db.collection('users').doc(supervisorId).get();
      if (supDoc.exists) {
        const supData = supDoc.data();
        assignedSupervisorId = supervisorId;
        assignedSupervisorName = supData.fullName || supData.name || '';
      }
    }
    if (genShift && assignedSupervisorId) {
      const firstArea = areaIds[0];
      const firstAreaData = activitiesByArea.get(firstArea)?.data || {};
      await this._setSupervisorShift(
        assignedSupervisorId,
        genShift,
        firstAreaData.stationId || '',
        data.contractId || '',
        assignedSupervisorName
      );
    }

    let assignedWorker = null;
    let assignedWorkers = [];
    if (workerIds && Array.isArray(workerIds) && workerIds.length > 0) {
      const workerDocs = await Promise.all(
        workerIds.map(wId => db.collection('users').doc(wId).get())
      );
      assignedWorkers = workerDocs
        .filter(d => d.exists)
        .map(d => ({ uid: d.id, ...d.data() }));
      if (assignedWorkers.length === 0) {
        throw new NotFoundError('None of the specified workers were found');
      }
    } else if (workerId) {
      const workerDoc = await db.collection('users').doc(workerId).get();
      if (!workerDoc.exists) {
        throw new NotFoundError(`Worker with ID ${workerId} not found`);
      }
      assignedWorker = { uid: workerDoc.id, ...workerDoc.data() };
    }

    const existingTaskKeys = new Set();
    const usedTimesByArea = new Map();
    const tasksByArea = new Map();
    const chunkSize = 10;
    for (let i = 0; i < areaIds.length; i += chunkSize) {
      const chunk = areaIds.slice(i, i + chunkSize);
      const existingTasksSnap = await db.collection('cleaningTasks')
        .where('date', '==', targetDate)
        .where('areaId', 'in', chunk)
        .select('workerId', 'areaId', 'scheduledTime', 'taskTypeId', 'status')
        .get();
      existingTasksSnap.forEach(doc => {
        const d = doc.data();
        if (d.status === 'cancelled') return;
        existingTaskKeys.add(`${d.areaId}|${d.workerId}|${d.scheduledTime}|${d.taskTypeId || 'default'}`);
        if (d.scheduledTime) {
          if (!usedTimesByArea.has(d.areaId)) usedTimesByArea.set(d.areaId, new Set());
          usedTimesByArea.get(d.areaId).add(d.scheduledTime);
          if (!tasksByArea.has(d.areaId)) tasksByArea.set(d.areaId, []);
          tasksByArea.get(d.areaId).push({ id: doc.id, scheduledTime: d.scheduledTime });
        }
      });
    }

    // Station-cleaning scope: only generate tasks for areas belonging to an
    // active station-cleaning contract. Other contract types are skipped so
    // this generic generator never writes tasks for other domains.
    const stationCleaningContractByStation = new Map();
    for (const areaId of areaIds) {
      const cachedArea = activitiesByArea.get(areaId) || { data: {} };
      const stationId = cachedArea.data.stationId || '';
      if (!stationId || stationCleaningContractByStation.has(stationId)) continue;
      const contract = await this._getActiveStationCleaningContract(stationId);
      stationCleaningContractByStation.set(stationId, contract.uid || '');
    }

    for (const areaId of areaIds) {
      const workersSnap = assignedWorker || assignedWorkers.length > 0
        ? null
        : await db.collection('areaWorkerAssignments').where('areaId', '==', areaId).where('isActive', '==', true).limit(200).get();
      const cachedArea = activitiesByArea.get(areaId) || { doc: null, data: {}, activities: [] };
      const areaData = cachedArea.data;
      const activities = cachedArea.activities;
      if (!stationCleaningContractByStation.get(areaData.stationId || '')) {
        continue;
      }
      const taskActivities = activities.length > 0 ? activities : [null];
      const cleaningFrequency = frequency || areaData.cleaningFrequency || areaData.frequency || 'daily';
      // Per-area EXACT time slots: when the admin picks specific times, those
      // are the authoritative slot set — the count/frequency machinery below
      // is skipped. Times must be 24-hour HH:MM; each slot keeps its own shift
      // (derived from the time) instead of being filtered to the chosen shift.
      const customTimes = data.areaTimeSlots && data.areaTimeSlots[areaId];
      const useCustomTimes = Array.isArray(customTimes) && customTimes.length > 0;
      let frequencyTimes;
      if (useCustomTimes) {
        const cleaned = [];
        for (const raw of customTimes) {
          const s = String(raw).trim();
          const m = /^(\d{1,2}):([0-5]\d)$/.exec(s);
          if (!m || parseInt(m[1], 10) > 23) {
            throw new ValidationError(`Invalid time slot "${raw}" for area ${areaData.areaName || areaCode || areaId}. Use 24-hour HH:MM.`);
          }
          cleaned.push(`${String(parseInt(m[1], 10)).padStart(2, '0')}:${m[2]}`);
        }
        frequencyTimes = [...new Set(cleaned)];
      } else {
        // Per-area override: contractor admin assigns how many times per day.
        const areaFreq = (areaFrequencies && areaFrequencies[areaId] !== undefined)
          ? parseInt(areaFrequencies[areaId], 10)
          : null;
        frequencyTimes = areaFreq
          ? this._buildTimeslots(areaFreq, cleaningFrequency)
          : (areaData.frequencyTimes || this._getDefaultFrequencyTimes(cleaningFrequency));
      }
      const normalizeDesired = (normalize && areaTimes && areaTimes[areaId] != null)
        ? parseInt(areaTimes[areaId], 10) || 0
        : null;
      // In normalize mode the daily count is authoritative, so the slot pool must be
      // wide enough to hold that many distinct occurrences. Expand it when needed
      // (custom time slots are already the exact set and never auto-expand).
      if (normalizeDesired != null && !useCustomTimes && frequencyTimes.length < normalizeDesired) {
        frequencyTimes = this._buildTimeslots(normalizeDesired, cleaningFrequency);
      }
      // Shift-window enforcement: when a specific shift was chosen, only slots
      // whose time falls inside that shift's window are generated. Choosing
      // "morning" therefore never produces 14:00/18:00/22:00 tasks. Custom time
      // slots carry their own shift and bypass this filter.
      if (genShift && !useCustomTimes) {
        frequencyTimes = frequencyTimes.filter(t => this._shiftForTime(t) === genShift);
      }
      const batch = db.batch();
      // Partial/frequency-based assignment: only create tasks for occurrences that
      // have not already been generated for this area on this date. The admin picks
      // how many of the remaining occurrences to assign (default: all remaining).
      const alreadyUsed = usedTimesByArea.get(areaId) || new Set();
      const availableTimes = frequencyTimes.filter(t => !alreadyUsed.has(t));
      const requestedCount = areaTimes && areaTimes[areaId] != null
        ? parseInt(areaTimes[areaId], 10) || 0
        : (timesCount || availableTimes.length);
      let batchCount = 0;
      let batchCancelled = 0;

      // In "normalize" mode (daily-count is authoritative), reconcile today's
      // active tasks for this area to EXACTLY the requested count:
      //   - more tasks exist  -> cancel the extras (prefer ones outside the slot list)
      //   - fewer             -> create the missing occurrences at the next free slots
      let timesToUse = [];
      if (useCustomTimes && normalizeDesired != null) {
        // EXACT-TIME mode: the picked HH:MM slots are authoritative and
        // ADDITIVE. A chosen time that already has an active task is never
        // duplicated (the existing slot wins); the run instead creates only the
        // chosen times that are still missing, each assigned to the supervisor
        // of the shift its time falls in. Tasks outside the picked set are left
        // untouched so an admin can add a specific-time / extra task without
        // wiping the day's other scheduled work.
        const areaTasks = tasksByArea.get(areaId) || [];
        const slotSet = new Set(frequencyTimes);
        const dupTimes = new Set();
        for (const t of areaTasks) {
          if (!slotSet.has(t.scheduledTime)) continue;
          if (dupTimes.has(t.scheduledTime)) {
            batch.update(db.collection('cleaningTasks').doc(t.id), {
              status: 'cancelled',
              // Marks the slot as deliberately closed by a manual override so the
              // auto (cron/schedule) generator does not recreate the task at this
              // time later in the day (see generateTasksFromSchedule).
              manualOverride: true,
              updatedAt: new Date().toISOString(),
            });
            batchCount++;
            batchCancelled++;
            continue;
          }
          dupTimes.add(t.scheduledTime);
        }
        timesToUse = frequencyTimes.filter(t => !dupTimes.has(t));
      } else if (normalizeDesired != null) {
        // NORMALIZE-by-count mode: reconcile today's active tasks for this area
        // to EXACTLY the requested count:
        //   - more tasks exist  -> cancel the extras (prefer ones outside the slot list)
        //   - fewer             -> create the missing occurrences at the next free slots
        const areaTasks = tasksByArea.get(areaId) || [];
        const activeCount = areaTasks.length;
        if (activeCount > normalizeDesired) {
          const slotSet = new Set(frequencyTimes);
          const sortable = areaTasks.slice().sort((a, b) => (a.scheduledTime || '').localeCompare(b.scheduledTime || ''));
          const candidates = [
            ...sortable.filter(t => !slotSet.has(t.scheduledTime)),
            ...sortable.filter(t => slotSet.has(t.scheduledTime)),
          ];
          candidates.slice(0, activeCount - normalizeDesired).forEach(t => {
            batch.update(db.collection('cleaningTasks').doc(t.id), {
              status: 'cancelled',
              // Marks the slot as deliberately closed by a manual override so the
              // auto (cron/schedule) generator does not recreate the task at this
              // time later in the day (see generateTasksFromSchedule).
              manualOverride: true,
              updatedAt: new Date().toISOString(),
            });
            batchCount++;
            batchCancelled++;
          });
        }
        const need = normalizeDesired - activeCount;
        timesToUse = need > 0 ? availableTimes.slice(0, need) : [];
      } else {
        timesToUse = availableTimes.slice(0, Math.max(0, Math.min(requestedCount, availableTimes.length)));
      }
      const baseAreaName = areaData.areaName || areaData.name || '';
      const areaCode = areaData.areaCode || '';
      const mainArea = areaData.mainArea || '';

      // Determine the list of target zones for this area
      let targetZones = [null];
      if (zoneIds && Array.isArray(zoneIds) && zoneIds.length > 0) {
        const zoneDocs = await Promise.all(zoneIds.map(zId => db.collection('stationZones').doc(zId).get()));
        targetZones = zoneDocs
          .filter(doc => doc.exists && doc.data().areaId === areaId)
          .map(doc => ({ uid: doc.id, name: doc.data().zoneName || doc.data().name || '' }));
        if (targetZones.length === 0) {
          targetZones = [null];
        }
      }

      const buildTask = (workerInfo, zoneInfo, scheduledTime, activity) => {
        const taskRef = db.collection('cleaningTasks').doc();
        const displayAreaName = [mainArea, baseAreaName, zoneInfo?.name].filter(Boolean).join(' - ');
        const task = {
          uid: taskRef.id,
          stationId: workerInfo.stationId || '',
          platformId: workerInfo.platformId || null,
          areaId,
          areaName: displayAreaName,
          areaCode,
          mainArea,
          zoneId: zoneInfo ? zoneInfo.uid : null,
          zoneName: zoneInfo ? zoneInfo.name : null,
          workerId: workerInfo.workerId,
          workerName: workerInfo.workerName || 'Unknown',
          supervisorId: workerInfo.supervisorId,
          supervisorName: workerInfo.supervisorName || '',
          assignmentId: workerInfo.assignmentId || null,
          activityType: activity ? activity.label : (areaData.areaType || 'Cleaning'),
          taskTypeId: activity ? activity.id : null,
          taskTypeName: activity ? activity.name : null,
          frequency: cleaningFrequency,
          date: targetDate,
          scheduledDate: targetDate,
          scheduledTime,
          priority: areaData.priority || 3,
          shift: workerInfo.shift,
          status: 'pending',
          startedAt: null, completedAt: null,
          approvedAt: null, rejectedAt: null,
          beforePhoto: null, afterPhoto: null,
          gpsLat: null, gpsLng: null,
          supervisorNotes: null, rejectionReason: null,
          source: 'manual',
          generationKey: `${areaData.stationId || workerInfo.stationId || ''}|${areaId}|${targetDate}|${workerInfo.shift || 'morning'}`,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: new Date().toISOString()
        };
        return { taskRef, task };
      };

      // For station-cleaning contracts, resolve each slot's supervisor from
      // stationSupervisorShifts so night/evening tasks go to the correct
      // shift supervisor rather than all going to the same one. Mirrors the
      // auto-generator's pickSupervisorForSlot: only RECORDED shifts claim a
      // supervisor (supervisors who never recorded a shift must not hijack
      // another supervisor's window), and the primary/morning supervisor is
      // the fallback for unrecorded morning slots.
      let slotSupervisorResolver = null;
      const isStationCleaning = stationCleaningContractByStation.has(areaData.stationId || '');
      if (isStationCleaning) {
        const contractId = stationCleaningContractByStation.get(areaData.stationId || '');
        const supMap = await this._stationSupervisorShifts(contractId, areaData.stationId || '');
        const byRecordedShift = new Map();
        for (const sup of supMap.values()) {
          if (!sup.recorded) continue;
          if (!byRecordedShift.has(sup.shift)) byRecordedShift.set(sup.shift, sup);
        }
        const primaryKey = assignedSupervisorId || data.supervisorId || '';
        const primarySupervisor = supMap.get(primaryKey) || supMap.values().next().value || null;
        slotSupervisorResolver = (scheduledTime) => {
          if (supMap.size === 0) return null;
          const slotShift = this._shiftForTime(scheduledTime) || 'morning';
          return byRecordedShift.get(slotShift)
            || (slotShift === 'morning' ? (supMap.get(primaryKey) || supMap.values().next().value) : null)
            || null;
        };
      }

      const processWorker = (workerInfo, resolver) => {
        for (const scheduledTime of timesToUse) {
          const slotSup = resolver ? resolver(scheduledTime) : null;
          const effectiveWorker = slotSup ? {
            ...workerInfo,
            workerId: slotSup.uid,
            workerName: slotSup.fullName || workerInfo.workerName,
            supervisorId: slotSup.uid,
            supervisorName: slotSup.fullName || workerInfo.supervisorName,
            shift: this._shiftForTime(scheduledTime) || workerInfo.shift || 'morning',
          } : workerInfo;
          for (const zoneInfo of targetZones) {
            for (const activity of taskActivities) {
              const dupKey = `${areaId}|${effectiveWorker.workerId}|${scheduledTime}|${activity ? (activity.id || 'default') : 'default'}`;
              if (existingTaskKeys.has(dupKey)) continue;
              const { taskRef, task } = buildTask(effectiveWorker, zoneInfo, scheduledTime, activity);
              batch.set(taskRef, task);
              allTaskIds.push(taskRef.id);
              batchCount++;
            }
          }
        }
      };

      if (assignedWorkers.length > 0) {
        let workerIdx = 0;
        for (const scheduledTime of timesToUse) {
          for (const zoneInfo of targetZones) {
            const w = assignedWorkers[workerIdx % assignedWorkers.length];
            workerIdx++;
            for (const activity of taskActivities) {
              const dupKey = `${areaId}|${w.uid}|${scheduledTime}|${activity ? (activity.id || 'default') : 'default'}`;
              if (existingTaskKeys.has(dupKey)) continue;
              const { taskRef, task } = buildTask({
                workerId: w.uid,
                workerName: w.fullName || w.name || 'Unknown',
                stationId: areaData.stationId || w.stationId || '',
                platformId: areaData.platformId || null,
                supervisorId: assignedSupervisorId || areaData.supervisorId || null,
                supervisorName: assignedSupervisorName || areaData.supervisorName || '',
                shift: genShift || areaData.defaultShift || 'morning',
              }, zoneInfo, scheduledTime, activity);
              batch.set(taskRef, task);
              allTaskIds.push(taskRef.id);
              batchCount++;
            }
          }
        }
      } else if (assignedWorker) {
        processWorker({
          workerId: assignedWorker.uid,
          workerName: assignedWorker.fullName || assignedWorker.name || 'Unknown',
          stationId: areaData.stationId || assignedWorker.stationId || '',
          platformId: areaData.platformId || null,
          supervisorId: assignedSupervisorId || areaData.supervisorId || null,
          supervisorName: assignedSupervisorName || areaData.supervisorName || '',
          shift: genShift || areaData.defaultShift || 'morning',
        });
      } else if (data.supervisorId) {
        // When a (contract) supervisor is explicitly assigned and no specific
        // worker is selected, generate all tasks for that supervisor themself.
        // Do NOT fall back to every worker assigned to the area, otherwise the
        // supervisor would see the whole team's tasks.
        const supervisorWorkerId = assignedSupervisorId || data.supervisorId;
        const supervisorWorkerName = assignedSupervisorName || 'Supervisor';
        processWorker({
          workerId: supervisorWorkerId,
          workerName: supervisorWorkerName,
          stationId: areaData.stationId || '',
          platformId: areaData.platformId || null,
          supervisorId: supervisorWorkerId,
          supervisorName: supervisorWorkerName,
          shift: genShift || areaData.defaultShift || 'morning',
        }, slotSupervisorResolver);
      } else if (workersSnap && workersSnap.size > 0) {
        workersSnap.forEach(workerDoc => {
          const assignment = workerDoc.data();
          processWorker({
            workerId: assignment.workerId,
            workerName: assignment.workerName,
            stationId: areaData.stationId || assignment.stationId,
            platformId: areaData.platformId || assignment.platformId || null,
            assignmentId: assignment.uid,
            supervisorId: assignedSupervisorId || areaData.supervisorId || null,
            supervisorName: assignedSupervisorName || areaData.supervisorName || '',
            shift: assignment.shift || areaData.defaultShift || 'morning',
          });
        });
      } else if (assignedSupervisorId) {
        processWorker({
          workerId: assignedSupervisorId,
          workerName: assignedSupervisorName || 'Supervisor',
          stationId: areaData.stationId || '',
          platformId: areaData.platformId || null,
          supervisorId: assignedSupervisorId,
          supervisorName: assignedSupervisorName || '',
          shift: genShift || areaData.defaultShift || 'morning',
        }, slotSupervisorResolver);
      }

      if (batchCount > 0) {
        await batch.commit();
        total += batchCount - batchCancelled;
        cancelledTotal += batchCancelled;
      }
    }

    const normMsg = cancelledTotal > 0 ? `, cancelled ${cancelledTotal} extra` : '';
    return { message: `Generated ${total} tasks across ${areaIds.length} areas for ${targetDate}${normMsg}`, count: total, cancelled: cancelledTotal, taskIds: allTaskIds };
  }

  async generateTasksForDateRange(data, user) {
    const { areaIds, startDate, endDate, workerId } = data;
    if (!areaIds || !Array.isArray(areaIds) || areaIds.length === 0) {
      throw new ValidationError('areaIds array is required');
    }
    if (!startDate || !endDate) throw new ValidationError('startDate and endDate are required');
    const start = new Date(startDate);
    const end = new Date(endDate);
    if (start > end) throw new ValidationError('startDate must be before endDate');

    let total = 0;
    const allTaskIds = [];
    const current = new Date(start);

    while (current <= end) {
      const dateStr = current.toISOString().split('T')[0];
      const result = await this.bulkGenerate({ areaIds, date: dateStr, workerId, shift: data.shift, activityType: data.activityType, areaActivities: data.areaActivities, taskTypeId: data.taskTypeId, taskTypeName: data.taskTypeName }, user);
      total += result.count;
      allTaskIds.push(...result.taskIds);
      current.setDate(current.getDate() + 1);
    }

    return { message: `Generated ${total} tasks across ${areaIds.length} areas from ${startDate} to ${endDate}`, count: total, taskIds: allTaskIds };
  }
}

export const taskManagementService = new TaskManagementService();
