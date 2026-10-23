import { db, admin } from '../database/index.js';
import { NotFoundError, ValidationError, ForbiddenError, ConflictError } from '../errors/index.js';

class V2Service {
  async #logAudit(params) {
    try {
      await db.collection('audit_logs').add({ ...params, timestamp: db.Timestamp() });
    } catch (_) {}
  }

  #hasRolePermission(assignerRole, assigneeRole) {
    const hierarchy = { CM: 5, CA: 4, CTS: 3, CS: 2, supervisor: 2, janitor: 1, attendant: 1 };
    const assignerLevel = hierarchy[assignerRole] || 0;
    const assigneeLevel = hierarchy[assigneeRole] || 0;
    return assignerLevel > assigneeLevel || (assignerRole === 'CM') || (assignerRole === 'CA' && assigneeLevel <= 3);
  }

  async #updateParentTaskStatus(parentTaskId) {
    try {
      const parentRef = db.collection('task_instances').doc(parentTaskId);
      const parentDoc = await parentRef.get();
      if (!parentDoc.exists) return;
      const parentData = parentDoc.data();
      const childIds = parentData.childTaskIds || [];
      let allCompleted = true, anyOverdue = false, anyOpen = false, anyRejected = false, anyNA = false, anyReopened = false;
      for (const cId of childIds) {
        const cDoc = await db.collection('task_instances').doc(cId).get();
        if (!cDoc.exists) { allCompleted = false; continue; }
        const s = cDoc.data().status;
        const finalStates = ['COMPLETED', 'VERIFIED', 'CLOSED', 'NOT_APPLICABLE'];
        if (!finalStates.includes(s)) allCompleted = false;
        if (s === 'OVERDUE') anyOverdue = true;
        if (s === 'OPEN' || s === 'PLANNED') anyOpen = true;
        if (s === 'REJECTED') anyRejected = true;
        if (s === 'NOT_APPLICABLE') anyNA = true;
        if (s === 'REOPENED') anyReopened = true;
      }
      let newStatus;
      if (allCompleted) newStatus = 'COMPLETED';
      else if (anyReopened) newStatus = 'REOPENED';
      else if (anyRejected) newStatus = 'PARTIAL';
      else if (anyOverdue) newStatus = 'OVERDUE';
      else if (anyOpen) newStatus = 'IN_PROGRESS';
      else newStatus = parentData.status;
      if (newStatus !== parentData.status) {
        await parentRef.update({ status: newStatus, updatedAt: new Date().toISOString() });
      }
    } catch (_) {}
  }

  async listTaskMasters(query = {}) {
    const { active, assignedRole, category } = query;
    let firestoreQuery = db.collection('task_masters');
    if (active === 'true') firestoreQuery = firestoreQuery.where('active', '==', true);
    if (assignedRole) firestoreQuery = firestoreQuery.where('assignedRole', '==', assignedRole);
    if (category) firestoreQuery = firestoreQuery.where('category', '==', category);
    const snapshot = await firestoreQuery.limit(200).get();
    const masters = [];
    snapshot.forEach(doc => masters.push({ id: doc.id, ...doc.data() }));
    return { success: true, count: masters.length, masters };
  }

  async getTaskMasters() {
    const snapshot = await db.collection('task_masters').orderBy('taskCode').limit(200).get();
    const masters = [];
    snapshot.forEach(doc => masters.push(doc.data()));
    return { count: masters.length, taskMasters: masters };
  }

  async createTaskMaster(body, user) {
    if (!['CM', 'CA'].includes(user.role)) {
      throw new ForbiddenError('Only CM/CA can create task masters');
    }
    const { taskCode, taskName, category, subCategory, assignedRole, applicableCoachTypes,
      priority, frequencyRules, scheduledTime, checklistTemplate,
      requiresSupervisorVerification, conflictGroup } = body;

    if (!taskCode || !taskName || !assignedRole) {
      throw new ValidationError('taskCode, taskName, assignedRole are required');
    }

    const ref = db.collection('task_masters').doc(taskCode);
    const existing = await ref.get();
    if (existing.exists) {
      throw new ConflictError('Task master with this code already exists');
    }

    const data = {
      taskCode, taskName, category: category || 'custom', subCategory: subCategory || null,
      assignedRole, applicableCoachTypes: applicableCoachTypes || ['all'],
      priority: priority || 'medium', requiresSupervisorVerification: requiresSupervisorVerification || false,
      isComplaintDriven: false, conflictGroup: conflictGroup || taskCode,
      frequencyRules: frequencyRules || [], scheduledTime: scheduledTime || null,
      checklistTemplate: checklistTemplate || [],
      active: true, isSystem: false,
      createdBy: user.uid, createdByName: user.fullName,
      createdAt: new Date().toISOString(), updatedAt: new Date().toISOString()
    };
    await ref.set(data);

    await this.#logAudit({
      action: 'TASK_MASTER_CREATED', entityType: 'task_masters',
      entityId: taskCode, actorId: user.uid, actorRole: user.role,
      actorName: user.fullName, newValue: data,
      details: `Created task master: ${taskName} (${taskCode})`
    });

    return { success: true, message: 'Task master created', taskCode };
  }

  async updateTaskMaster(taskCode, body, user) {
    if (!['CM', 'CA'].includes(user.role)) {
      throw new ForbiddenError('Only CM/CA can update task masters');
    }
    const ref = db.collection('task_masters').doc(taskCode);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Task master not found');

    const oldData = doc.data();
    const updates = body;
    delete updates.taskCode;
    delete updates.isSystem;
    updates.updatedAt = new Date().toISOString();
    updates.updatedBy = user.uid;

    await ref.update(updates);

    await this.#logAudit({
      action: 'TASK_MASTER_UPDATED', entityType: 'task_masters',
      entityId: taskCode, actorId: user.uid, actorRole: user.role,
      actorName: user.fullName, oldValue: oldData, newValue: { ...oldData, ...updates },
      details: `Updated task master: ${taskCode}`
    });

    return { success: true, message: 'Task master updated' };
  }

  async createAssignments(body, user) {
    const { runInstanceId, assignments } = body;
    if (!runInstanceId || !assignments || !Array.isArray(assignments)) {
      throw new ValidationError('runInstanceId and assignments array are required');
    }

    const runRef = db.collection('RunInstance').doc(runInstanceId);
    const runDoc = await runRef.get();
    if (!runDoc.exists) throw new NotFoundError('Run instance not found');
    if (runDoc.data().status !== 'PLANNED') {
      throw new ValidationError('Can only assign workers to PLANNED journeys');
    }

    const batch = db.batch();
    const results = [];
    const runData = runDoc.data();

    for (const assign of assignments) {
      const { workerId, workerRole, coachNos, workerName } = assign;
      if (!workerId || !workerRole || !coachNos || !Array.isArray(coachNos)) {
        throw new ValidationError('Each assignment needs workerId, workerRole, coachNos[]');
      }

      if (!this.#hasRolePermission(user.role, workerRole)) {
        throw new ForbiddenError(`Cannot assign ${workerRole}. Your role (${user.role}) lacks permission.`);
      }

      if (workerRole === 'janitor' && coachNos.length > 2) {
        throw new ValidationError(`Janitor ${workerId} cannot be assigned more than 2 coaches (got ${coachNos.length})`);
      }

      if (workerRole === 'attendant') {
        for (const cn of coachNos) {
          const coach = runData.coaches.find(c => (c.coachPosition === cn || c.coachNo === cn));
          if (coach && coach.coachType !== 'AC' && coach.coachType !== 'ac') {
            throw new ValidationError(`Attendant can only be assigned to AC coaches. Coach ${cn} is not AC.`);
          }
        }
      }

      const assignmentId = `${runInstanceId}_${workerId}_${Date.now()}`;
      const ref = db.collection('worker_assignments').doc(assignmentId);
      batch.set(ref, {
        assignmentId, runInstanceId, workerId, workerRole,
        coachNos, assignedBy: user.uid,
        assignedByName: user.fullName,
        status: 'ACTIVE',
        createdAt: new Date().toISOString()
      });

      for (const cn of coachNos) {
        const coachIndex = runData.coaches.findIndex(c => (c.coachPosition === cn || c.coachNo === cn));
        if (coachIndex !== -1) {
          const coachRef = db.collection('RunInstance').doc(runInstanceId);
          batch.update(coachRef, {
            [`coaches.${coachIndex}.workerId`]: workerId,
            [`coaches.${coachIndex}.workerName`]: workerName || 'Unknown',
            [`coaches.${coachIndex}.workerRole`]: workerRole
          });
        }
      }

      results.push({ assignmentId, workerId, workerRole, coachNos });
    }

    await batch.commit();

    await runRef.update({ status: 'ALLOCATED', updatedAt: new Date().toISOString() });

    await this.#logAudit({
      action: 'WORKERS_ASSIGNED', entityType: 'RunInstance',
      entityId: runInstanceId, actorId: user.uid,
      actorRole: user.role, actorName: user.fullName,
      newValue: { assignments: results, status: 'ALLOCATED' },
      details: `Assigned ${assignments.length} workers to ${runInstanceId}`
    });

    return { success: true, message: 'Workers assigned', assignments: results };
  }

  async createAssignment(body) {
    const { runInstanceId, workerId, workerName, workerRole, coachNos } = body;
    const assignmentId = `${runInstanceId}_${workerId}`;
    await db.collection('v2_assignments').doc(assignmentId).set({
      assignmentId, runInstanceId, workerId, workerName, workerRole,
      coachNos: coachNos || [], status: 'ACTIVE',
      createdAt: new Date().toISOString(), updatedAt: new Date().toISOString()
    });
    return { message: 'Assignment created', assignmentId };
  }

  async getAssignments(runInstanceId) {
    const snapshot = await db.collection('worker_assignments')
      .where('runInstanceId', '==', runInstanceId)
      .where('status', '==', 'ACTIVE')
      .limit(200).get();
    const assignments = [];
    snapshot.forEach(doc => assignments.push(doc.data()));
    return { success: true, count: assignments.length, assignments };
  }

  async getTasks(runInstanceId, queryParams = {}) {
    const { coachNo, status, workerId } = queryParams;
    let query = db.collection('task_instances').where('runInstanceId', '==', runInstanceId);
    if (coachNo) query = query.where('coachNo', '==', coachNo);
    if (status) query = query.where('status', '==', status);
    if (workerId) query = query.where('workerId', '==', workerId);
    const snapshot = await query.limit(200).get();
    const tasks = [];
    snapshot.forEach(doc => tasks.push(doc.data()));
    return { success: true, count: tasks.length, tasks };
  }

  async submitTask(body, user) {
    const { taskInstanceId, checklistResponses, beforePhoto, afterPhoto,
      gpsLatitude, gpsLongitude, deviceTimestamp, deviceId, mobileNumber, comment } = body;

    if (!taskInstanceId || !beforePhoto || !afterPhoto || gpsLatitude === undefined || gpsLongitude === undefined) {
      throw new ValidationError('taskInstanceId, beforePhoto, afterPhoto, gpsLatitude, gpsLongitude are mandatory');
    }

    const ref = db.collection('task_instances').doc(taskInstanceId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Task instance not found');

    const taskData = doc.data();
    const role = String(user.role || '').toUpperCase().replace(/\s+/g, '_');
    if (['WORKER', 'RAILWAY_WORKER', 'JANITOR', 'ATTENDANT'].includes(role)) {
      const assignedWorkerId = taskData.workerId || taskData.assignedTo;
      if (assignedWorkerId !== user.uid) {
        throw new ForbiddenError('You can only submit tasks assigned to you.');
      }
    }
    if (['COMPLETED', 'VERIFIED', 'CLOSED', 'NOT_APPLICABLE'].includes(taskData.status)) {
      throw new ValidationError(`Task already in final state: ${taskData.status}`);
    }

    if (taskData.scheduledTime) {
      const now = new Date();
      const istNow = new Date(now.toLocaleString('en-US', { timeZone: 'Asia/Kolkata' }));
      const [sh, sm] = taskData.scheduledTime.split(':').map(Number);
      const scheduledMinutes = sh * 60 + (sm || 0);
      const currentMinutes = istNow.getHours() * 60 + istNow.getMinutes();
      
      let diff = currentMinutes - scheduledMinutes;
      if (diff < -12 * 60) diff += 24 * 60; // Rollover handling
      
      if (diff > 120 && diff < 12 * 60) {
        if (!comment || comment.trim().length < 5) {
           throw new ValidationError('Task is OVERDUE (grace period exceeded). A delay remark/comment is mandatory to unlock evidence submission.');
        }
      }
    }

    const updateData = {
      status: 'COMPLETED',
      beforePhoto, afterPhoto,
      gpsLatitude, gpsLongitude,
      deviceId: deviceId || null,
      mobileNumber: mobileNumber || null,
      checklistResponses: checklistResponses || [],
      comment: comment || null,
      completedBy: user.uid,
      completedByName: user.fullName,
      deviceTimestamp: deviceTimestamp || new Date().toISOString(),
      completedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    await ref.update(updateData);

    if (taskData.parentTaskId) {
      await this.#updateParentTaskStatus(taskData.parentTaskId);
    }

    await this.#logAudit({
      action: 'TASK_INSTANCE_COMPLETED', entityType: 'task_instances',
      entityId: taskInstanceId, actorId: user.uid,
      actorRole: user.role, actorName: user.fullName,
      oldValue: { status: taskData.status },
      newValue: { status: 'COMPLETED', gpsLatitude, gpsLongitude },
      details: `Completed ${taskData.taskName} for Coach ${taskData.coachNo}`
    });

    return { success: true, message: 'Task completed', taskInstanceId };
  }

  async startTask(body, user) {
    const { taskInstanceId, gpsLatitude, gpsLongitude, deviceId } = body;
    if (!taskInstanceId) throw new ValidationError('taskInstanceId required');

    const ref = db.collection('task_instances').doc(taskInstanceId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Task instance not found');

    const oldData = doc.data();
    if (!['OPEN', 'OVERDUE', 'REOPENED'].includes(oldData.status)) {
      throw new ValidationError(`Cannot start task in status ${oldData.status}`);
    }

    await ref.update({
      status: 'IN_PROGRESS',
      startedAt: new Date().toISOString(),
      startedBy: user.uid,
      startedByName: user.fullName,
      gpsLatitude: gpsLatitude || null,
      gpsLongitude: gpsLongitude || null,
      deviceId: deviceId || null,
      updatedAt: new Date().toISOString()
    });

    await this.#logAudit({
      action: 'TASK_STARTED', entityType: 'task_instances',
      entityId: taskInstanceId, actorId: user.uid,
      actorRole: user.role, actorName: user.fullName,
      oldValue: { status: oldData.status },
      newValue: { status: 'IN_PROGRESS' },
      details: `Started ${oldData.taskName} for Coach ${oldData.coachNo}`
    });

    return { success: true, message: 'Task started', taskInstanceId, status: 'IN_PROGRESS' };
  }

  async verifyTask(body, user) {
    const { taskInstanceId, verified, remarks, supervisorScore } = body;
    if (!taskInstanceId) throw new ValidationError('taskInstanceId required');

    const allowedRoles = ['CS', 'CTS', 'CA', 'CM'];
    if (!allowedRoles.includes(user.role)) {
      throw new ForbiddenError('Only CS/CTS/CA/CM can verify tasks');
    }

    const ref = db.collection('task_instances').doc(taskInstanceId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Task instance not found');

    const oldData = doc.data();
    const isApproved = verified !== false;
    const newStatus = isApproved ? 'VERIFIED' : 'REJECTED';

    await ref.update({
      supervisorVerified: isApproved,
      supervisorId: user.uid,
      supervisorName: user.fullName,
      supervisorRemarks: remarks || null,
      supervisorScore: supervisorScore !== undefined ? Number(supervisorScore) : null,
      verifiedAt: new Date().toISOString(),
      status: newStatus,
      updatedAt: new Date().toISOString()
    });

    await this.#logAudit({
      action: isApproved ? 'TASK_VERIFIED' : 'TASK_REJECTED',
      entityType: 'task_instances', entityId: taskInstanceId,
      actorId: user.uid, actorRole: user.role,
      actorName: user.fullName,
      oldValue: { status: oldData.status, supervisorVerified: oldData.supervisorVerified },
      newValue: { status: newStatus, supervisorVerified: isApproved, remarks },
      details: remarks || 'No remarks'
    });

    return { success: true, message: isApproved ? 'Task verified' : 'Task rejected', status: newStatus };
  }

  async closeTask(body, user) {
    const { taskInstanceId, remarks } = body;
    if (!taskInstanceId) throw new ValidationError('taskInstanceId required');

    const ref = db.collection('task_instances').doc(taskInstanceId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Task instance not found');

    const oldData = doc.data();
    if (oldData.status !== 'VERIFIED') {
      throw new ValidationError('Only VERIFIED tasks can be closed');
    }

    await ref.update({
      status: 'CLOSED',
      closedAt: new Date().toISOString(),
      closedBy: user.uid,
      closedByName: user.fullName,
      closeRemarks: remarks || null,
      updatedAt: new Date().toISOString()
    });

    await this.#logAudit({
      action: 'TASK_CLOSED', entityType: 'task_instances',
      entityId: taskInstanceId, actorId: user.uid,
      actorRole: user.role, actorName: user.fullName,
      oldValue: { status: oldData.status },
      newValue: { status: 'CLOSED' },
      details: remarks || 'Task closed'
    });

    return { success: true, message: 'Task closed', taskInstanceId, status: 'CLOSED' };
  }

  async reopenTask(body, user) {
    const { taskInstanceId, reason } = body;
    if (!taskInstanceId || !reason) throw new ValidationError('taskInstanceId and reason required');

    const ref = db.collection('task_instances').doc(taskInstanceId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Task instance not found');

    const oldData = doc.data();
    const completableStatuses = ['COMPLETED', 'VERIFIED', 'CLOSED', 'REJECTED'];
    if (!completableStatuses.includes(oldData.status)) {
      throw new ValidationError(`Cannot reopen task in status ${oldData.status}`);
    }

    await ref.update({
      status: 'REOPENED',
      reopenedAt: new Date().toISOString(),
      reopenedBy: user.uid,
      reopenedByName: user.fullName,
      reopenReason: reason,
      supervisorVerified: false,
      updatedAt: new Date().toISOString()
    });

    await this.#logAudit({
      action: 'TASK_REOPENED', entityType: 'task_instances',
      entityId: taskInstanceId, actorId: user.uid,
      actorRole: user.role, actorName: user.fullName,
      oldValue: { status: oldData.status },
      newValue: { status: 'REOPENED', reason },
      details: `Reopened: ${reason}`
    });

    return { success: true, message: 'Task reopened', taskInstanceId, status: 'REOPENED' };
  }

  async markNotApplicable(body, user) {
    const { taskInstanceId, reason } = body;
    if (!taskInstanceId || !reason) throw new ValidationError('taskInstanceId and reason required');

    const ref = db.collection('task_instances').doc(taskInstanceId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Task instance not found');

    const oldData = doc.data();
    if (!['OPEN', 'PLANNED', 'OVERDUE'].includes(oldData.status)) {
      throw new ValidationError(`Cannot mark task as N/A in status ${oldData.status}`);
    }

    await ref.update({
      status: 'NOT_APPLICABLE',
      notApplicableReason: reason,
      notApplicableMarkedBy: user.uid,
      notApplicableMarkedByName: user.fullName,
      notApplicableAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });

    await this.#logAudit({
      action: 'TASK_NA', entityType: 'task_instances',
      entityId: taskInstanceId, actorId: user.uid,
      actorRole: user.role, actorName: user.fullName,
      oldValue: { status: oldData.status },
      newValue: { status: 'NOT_APPLICABLE', reason },
      details: `Marked N/A: ${reason}`
    });

    return { success: true, message: 'Task marked not applicable', taskInstanceId, status: 'NOT_APPLICABLE' };
  }

  async markTaskNotApplicable(body, user) {
    const { taskInstanceId, reason } = body;
    await db.collection('task_instances').doc(taskInstanceId).update({
      status: 'NA', naReason: reason, markedAt: new Date().toISOString(), markedBy: user.uid
    });
    return { message: 'Task marked N/A' };
  }

  async updateTask(taskInstanceId, body, user) {
    const allowedRoles = ['CS', 'CTS', 'CA', 'CM'];
    if (!allowedRoles.includes(user.role)) {
      throw new ForbiddenError('Only CS/CTS/CA/CM can edit tasks');
    }

    const ref = db.collection('task_instances').doc(taskInstanceId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Task instance not found');

    const oldData = doc.data();
    const updates = { ...body };

    delete updates.taskId;
    delete updates.runInstanceId;
    delete updates.isParentTask;
    delete updates.parentTaskId;
    delete updates.childTaskIds;
    delete updates.createdAt;

    if (updates.workerId && updates.workerId !== oldData.workerId) {
      if (!updates.workerName) {
        try {
          const workerDoc = await db.collection('users').doc(updates.workerId).get();
          if (workerDoc.exists) {
            updates.workerName = workerDoc.data().fullName || workerDoc.data().name || 'Unknown';
          }
        } catch (_) { updates.workerName = 'Unknown'; }
      }
    }

    updates.updatedAt = new Date().toISOString();
    updates.editedBy = user.uid;
    updates.editedByName = user.fullName;
    updates.editedAt = updates.updatedAt;

    await ref.update(updates);

    if (oldData.isParentTask && (updates.workerId || updates.workerName || updates.workerRole)) {
      const children = oldData.childTaskIds || [];
      const childBatch = db.batch();
      for (const cId of children) {
        const childRef = db.collection('task_instances').doc(cId);
        childBatch.update(childRef, {
          ...(updates.workerId && { workerId: updates.workerId }),
          ...(updates.workerName && { workerName: updates.workerName }),
          ...(updates.workerRole && { workerRole: updates.workerRole }),
          ...(updates.scheduledTime && { scheduledTime: updates.scheduledTime }),
          ...(updates.coachNo && { coachNo: updates.coachNo }),
          updatedAt: new Date().toISOString()
        });
      }
      await childBatch.commit();
    }

    await this.#logAudit({
      action: 'TASK_EDITED', entityType: 'task_instances',
      entityId: taskInstanceId, actorId: user.uid,
      actorRole: user.role, actorName: user.fullName,
      oldValue: oldData, newValue: { ...oldData, ...updates },
      details: `Supervisor ${user.fullName} edited task ${taskInstanceId}`
    });

    return { success: true, message: 'Task updated', taskInstanceId };
  }

  async editTask(taskInstanceId, body, user) {
    return this.updateTask(taskInstanceId, body, user);
  }

  async createEscalation(body, user) {
    const { sourceEntity, sourceId, reason, escalatedToRole, details } = body;
    if (!sourceEntity || !sourceId || !reason) {
      throw new ValidationError('sourceEntity, sourceId, reason required');
    }

    const ref = db.collection('escalations').doc();
    const escalation = {
      escalationId: ref.id,
      sourceEntity, sourceId,
      reason, details: details || '',
      escalatedBy: user.uid, escalatedByName: user.fullName,
      escalatedByRole: user.role,
      escalatedToRole: escalatedToRole || this.#getNextEscalationRole(user.role),
      status: 'OPEN',
      resolvedAt: null, resolvedBy: null, resolution: null,
      createdAt: new Date().toISOString(), updatedAt: new Date().toISOString()
    };
    await ref.set(escalation);

    if (sourceEntity === 'task_instance') {
      try {
        const srcDoc = await db.collection('task_instances').doc(sourceId).get();
        if (srcDoc.exists) {
          await srcDoc.ref.update({
            status: 'ESCALATED',
            escalationId: ref.id,
            updatedAt: new Date().toISOString()
          });
        }
      } catch (_) {}
    }

    await this.#logAudit({
      action: 'ESCALATION_CREATED', entityType: 'escalations',
      entityId: ref.id, actorId: user.uid,
      actorRole: user.role, actorName: user.fullName,
      newValue: escalation, details: `Escalated ${sourceEntity}:${sourceId} - ${reason}`
    });

    return { success: true, message: 'Escalation created', escalationId: ref.id };
  }

  #getNextEscalationRole(currentRole) {
    const chain = ['janitor', 'CS', 'CTS', 'CA', 'CM'];
    const idx = chain.indexOf(currentRole);
    if (idx === -1 || idx >= chain.length - 1) return 'CM';
    return chain[idx + 1];
  }

  async resolveEscalation(escalationId, body, user) {
    const { resolution } = body;
    const ref = db.collection('escalations').doc(escalationId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Escalation not found');

    const oldData = doc.data();
    await ref.update({
      status: 'RESOLVED',
      resolvedBy: user.uid,
      resolvedByName: user.fullName,
      resolution: resolution || 'Resolved',
      resolvedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });

    await this.#logAudit({
      action: 'ESCALATION_RESOLVED', entityType: 'escalations',
      entityId: escalationId, actorId: user.uid,
      actorRole: user.role, actorName: user.fullName,
      oldValue: { status: oldData.status },
      newValue: { status: 'RESOLVED', resolution },
      details: resolution || 'Resolved'
    });

    return { success: true, message: 'Escalation resolved' };
  }

  async listEscalations(query = {}) {
    const { status: filterStatus, sourceEntity } = query;
    let firestoreQuery = db.collection('escalations');
    if (filterStatus) firestoreQuery = firestoreQuery.where('status', '==', filterStatus);
    if (sourceEntity) firestoreQuery = firestoreQuery.where('sourceEntity', '==', sourceEntity);
    const snapshot = await firestoreQuery.orderBy('createdAt', 'desc').limit(200).get();
    const list = [];
    snapshot.forEach(doc => list.push(doc.data()));
    return { success: true, count: list.length, escalations: list };
  }

  async getEscalations(queryParams) {
    const { status } = queryParams;
    let query = db.collection('v2_escalations');
    if (status) query = query.where('status', '==', status);
    const snapshot = await query.orderBy('createdAt', 'desc').limit(200).get();
    const escalations = [];
    snapshot.forEach(doc => escalations.push(doc.data()));
    return { count: escalations.length, escalations };
  }

  async getAuditLogs(query = {}) {
    const { entityType, entityId, action, limit: qLimit } = query;
    let firestoreQuery = db.collection('audit_logs');
    if (entityType) firestoreQuery = firestoreQuery.where('entityType', '==', entityType);
    if (entityId) firestoreQuery = firestoreQuery.where('entityId', '==', entityId);
    if (action) firestoreQuery = firestoreQuery.where('action', '==', action);
    const snapshot = await firestoreQuery.orderBy('timestamp', 'desc').limit(parseInt(qLimit) || 100).get();
    const logs = [];
    snapshot.forEach(doc => logs.push(doc.data()));
    return { success: true, count: logs.length, logs };
  }

  async getClosureTasks(runInstanceId) {
    const snapshot = await db.collection('closure_tasks')
      .where('runInstanceId', '==', runInstanceId)
      .limit(200).get();
    const tasks = [];
    snapshot.forEach(doc => tasks.push(doc.data()));
    return { success: true, count: tasks.length, tasks };
  }

  async completeClosureTask(body, user) {
    const { taskId, beforePhoto, afterPhoto, gpsLatitude, gpsLongitude } = body;
    if (!taskId) throw new ValidationError('taskId required');

    const ref = db.collection('closure_tasks').doc(taskId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Closure task not found');

    await ref.update({
      status: 'COMPLETED',
      beforePhoto: beforePhoto || null,
      afterPhoto: afterPhoto || null,
      gpsLatitude: gpsLatitude || null,
      gpsLongitude: gpsLongitude || null,
      completedAt: new Date().toISOString()
    });

    return { success: true, message: 'Closure task completed', taskId };
  }

  async completeClosureTasks(body, user) {
    const { runInstanceId } = body;
    const snapshot = await db.collection('task_instances')
      .where('runInstanceId', '==', runInstanceId)
      .where('category', '==', 'closure')
      .where('status', 'in', ['OPEN', 'IN_PROGRESS']).limit(200).get();
    const batch = db.batch();
    snapshot.forEach(doc => batch.update(doc.ref, {
      status: 'COMPLETED', completedAt: new Date().toISOString(), completedBy: user.uid
    }));
    await batch.commit();
    return { message: `Completed ${snapshot.size} closure tasks` };
  }

  async getWorkerMyTasks(workerId, query = {}, user = {}) {
    const { status: filterStatus, runInstanceId } = query;

    let myRun = null;
    let myCoaches = [];
    let myCoachTasks = null;

    const applyRun = (doc) => {
      const d = doc.data();
      const assigned = (d.coaches || []).filter(c =>
        c.workerId === workerId || c.janitorId === workerId || c.attendantId === workerId);
      if (assigned.length === 0) return false;
      myRun = { ...d, runInstanceId: doc.id };
      myCoaches = assigned.map(c => c.coachPosition || c.coachNo);
      myCoachTasks = assigned.reduce((acc, c) => {
        const cn = c.coachPosition || c.coachNo;
        if (c.tasks && c.tasks.length > 0) acc[cn] = c.tasks.map(t => t.toLowerCase());
        return acc;
      }, {});
      return true;
    };

    if (runInstanceId) {
      // The app resolves the worker's run first; honour that run instead of
      // silently showing tasks from a different active run.
      const doc = await db.collection('RunInstance').doc(runInstanceId).get();
      if (doc.exists) applyRun(doc);
    } else {
      const runsSnap = await db.collection('RunInstance')
        .where('status', '==', 'Active')
        .limit(200).get();

      // A worker can have more than one active run; pick the most recent one
      // instead of whichever document Firestore happens to return last.
      const matches = [];
      runsSnap.forEach(doc => {
        const d = doc.data();
        const assigned = (d.coaches || []).some(c =>
          c.workerId === workerId || c.janitorId === workerId || c.attendantId === workerId);
        if (assigned) matches.push(doc);
      });
      matches.sort((a, b) => {
        const aData = a.data();
        const bData = b.data();
        const aKey = aData.scheduledDeparture || aData.departureDate || aData.createdAt || '';
        const bKey = bData.scheduledDeparture || bData.departureDate || bData.createdAt || '';
        return String(bKey).localeCompare(String(aKey));
      });
      if (matches.length > 0) applyRun(matches[0]);
    }

    if (!myRun) {
      return { success: false, error: 'No active journey found for this worker' };
    }

    let taskQuery = db.collection('task_instances')
      .where('runInstanceId', '==', myRun.runInstanceId)
      .where('isParentTask', '==', false);

    const janitorCoaches = myRun.coaches
      .filter(c => c.workerId === workerId || c.janitorId === workerId)
      .map(c => c.coachPosition || c.coachNo);
    const attendantCoaches = myRun.coaches.filter(c => c.attendantId === workerId).map(c => c.coachPosition || c.coachNo);
    const assignedCoachNos = [...new Set([...janitorCoaches, ...attendantCoaches])];

    const taskSnap = await taskQuery.limit(3000).get();
    let tasks = [];
    taskSnap.forEach(doc => tasks.push(doc.data()));

    tasks = tasks.filter(t => assignedCoachNos.includes(t.coachNo));

    const role = String(user.role || '').toUpperCase().replace(/\s+/g, '_');
    const workerType = String(user.workerType || user.worker_type || '').toUpperCase();
    const isAttendant = role === 'ATTENDANT' || workerType === 'ATTENDANT';
    const isJanitor = role === 'JANITOR' || workerType === 'JANITOR';
    const attendantTaskTypes = new Set(['LINEN_CHANGE', 'BERTH_INSPECTION']);
    tasks = tasks.filter(task => {
      const assignedWorkerId = task.workerId || task.assignedTo;
      if (assignedWorkerId !== workerId) return false;

      const taskType = String(task.taskType || '').toUpperCase();
      const taskWorkerType = String(task.workerType || '').toUpperCase();
      const isAttendantTask =
        taskWorkerType === 'ATTENDANT' ||
        attendantTaskTypes.has(taskType) ||
        taskType.includes('LINEN') ||
        taskType.includes('BERTH');

      if (isAttendant) return isAttendantTask;
      if (isJanitor) return !isAttendantTask;
      return true;
    });

    if (myCoachTasks) {
      tasks = tasks.filter(t => {
        const allowed = myCoachTasks[t.coachNo];
        if (!allowed) return true;
        const taskName = (t.taskName || t.taskMasterCode || '').toLowerCase();
        return allowed.some(keyword => taskName.includes(keyword));
      });
    }

    if (filterStatus) tasks = tasks.filter(t => t.status === filterStatus);

    const baseDate = myRun.actualDeparture || myRun.scheduledDeparture || new Date().toISOString();
    const dateStr = baseDate.split('T')[0];
    
    tasks = tasks.map(t => {
      let dueTime = null;
      if (t.scheduledTime && t.scheduledTime.includes(':')) {
        dueTime = `${dateStr}T${t.scheduledTime}:00.000Z`;
      }
      return { ...t, dueTime };
    });

    return {
      success: true,
      journey: {
        runInstanceId: myRun.runInstanceId,
        trainNo: myRun.trainNo, trainName: myRun.trainName,
        coaches: myCoaches,
        actualDeparture: myRun.actualDeparture,
        scheduledArrival: myRun.scheduledArrival
      },
      taskCount: tasks.length,
      tasks
    };
  }

  async getJourneyTimeline(runInstanceId) {
    const runDoc = await db.collection('RunInstance').doc(runInstanceId).get();
    if (!runDoc.exists) throw new NotFoundError('Journey not found');

    const run = runDoc.data();
    const actualDeparture = run.actualDeparture ? new Date(run.actualDeparture) : null;
    const scheduledDeparture = run.scheduledDeparture ? new Date(run.scheduledDeparture) : null;
    const delayMs = actualDeparture && scheduledDeparture
      ? actualDeparture.getTime() - scheduledDeparture.getTime()
      : 0;
    const delayMinutes = Math.round(delayMs / 60000);

    const taskSnap = await db.collection('task_instances')
      .where('runInstanceId', '==', runInstanceId)
      .where('isParentTask', '==', true)
      .limit(200).get();

    const tasks = [];
    taskSnap.forEach(doc => tasks.push(doc.data()));

    const adjustedTasks = tasks.map(t => {
      if (delayMinutes > 0 && t.scheduledTime) {
        const [h, m] = t.scheduledTime.split(':').map(Number);
        const totalMin = h * 60 + m + delayMinutes;
        const newH = Math.floor(totalMin / 60) % 24;
        const newM = totalMin % 60;
        return { ...t, originalScheduledTime: t.scheduledTime, adjustedTime: `${String(newH).padStart(2, '0')}:${String(newM).padStart(2, '0')}` };
      }
      return { ...t, adjustedTime: t.scheduledTime };
    });

    return {
      success: true,
      journey: {
        runInstanceId, trainNo: run.trainNo, trainName: run.trainName,
        scheduledDeparture: run.scheduledDeparture,
        actualDeparture: run.actualDeparture,
        scheduledArrival: run.scheduledArrival,
        actualArrival: run.actualArrival,
        delayMinutes,
        status: run.status
      },
      taskCount: adjustedTasks.length,
      tasks: adjustedTasks
    };
  }

  async submitPassengerFeedback(body) {
    const { passengerName, mobileNumber, coachNo, ratings, remarks, runInstanceId } = body;
    if (!runInstanceId || !coachNo || !ratings) throw new ValidationError('Required fields missing.');
    const { cleanliness, toiletHygiene, linenQuality, security, staffBehaviour } = ratings;
    if (cleanliness === undefined || toiletHygiene === undefined || linenQuality === undefined || security === undefined || staffBehaviour === undefined) {
      throw new ValidationError('All 5 rating parameters required.');
    }
    const runDoc = await db.collection('RunInstance').doc(runInstanceId).get();
    if (!runDoc.exists) throw new NotFoundError('Journey not found.');
    const runData = runDoc.data();
    const totalStars = Number(cleanliness) + Number(toiletHygiene) + Number(linenQuality) + Number(security) + Number(staffBehaviour);
    const overallRating = parseFloat((totalStars / 5).toFixed(2));
    const feedbackRef = db.collection('obhs_feedbacks').doc();
    await feedbackRef.set({
      feedbackId: feedbackRef.id, feedbackType: 'QR_PASSENGER', runInstanceId,
      trainNo: runData.trainNo || 'UNKNOWN', trainName: runData.trainName || '',
      coachNo, passengerName: passengerName || 'Anonymous', mobileNumber: mobileNumber || 'N/A',
      remarks: remarks || '', ratings, overallRating, source: 'QR_CODE',
      createdAt: new Date().toISOString()
    });
    return { success: true, message: 'Thank you for your feedback!', overallRating };
  }

  // ─── Generic list/get delegates ────────────────────────────────────────

  async listRunInstances(user, query) {
    const collection = 'RunInstance';
    let q = db.collection(collection);
    if (query.division) q = q.where('division', '==', query.division);
    if (query.status) q = q.where('status', '==', query.status);
    if (query.trainNo) q = q.where('trainNo', '==', query.trainNo);
    q = q.orderBy('createdAt', 'desc').limit(50);
    const snapshot = await q.get();
    const data = [];
    snapshot.forEach(doc => data.push({ id: doc.id, ...doc.data() }));
    return { success: true, count: data.length, data };
  }

  async getRunInstance(runInstanceId) {
    const snapshot = await db.collection('RunInstance').doc(runInstanceId).get();
    if (!snapshot.exists) throw new NotFoundError('RunInstance not found');
    return { success: true, data: { id: snapshot.id, ...snapshot.data() } };
  }

  async listCoachForms(user, query) {
    const snapshot = await db.collection('coachForms').orderBy('createdAt', 'desc').limit(50).get();
    const data = [];
    snapshot.forEach(doc => data.push({ id: doc.id, ...doc.data() }));
    return { success: true, count: data.length, data };
  }

  async getCoachForm(formId) {
    const snapshot = await db.collection('coachForms').doc(formId).get();
    if (!snapshot.exists) throw new NotFoundError('Coach form not found');
    return { success: true, data: { id: snapshot.id, ...snapshot.data() } };
  }

  async listPremisesForms(user, query) {
    const snapshot = await db.collection('premisesForms').orderBy('createdAt', 'desc').limit(50).get();
    const data = [];
    snapshot.forEach(doc => data.push({ id: doc.id, ...doc.data() }));
    return { success: true, count: data.length, data };
  }

  async getPremisesForm(formId) {
    const snapshot = await db.collection('premisesForms').doc(formId).get();
    if (!snapshot.exists) throw new NotFoundError('Premises form not found');
    return { success: true, data: { id: snapshot.id, ...snapshot.data() } };
  }

  async listCtsForms(user, query) {
    const snapshot = await db.collection('ctsForms').orderBy('createdAt', 'desc').limit(50).get();
    const data = [];
    snapshot.forEach(doc => data.push({ id: doc.id, ...doc.data() }));
    return { success: true, count: data.length, data };
  }

  async getCtsForm(formId) {
    const snapshot = await db.collection('ctsForms').doc(formId).get();
    if (!snapshot.exists) throw new NotFoundError('CTS form not found');
    return { success: true, data: { id: snapshot.id, ...snapshot.data() } };
  }

  async listCleaningForms(user, query) {
    const snapshot = await db.collection('cleaningForms').orderBy('createdAt', 'desc').limit(50).get();
    const data = [];
    snapshot.forEach(doc => data.push({ id: doc.id, ...doc.data() }));
    return { success: true, count: data.length, data };
  }

  async getCleaningForm(uid) {
    const snapshot = await db.collection('cleaningForms').doc(uid).get();
    if (!snapshot.exists) throw new NotFoundError('Cleaning form not found');
    return { success: true, data: { id: snapshot.id, ...snapshot.data() } };
  }

  async listTasks(user, query) {
    const { taskService } = await import('./taskService.js');
    return taskService.getTasksForRun(user, query.runInstanceId, query);
  }

  async getTask(taskId) {
    const snapshot = await db.collection('task_instances').doc(taskId).get();
    if (!snapshot.exists) throw new NotFoundError('Task not found');
    return { success: true, data: { id: snapshot.id, ...snapshot.data() } };
  }

  async listOBHS(user, query) {
    const snapshot = await db.collection('obhs_complaints').orderBy('createdAt', 'desc').limit(50).get();
    const data = [];
    snapshot.forEach(doc => data.push({ id: doc.id, ...doc.data() }));
    return { success: true, count: data.length, data };
  }

  async getOBHS(obhsId) {
    const snapshot = await db.collection('obhs_complaints').doc(obhsId).get();
    if (!snapshot.exists) throw new NotFoundError('OBHS record not found');
    return { success: true, data: { id: snapshot.id, ...snapshot.data() } };
  }
}

export const v2Service = new V2Service();
