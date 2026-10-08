import { db, admin } from '../database/index.js';
import logger from '../logger/index.js';
import { NotFoundError, ValidationError, ForbiddenError, FirestoreError } from '../errors/index.js';

class ObhsService {
  async markAttendance(userData, body) {
    const allowedFields = ['runInstanceId', 'attendanceType', 'imageUrl', 'latitude', 'longitude', 'deviceTimestamp', 'mobileNumber', 'deviceId', 'livenessChallenge'];
    for (const key of Object.keys(body)) {
      if (!allowedFields.includes(key)) throw new ValidationError(`Invalid field: '${key}'`);
    }
    const { runInstanceId, attendanceType, imageUrl, latitude, longitude, deviceTimestamp, mobileNumber, deviceId, livenessChallenge } = body;
    if (!runInstanceId || !attendanceType || !imageUrl || !deviceTimestamp) {
      throw new ValidationError('runInstanceId, attendanceType, imageUrl, and deviceTimestamp are required.');
    }
    if (!['start', 'mid', 'end'].includes(attendanceType)) {
      throw new ValidationError("attendanceType must be 'start', 'mid', or 'end'");
    }
    const { uid: workerId, fullName: workerName } = userData;
    const finalWorkerName = workerName || 'Unknown Worker';
    let isLateAttendance = false;
    let lateByMinutes = 0;
    let firstAttendanceTime = null;

    if (livenessChallenge) {
      try {
        const { verifyFaceLiveness } = await import('./rekognitionService.js');
        const livenessResult = await verifyFaceLiveness(imageUrl, livenessChallenge);
        if (!livenessResult.matched && !livenessResult.error) {
          // Deliberate mismatch — gesture was wrong
          throw new ValidationError(`Liveness Verification Failed: ${livenessResult.reason}`);
        } else if (livenessResult.error) {
          // AWS/network error — log and allow attendance, do not block worker
          logger.error('OBHS', '(Liveness Check) AWS error, allowing attendance:', livenessResult.reason);
        }
      } catch (livenessErr) {
        if (livenessErr instanceof ValidationError) throw livenessErr;
        // Module import or unexpected error — log and continue
        logger.error('OBHS', '(Liveness Check) Unexpected error:', livenessErr.message);
      }
    }

    try {
      if (runInstanceId && attendanceType === 'start') {
        const runSnap = await db.collection('RunInstance').doc(runInstanceId).get();
        if (runSnap.exists) {
          const runData = runSnap.data();
          firstAttendanceTime = runData.first_attendance_time;
          const currentTimestamp = new Date(deviceTimestamp || new Date().toISOString());
          if (!firstAttendanceTime) {
            firstAttendanceTime = currentTimestamp.toISOString();
            await db.collection('RunInstance').doc(runInstanceId).update({ first_attendance_time: firstAttendanceTime, updatedAt: new Date().toISOString() });
          } else {
            let firstTimeMs = 0;
            if (firstAttendanceTime && typeof firstAttendanceTime.toDate === 'function') {
              firstTimeMs = firstAttendanceTime.toDate().getTime();
            } else {
              firstTimeMs = new Date(firstAttendanceTime).getTime();
            }
            if (!isNaN(firstTimeMs)) {
              const diffMs = currentTimestamp.getTime() - firstTimeMs;
              const diffMins = Math.floor(diffMs / 60000);
              if (diffMins > 15) { isLateAttendance = true; lateByMinutes = diffMins - 15; }
            }
          }
        }
      }
    } catch (winErr) { logger.error('OBHS', '(Attendance Timing Engine) Error:', winErr); }

    const getISTDateString = (date) => {
      if (!date || isNaN(date.getTime())) return null;
      const ist = new Date(date.getTime() + 5.5 * 60 * 60 * 1000);
      return ist.toISOString().split('T')[0];
    };
    const todayIST = getISTDateString(new Date());

    // Use the deterministic doc ID (runInstanceId_workerId) as the primary lookup.
    // This avoids a full collection scan that can hit Firestore limits or index issues.
    let attendanceDocId = `${runInstanceId}_${workerId}`;
    let attendanceRef = db.collection('obhs_attendance').doc(attendanceDocId);
    let attendanceDoc;
    try {
      attendanceDoc = await attendanceRef.get();
    } catch (dbErr) {
      logger.error('OBHS', '(Attendance Doc Fetch) Firestore error:', dbErr.message);
      throw new FirestoreError(`Failed to fetch attendance record: ${dbErr.message}`);
    }

    // Fallback: if the deterministic doc doesn't exist, scan for a today's record
    // (handles legacy docs that may have been created with a different ID scheme)
    if (!attendanceDoc.exists) {
      try {
        const snapshot = await db.collection('obhs_attendance')
          .where('workerId', '==', workerId)
          .where('runInstanceId', '==', runInstanceId)
          .limit(5)
          .get();
        let latestDoc = null;
        let latestTime = 0;
        snapshot.forEach(doc => {
          const data = doc.data();
          let time = 0;
          if (data.createdAt) {
            if (typeof data.createdAt.toDate === 'function') {
              time = data.createdAt.toDate().getTime();
            } else {
              time = new Date(data.createdAt).getTime();
            }
          }
          if (!isNaN(time) && time > latestTime) {
            latestTime = time;
            latestDoc = doc;
          }
        });
        if (latestDoc) {
          let latestCreatedAt = latestDoc.data().createdAt;
          if (latestCreatedAt && typeof latestCreatedAt.toDate === 'function') {
            latestCreatedAt = latestCreatedAt.toDate();
          } else if (latestCreatedAt) {
            latestCreatedAt = new Date(latestCreatedAt);
          }
          if (getISTDateString(latestCreatedAt) === todayIST) {
            attendanceDoc = latestDoc;
            attendanceDocId = latestDoc.id;
            attendanceRef = db.collection('obhs_attendance').doc(attendanceDocId);
          }
        }
      } catch (scanErr) {
        logger.error('OBHS', '(Attendance fallback scan) Error:', scanErr.message);
        // Non-fatal: proceed with the deterministic doc (it doesn't exist, so we'll create it)
      }
    }
    const attendanceEntry = {
      photoUrl: imageUrl, deviceTimestamp, serverTimestamp: new Date().toISOString(),
      location: (latitude && longitude) ? { latitude, longitude } : null,
      mobileNumber: mobileNumber || null, deviceId: deviceId || null,
      isLate: isLateAttendance, lateByMinutes,
      firstAttendanceReference: firstAttendanceTime,
      status: isLateAttendance ? 'LATE' : 'PRESENT'
    };

    if (!attendanceDoc.exists) {
      if (attendanceType !== 'start') throw new ValidationError("You must submit 'start' attendance first.");
      try {
        await attendanceRef.set({
          uid: attendanceDocId, runInstanceId, workerId, workerName: finalWorkerName,
          mobileNumber: mobileNumber || null, deviceId: deviceId || null,
          isStartMarked: true, isMidMarked: false, isEndMarked: false,
          attendanceStatus: isLateAttendance ? 'LATE' : 'PRESENT',
          lateByMinutes, firstAttendanceReference: firstAttendanceTime,
          identityAuditStatus: 'PENDING_VERIFICATION',
          startAttendance: attendanceEntry, midAttendance: null, endAttendance: null,
          createdAt: new Date().toISOString(), updatedAt: new Date().toISOString()
        });
      } catch (dbErr) {
        logger.error('OBHS', '(Attendance Set) Firestore error:', dbErr.message);
        throw new FirestoreError(`Failed to save attendance record: ${dbErr.message}`);
      }
      try {
        if (runInstanceId && attendanceType === 'start') {
          const runSnap2 = await db.collection('RunInstance').doc(runInstanceId).get();
          if (runSnap2.exists && runSnap2.data().status === 'ALLOCATED') {
            const runData2 = runSnap2.data();
            const totalWorkers = (runData2.coaches || []).filter(c => c.workerId).length;
            const attendSnap = await db.collection('obhs_attendance')
              .where('runInstanceId', '==', runInstanceId)
              .where('isStartMarked', '==', true).limit(200).get();
            if (attendSnap.size >= totalWorkers && totalWorkers > 0) {
              await db.collection('RunInstance').doc(runInstanceId).update({ status: 'READY', updatedAt: new Date().toISOString() });
            }
          }
        }
      } catch (readyErr) { logger.error('OBHS', '(Attendance->READY) Error:', readyErr.message); }
    } else {
      const currentData = attendanceDoc.data();
      const updateData = { updatedAt: new Date().toISOString() };
      if (attendanceType === 'start') throw new ValidationError('Start attendance already submitted.');
      const baseStartPhoto = currentData.startAttendance?.photoUrl;
      if (!baseStartPhoto) throw new ValidationError('Baseline image missing from DB.');

      let faceVerification = { matched: true, similarity: 100, reason: 'Skipped (AWS unavailable)' };
      try {
        const { compareFaces } = await import('./rekognitionService.js');
        faceVerification = await compareFaces(baseStartPhoto, imageUrl);
      } catch (importErr) {
        logger.error('OBHS', '(compareFaces import) Error:', importErr.message);
        // If rekognition module fails to load, allow attendance but flag for review
        faceVerification = { matched: true, similarity: 0, reason: 'Rekognition unavailable - flagged for manual review', error: true };
      }

      if (!faceVerification.matched && !faceVerification.error) {
        await attendanceRef.update({
          identityAuditStatus: 'MISMATCH_ALERT',
          lastMismatchReason: faceVerification.reason,
          lastMismatchSimilarity: faceVerification.similarity,
          lastMismatchAt: new Date().toISOString(),
          updatedAt: new Date().toISOString()
        });
        throw new ValidationError(
          `Identity Verification Failed. Face match score (${faceVerification.similarity}%) below threshold. ${faceVerification.reason}`
        );
      } else if (faceVerification.error) {
        // AWS error: log it but allow attendance - flag for manual audit
        logger.error('OBHS', '(Face Comparison) AWS error - allowing with flag:', faceVerification.reason);
        await attendanceRef.update({
          identityAuditStatus: 'MANUAL_REVIEW_REQUIRED',
          lastMismatchReason: faceVerification.reason,
          updatedAt: new Date().toISOString()
        }).catch(e => logger.error('OBHS', 'Could not update audit status', e.message));
      }

      if (attendanceType === 'mid') {
        if (currentData.midAttendance) throw new ValidationError('Mid attendance already submitted.');
        updateData.midAttendance = attendanceEntry;
        updateData.isMidMarked = true;
        updateData.identityAuditStatus = 'MID_VERIFIED';
      }
      if (attendanceType === 'end') {
        if (currentData.endAttendance) throw new ValidationError('End attendance already submitted.');
        updateData.endAttendance = attendanceEntry;
        updateData.isEndMarked = true;
        updateData.identityAuditStatus = 'VERIFIED_SUCCESS';
      }
      updateData.attendanceStatus = isLateAttendance ? 'LATE' : 'PRESENT';
      updateData.timingSnapshot = {
        isLate: isLateAttendance, lateByMinutes,
        firstAttendanceReference: firstAttendanceTime,
        recordedAt: new Date().toISOString()
      };
      try {
        await attendanceRef.update(updateData);
      } catch (dbErr) {
        logger.error('OBHS', '(Attendance Update) Firestore error:', dbErr.message);
        throw new FirestoreError(`Failed to update attendance record: ${dbErr.message}`);
      }
    }
    return { success: true, message: `${attendanceType.toUpperCase()} attendance processed successfully.`, uid: attendanceDocId, isLate: isLateAttendance };
  }

  async getAttendance(filters = {}) {
    const { runInstanceId, callerId, role } = filters;
    let query = db.collection('obhs_attendance');
    if (runInstanceId) query = query.where('runInstanceId', '==', runInstanceId);
    const snapshot = await query.limit(200).get();
    let records = [];
    snapshot.forEach(doc => records.push({ id: doc.id, ...doc.data() }));
    const roleUpper = (role || '').toUpperCase();
    if (roleUpper === 'WORKER' || roleUpper === 'RAILWAY WORKER') records = records.filter(r => r.workerId === callerId);
    records.sort((a, b) => ((b.updatedAt || '') > (a.updatedAt || '') ? 1 : -1));
    return { count: records.length, records };
  }

  async getAttendanceStatus(runInstanceId, workerId) {
    if (!workerId) {
      throw new ValidationError('workerId is required.');
    }

    const getISTDateString = (date) => {
      if (!date || isNaN(date.getTime())) return null;
      const ist = new Date(date.getTime() + 5.5 * 60 * 60 * 1000);
      return ist.toISOString().split('T')[0];
    };
    const todayIST = getISTDateString(new Date());

    // Primary: look up deterministic doc ID
    const resolveDate = (createdAt) => {
      if (!createdAt) return null;
      if (typeof createdAt.toDate === 'function') return createdAt.toDate();
      return new Date(createdAt);
    };

    // Try the deterministic doc ID first (fast, no index required)
    if (runInstanceId) {
      try {
        const docId = `${runInstanceId}_${workerId}`;
        const directDoc = await db.collection('obhs_attendance').doc(docId).get();
        if (directDoc.exists) {
          const data = directDoc.data();
          const docDate = getISTDateString(resolveDate(data.createdAt));
          if (docDate === todayIST) {
            return {
              exists: true,
              isStartMarked: data.isStartMarked || false,
              isMidMarked: data.isMidMarked || false,
              isEndMarked: data.isEndMarked || false,
              identityAuditStatus: data.identityAuditStatus || null,
              attendanceStatus: data.attendanceStatus || null,
              startAttendance: data.startAttendance || null,
              midAttendance: data.midAttendance || null,
              endAttendance: data.endAttendance || null,
              uid: data.uid,
              runInstanceId: data.runInstanceId
            };
          }
        }
      } catch (directErr) {
        logger.error('OBHS', '(getAttendanceStatus direct lookup) Error:', directErr.message);
        // Fall through to fallback scan
      }
    }

    // Fallback: scan by workerId + runInstanceId (handles legacy doc IDs)
    try {
      let query = db.collection('obhs_attendance').where('workerId', '==', workerId);
      if (runInstanceId) query = query.where('runInstanceId', '==', runInstanceId);
      const snapshot = await query.limit(10).get();
      let latestData = null;
      let latestTime = 0;
      snapshot.forEach(doc => {
        const data = doc.data();
        const dateObj = resolveDate(data.createdAt);
        const time = dateObj ? dateObj.getTime() : 0;
        if (!isNaN(time) && time > latestTime) {
          latestTime = time;
          latestData = data;
        }
      });

      if (!latestData || getISTDateString(resolveDate(latestData.createdAt)) !== todayIST) {
        return { exists: false, isStartMarked: false, isMidMarked: false, isEndMarked: false, identityAuditStatus: null };
      }
      return {
        exists: true,
        isStartMarked: latestData.isStartMarked || false,
        isMidMarked: latestData.isMidMarked || false,
        isEndMarked: latestData.isEndMarked || false,
        identityAuditStatus: latestData.identityAuditStatus || null,
        attendanceStatus: latestData.attendanceStatus || null,
        startAttendance: latestData.startAttendance || null,
        midAttendance: latestData.midAttendance || null,
        endAttendance: latestData.endAttendance || null,
        uid: latestData.uid,
        runInstanceId: latestData.runInstanceId
      };
    } catch (scanErr) {
      logger.error('OBHS', '(getAttendanceStatus scan) Error:', scanErr.message);
      return { exists: false, isStartMarked: false, isMidMarked: false, isEndMarked: false, identityAuditStatus: null };
    }
  }

  async getAttendanceExceptions(filters = {}) {
    const { status } = filters;
    let query = db.collection('attendance_exceptions');
    if (status) query = query.where('status', '==', status);
    const snapshot = await query.limit(200).get();
    const exceptions = [];
    snapshot.forEach(doc => exceptions.push(doc.data()));
    exceptions.sort((a, b) => ((b.createdAt || '') > (a.createdAt || '') ? 1 : -1));
    return { success: true, count: exceptions.length, exceptions };
  }

  async takeActionOnException(body) {
    const { exceptionId, action, adminRemark } = body;
    if (!exceptionId || !action) throw new ValidationError('exceptionId and action are required.');
    const validActions = ['APPROVED', 'REJECTED'];
    if (!validActions.includes(action)) throw new ValidationError('Action must be APPROVED or REJECTED.');
    const ref = db.collection('attendance_exceptions').doc(exceptionId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Attendance exception not found.');
    await ref.update({
      status: action,
      adminRemark: adminRemark || '',
      actionTakenAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });
    return { success: true, message: `Exception ${action} successfully` };
  }

  async reportAttendanceIssue(userData, body) {
    const { runInstanceId, issueType, remark, photoUrl, latitude, longitude, attendanceType } = body;
    if (!runInstanceId || !issueType) {
      throw new ValidationError('runInstanceId and issueType are required.');
    }
    const workerId = userData.uid;
    const workerName = userData.fullName || 'Unknown';
    const issueRef = db.collection('attendance_exceptions').doc();
    await issueRef.set({
      exceptionId: issueRef.id,
      runInstanceId,
      workerId,
      workerName,
      issueType,
      remark: remark || '',
      photoUrl: photoUrl || null,
      location: (latitude && longitude) ? { latitude, longitude } : null,
      attendanceType: attendanceType || null,
      status: 'PENDING',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });
    return { success: true, message: 'Attendance issue reported.', exceptionId: issueRef.id };
  }

  async submitComplaint(userData, body) {
    const { runInstanceId: bodyRunInstanceId, coachNo, category, description, photoUrl } = body;
    if (!coachNo || !category || !description) {
      throw new ValidationError('Coach number, category, and description are required.');
    }
    if (!userData || !userData.uid) throw new ForbiddenError('Unauthorized.');
    const workerId = userData.uid;
    const workerName = userData.fullName || 'Unknown';
    let runInstanceId = bodyRunInstanceId || userData.activeRunInstanceId;
    if (!runInstanceId) throw new ValidationError('No active run instance found.');
    const runDoc = await db.collection('RunInstance').doc(runInstanceId).get();
    if (!runDoc.exists) throw new NotFoundError('RunInstance not found.');
    const runData = runDoc.data();
    const complaintsRef = db.collection('obhs_complaints').doc();
    await complaintsRef.set({
      complaintId: complaintsRef.id, runInstanceId,
      trainNo: runData.trainNo || 'N/A', trainName: runData.trainName || 'N/A',
      coachNo, category, description, photoUrl: photoUrl || null,
      status: 'OPEN', date: new Date().toISOString().split('T')[0],
      createdAt: new Date().toISOString(),
      submittedBy: { uid: workerId, name: workerName, role: userData.role || 'Railway Worker' },
      assignedToSupervisor: runData.supervisorId || runData.contractorSupervisorId || null
    });
    return { success: true, message: 'Complaint registered successfully', complaintId: complaintsRef.id };
  }

  async getComplaints(filters = {}) {
    const { status, runInstanceId } = filters;
    let query = db.collection('obhs_complaints');
    if (status) query = query.where('status', '==', status);
    if (runInstanceId) query = query.where('runInstanceId', '==', runInstanceId);
    const snapshot = await query.orderBy('createdAt', 'desc').limit(200).get();
    const complaints = [];
    snapshot.forEach(doc => complaints.push(doc.data()));
    return { count: complaints.length, complaints };
  }

  async submitFeedback(userData, body) {
    const { feedbackType, runInstanceId, coachNo, ratings, remarks, passengerName, mobileNumber, inspectorName } = body;
    if (!runInstanceId || !coachNo || !ratings) throw new ValidationError('Required fields missing.');
    const feedbackRef = db.collection('obhs_feedbacks').doc();
    const totalStars = Object.values(ratings).reduce((a, b) => a + Number(b), 0);
    const overallRating = parseFloat((totalStars / 5).toFixed(2));
    const fType = (feedbackType || 'PASSENGER').toUpperCase();
    const feedbackData = {
      feedbackId: feedbackRef.id,
      feedbackType: fType,
      runInstanceId, coachNo, ratings, overallRating,
      remarks: remarks || '', createdAt: new Date().toISOString()
    };
    if (fType === 'OFFICIAL') {
      feedbackData.inspectorName = inspectorName || userData.fullName;
    } else {
      feedbackData.passengerName = passengerName || 'Anonymous';
      feedbackData.mobileNumber = mobileNumber || '';
    }
    await feedbackRef.set(feedbackData);

    return { success: true, message: 'Feedback submitted.', overallRating };
  }

  async getFeedbacks(filters = {}) {
    const { workerId } = filters;
    if (!workerId) throw new ValidationError('workerId required.');
    const snapshot = await db.collection('obhs_feedbacks').limit(200).get();
    const feedbacks = [];
    snapshot.forEach(doc => {
      const d = doc.data();
      if (d.targetWorker === workerId || d.coachNo) feedbacks.push(d);
    });
    const avgRating = feedbacks.length > 0
      ? parseFloat((feedbacks.reduce((s, f) => s + (f.overallRating || 0), 0) / feedbacks.length).toFixed(2))
      : 0;
    return { count: feedbacks.length, averageRating: avgRating, feedbacks };
  }

  async getWorkerStats(workerId) {
    if (!workerId) throw new ValidationError('workerId is required.');
    const [taskSnap, ratingSnap] = await Promise.all([
      db.collection('obhs_tasks').where('submittedBy.id', '==', workerId).limit(200).get(),
      db.collection('worker_ratings').where('workerId', '==', workerId).limit(200).get()
    ]);
    const taskStats = { total: 0, completed: 0 };
    taskSnap.forEach(doc => {
      const t = doc.data();
      taskStats.total++;
      if (t.status === 'Completed') taskStats.completed++;
    });
    let totalScore = 0, ratingCount = 0;
    const categories = {};
    ratingSnap.forEach(doc => {
      const d = doc.data();
      totalScore += Number(d.score) || 0;
      ratingCount++;
      if (!categories[d.category]) categories[d.category] = { total: 0, count: 0 };
      categories[d.category].total += Number(d.score) || 0;
      categories[d.category].count++;
    });
    return {
      workerId,
      taskStats: {
        totalTasks: taskStats.total,
        completedTasks: taskStats.completed,
        completionRate: taskStats.total > 0 ? parseFloat(((taskStats.completed / taskStats.total) * 100).toFixed(2)) : 0
      },
      ratingStats: {
        averageScore: ratingCount > 0 ? parseFloat((totalScore / ratingCount).toFixed(2)) : 0,
        totalRatings: ratingCount,
        categoryBreakdown: Object.entries(categories).map(([k, v]) => ({
          category: k,
          average: parseFloat((v.total / v.count).toFixed(2)),
          count: v.count
        }))
      }
    };
  }

  // ─── GARBAGE TASKS ──────────────────────────────────────────────────────

  async getGarbageTasks(filters = {}) {
    const { runInstanceId, workerId, status } = filters;
    if (!runInstanceId) throw new ValidationError('runInstanceId query parameter is required.');
    let query = db.collection('garbage_tasks')
      .where('runInstanceId', '==', runInstanceId);
    if (workerId) query = query.where('workerId', '==', workerId);
    if (status) query = query.where('status', '==', status);
    const snapshot = await query.limit(200).get();
    const tasks = [];
    snapshot.forEach(doc => tasks.push(doc.data()));
    tasks.sort((a, b) => (a.scheduledTime || '').localeCompare(b.scheduledTime || ''));
    return { success: true, count: tasks.length, tasks };
  }

  async completeGarbageTask(body) {
    const { taskId, beforePhoto, afterPhoto, latitude, longitude } = body;
    if (!taskId || !beforePhoto || !afterPhoto) {
      throw new ValidationError('taskId, beforePhoto, and afterPhoto are required.');
    }
    const ref = db.collection('garbage_tasks').doc(taskId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Garbage task not found.');
    await ref.update({
      status: 'COMPLETED',
      beforePhoto,
      afterPhoto,
      gpsLatitude: latitude || null,
      gpsLongitude: longitude || null,
      completedAt: new Date().toISOString()
    });
    return { success: true, message: 'Garbage task completed', taskId };
  }

  async getPreTerminalGarbageTasks(runInstanceId) {
    if (!runInstanceId) throw new ValidationError('runInstanceId query parameter is required.');
    const snapshot = await db.collection('garbage_tasks')
      .where('runInstanceId', '==', runInstanceId)
      .where('isPreTerminal', '==', true)
      .limit(200).get();
    const tasks = [];
    snapshot.forEach(doc => tasks.push(doc.data()));
    return { success: true, count: tasks.length, tasks };
  }

  // ─── WATER CHECKS ────────────────────────────────────────────────────────

  // A check is uniquely identified by the coach it was taken on plus the time
  // slot, so the field app can submit a check without a server-issued id.
  _slotDocId(prefix, runInstanceId, coachNo, slotTime) {
    const slot = String(slotTime || '').replace(/[^0-9]/g, '').slice(0, 8) || 'NA';
    const coach = String(coachNo || 'NA').replace(/[^A-Za-z0-9]/g, '');
    return `${prefix}_${runInstanceId}_${coach}_${slot}`;
  }

  async getWaterChecks(filters = {}) {
    const { runInstanceId } = filters;
    if (!runInstanceId) throw new ValidationError('runInstanceId query parameter is required.');
    const snapshot = await db.collection('water_checks')
      .where('runInstanceId', '==', runInstanceId)
      .limit(200).get();
    const checks = [];
    snapshot.forEach(doc => checks.push({ id: doc.id, ...doc.data() }));
    checks.sort((a, b) => (a.checkTime || '').localeCompare(b.checkTime || ''));
    return { success: true, count: checks.length, checks };
  }

  async submitWaterCheck(body) {
    const { checkId, runInstanceId, coachNo, checkTime, waterStatus, lowWaterAlert, wateringPointSchedule, photoUrl } = body;
    if (!waterStatus) {
      throw new ValidationError('waterStatus is required.');
    }
    if (!['full', 'low', 'empty'].includes(waterStatus)) {
      throw new ValidationError('Invalid waterStatus. Must be: full, low, or empty.');
    }
    if (!checkId && !(runInstanceId && coachNo)) {
      throw new ValidationError('Provide checkId, or runInstanceId together with coachNo.');
    }

    const ref = checkId
      ? db.collection('water_checks').doc(checkId)
      : db.collection('water_checks').doc(this._slotDocId('water', runInstanceId, coachNo, checkTime));

    const now = new Date().toISOString();
    const payload = {
      waterStatus,
      lowWaterAlert: lowWaterAlert !== undefined
        ? !!lowWaterAlert
        : (waterStatus === 'empty' || waterStatus === 'low'),
      wateringPointSchedule: wateringPointSchedule || null,
      photoUrl: photoUrl || null,
      status: 'COMPLETED',
      completedAt: now,
      updatedAt: now
    };
    // Identity fields are only written when creating, so a resend of the same
    // slot updates the check instead of orphaning the original.
    if (!checkId) {
      payload.runInstanceId = runInstanceId;
      payload.coachNo = coachNo;
      payload.checkTime = checkTime || now;
      payload.checkDate = String(payload.checkTime).split('T')[0];
      payload.createdAt = now;
    }
    await ref.set(payload, { merge: true });
    return { success: true, message: 'Water check submitted', checkId: ref.id };
  }

  async getWaterAlerts(runInstanceId) {
    if (!runInstanceId) throw new ValidationError('runInstanceId query parameter is required.');
    const snapshot = await db.collection('water_checks')
      .where('runInstanceId', '==', runInstanceId)
      .where('lowWaterAlert', '==', true)
      .limit(200).get();
    const alerts = [];
    snapshot.forEach(doc => alerts.push({ id: doc.id, ...doc.data() }));
    return { success: true, count: alerts.length, alerts };
  }

  // ─── SAFETY CHECKS ───────────────────────────────────────────────────────

  async getSafetyChecks(runInstanceId) {
    if (!runInstanceId) throw new ValidationError('runInstanceId query parameter is required.');
    const snapshot = await db.collection('safety_checks')
      .where('runInstanceId', '==', runInstanceId)
      .limit(200).get();
    const checks = [];
    snapshot.forEach(doc => checks.push({ id: doc.id, ...doc.data() }));
    checks.sort((a, b) => (a.scheduledTime || '').localeCompare(b.scheduledTime || ''));
    return { success: true, count: checks.length, checks };
  }

  async submitSafetyCheck(body) {
    const { checkId, runInstanceId, coachNo, scheduledTime, fireExtinguisherStatus, fsdsStatus, cctvStatus, emergencyEquipmentStatus, photos, deficiencyReports, remarks } = body;
    // The field app submits run-wide checks that are not tied to a single
    // coach, so fall back to a stable per-run slot instead of rejecting.
    const effectiveCoachNo = coachNo || 'ALL';
    if (!checkId && !runInstanceId) {
      throw new ValidationError('Provide checkId, or runInstanceId together with coachNo.');
    }
    const ref = checkId
      ? db.collection('safety_checks').doc(checkId)
      : db.collection('safety_checks').doc(this._slotDocId('safety', runInstanceId, effectiveCoachNo, scheduledTime));

    const now = new Date().toISOString();
    const payload = {
      fireExtinguisherStatus: fireExtinguisherStatus || null,
      fsdsStatus: fsdsStatus || null,
      cctvStatus: cctvStatus || null,
      emergencyEquipmentStatus: emergencyEquipmentStatus || null,
      photos: photos || [],
      deficiencyReports: deficiencyReports || [],
      status: 'COMPLETED',
      remarks: remarks || null,
      completedAt: now,
      updatedAt: now
    };
    if (!checkId) {
      payload.runInstanceId = runInstanceId;
      payload.coachNo = effectiveCoachNo;
      payload.scheduledTime = scheduledTime || now;
      payload.createdAt = now;
    }
    await ref.set(payload, { merge: true });
    return { success: true, message: 'Safety check submitted', checkId: ref.id };
  }

  async reportSafetyDeficiency(userData, body) {
    const { checkId, deficiencyReport, photoUrl } = body;
    if (!checkId || !deficiencyReport) {
      throw new ValidationError('checkId and deficiencyReport are required.');
    }
    const ref = db.collection('safety_checks').doc(checkId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Safety check not found.');
    // `deficiencyReports` is a List<String> in the Flutter model, so append the
    // report text rather than an object.
    await ref.update({
      deficiencyReports: admin.firestore.FieldValue.arrayUnion(deficiencyReport)
    });
    return { success: true, message: 'Deficiency reported', checkId };
  }

  // ─── PETTY REPAIRS ───────────────────────────────────────────────────────

  async getPettyRepairs(runInstanceId) {
    if (!runInstanceId) throw new ValidationError('runInstanceId query parameter is required.');
    const snapshot = await db.collection('petty_repairs')
      .where('runInstanceId', '==', runInstanceId)
      .limit(200).get();
    const repairs = [];
    snapshot.forEach(doc => repairs.push({ id: doc.id, ...doc.data() }));
    repairs.sort((a, b) => (a.inspectionTime || '').localeCompare(b.inspectionTime || ''));
    return { success: true, count: repairs.length, repairs };
  }

  async submitPettyRepair(body) {
    const { repairId, runInstanceId, coachNo, inspectionTime, items, remarks } = body;
    if (!repairId && !(runInstanceId && coachNo)) {
      throw new ValidationError('Provide repairId, or runInstanceId together with coachNo.');
    }
    const ref = repairId
      ? db.collection('petty_repairs').doc(repairId)
      : db.collection('petty_repairs').doc(this._slotDocId('repair', runInstanceId, coachNo, inspectionTime));

    const now = new Date().toISOString();
    const updateData = {
      items: items || {},
      status: items ? 'COMPLETED' : 'PENDING',
      remarks: remarks || null,
      updatedAt: now
    };
    if (!repairId) {
      updateData.runInstanceId = runInstanceId;
      updateData.coachNo = coachNo;
      updateData.inspectionTime = inspectionTime || now;
      updateData.isEscalated = false;
      updateData.createdAt = now;
    }
    await ref.set(updateData, { merge: true });
    return { success: true, message: 'Petty repair inspection submitted', repairId: ref.id };
  }

  async escalatePettyRepair(body) {
    const { repairId, escalatedTo } = body;
    if (!repairId) throw new ValidationError('repairId is required.');
    const ref = db.collection('petty_repairs').doc(repairId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Petty repair record not found.');
    await ref.update({
      isEscalated: true,
      escalatedTo: escalatedTo || 'supervisor',
      status: 'ESCALATED',
      updatedAt: new Date().toISOString()
    });
    return { success: true, message: 'Repair escalated', repairId };
  }

  // ─── RATINGS ────────────────────────────────────────────────────────────

  async submitRating(userData, body) {
    const { runInstanceId, coachNo, employeeId, source, rating, remarks } = body;
    if (!runInstanceId || !source || !rating) {
      throw new ValidationError('runInstanceId, source, and rating are required.');
    }
    const validSources = ['passenger', 'tte', 'supervisor', 'railway_official'];
    if (!validSources.includes(source)) {
      throw new ValidationError(`Invalid source. Must be one of: ${validSources.join(', ')}`);
    }
    if (rating < 1 || rating > 5) {
      throw new ValidationError('Rating must be between 1 and 5.');
    }
    const ref = db.collection('obhs_ratings').doc();
    const data = {
      id: ref.id,
      runInstanceId,
      coachNo: coachNo || null,
      employeeId: employeeId || userData.uid,
      taskId: body.taskId || null,
      source,
      rating: Number(rating),
      journeyId: runInstanceId,
      remarks: remarks || null,
      createdAt: new Date().toISOString()
    };
    await ref.set(data);
    return { success: true, message: 'Rating submitted', ratingId: ref.id };
  }

  async getRatings(filters = {}) {
    const { employeeId, runInstanceId, source } = filters;
    let query = db.collection('obhs_ratings');
    if (employeeId) query = query.where('employeeId', '==', employeeId);
    if (runInstanceId) query = query.where('runInstanceId', '==', runInstanceId);
    if (source) query = query.where('source', '==', source);
    const snapshot = await query.limit(200).get();
    const ratings = [];
    snapshot.forEach(doc => ratings.push(doc.data()));
    return { success: true, count: ratings.length, ratings };
  }

  async getEmployeePerformance(employeeId) {
    if (!employeeId) throw new ValidationError('employeeId is required.');
    const snapshot = await db.collection('obhs_ratings').where('employeeId', '==', employeeId).limit(200).get();
    let totalRating = 0, count = 0;
    const sourceBreakdown = {
      passenger: { total: 0, count: 0 },
      tte: { total: 0, count: 0 },
      supervisor: { total: 0, count: 0 },
      railway_official: { total: 0, count: 0 }
    };
    snapshot.forEach(doc => {
      const r = doc.data();
      totalRating += r.rating;
      count++;
      if (sourceBreakdown[r.source]) {
        sourceBreakdown[r.source].total += r.rating;
        sourceBreakdown[r.source].count++;
      }
    });
    const avgRating = count > 0 ? parseFloat((totalRating / count).toFixed(2)) : 0;
    const breakdown = {};
    for (const [key, val] of Object.entries(sourceBreakdown)) {
      breakdown[key] = {
        average: val.count > 0 ? parseFloat((val.total / val.count).toFixed(2)) : 0,
        count: val.count
      };
    }
    return {
      success: true,
      employeeId,
      averageRating: avgRating,
      totalRatings: count,
      sourceBreakdown: breakdown
    };
  }

  // ─── COMPLAINTS SLA ─────────────────────────────────────────────────────

  async updateComplaintSLA(complaintId, body) {
    const { status, resolutionNotes, resolutionPhotoUrl, escalatedTo } = body;
    const ref = db.collection('obhs_complaints').doc(complaintId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Complaint not found.');
    const complaint = doc.data();
    const createdAt = new Date(complaint.createdAt);
    const now = new Date();
    const resolutionTimeMinutes = Math.round((now - createdAt) / (1000 * 60));

    const slaMap = {
      'Cleaning': 30, 'Garbage': 20, 'Water': 30,
      'Petty Repair': 60, 'Toilet': 30, 'Electrical': 60,
      'Toilet Cleaning': 30, 'Coach Cleaning': 30
    };
    const slaMinutes = slaMap[complaint.category] || 30;
    const slaBreached = resolutionTimeMinutes > slaMinutes;

    const updateData = {
      status: status || complaint.status,
      updatedAt: now.toISOString(),
      slaMinutes,
      resolutionTimeMinutes,
      slaBreached,
      resolutionNotes: resolutionNotes || complaint.resolutionNotes || null,
      resolutionPhotoUrl: resolutionPhotoUrl || complaint.resolutionPhotoUrl || null
    };
    if (escalatedTo) updateData.escalatedTo = escalatedTo;
    if (status === 'RESOLVED' || status === 'CLOSED') {
      updateData.resolvedAt = now.toISOString();
    }
    await ref.update(updateData);
    return {
      success: true,
      message: 'Complaint SLA updated',
      complaintId,
      resolutionTimeMinutes,
      slaBreached,
      slaMinutes
    };
  }

  async getSLAReport(runInstanceId) {
    let query = db.collection('obhs_complaints');
    if (runInstanceId) query = query.where('runInstanceId', '==', runInstanceId);
    const snapshot = await query.limit(200).get();
    let total = 0, withinSLA = 0, breached = 0, open = 0;
    const categoryStats = {};
    snapshot.forEach(doc => {
      const c = doc.data();
      total++;
      if (c.status === 'OPEN' || c.status === 'ESCALATED') open++;
      if (c.slaBreached) breached++;
      else if (c.status === 'RESOLVED' || c.status === 'CLOSED') withinSLA++;
      const cat = c.category || 'Other';
      if (!categoryStats[cat]) categoryStats[cat] = { total: 0, breached: 0, withinSLA: 0 };
      categoryStats[cat].total++;
      if (c.slaBreached) categoryStats[cat].breached++;
      else if (c.status === 'RESOLVED' || c.status === 'CLOSED') categoryStats[cat].withinSLA++;
    });
    const slaComplianceRate = (total - open) > 0
      ? parseFloat((withinSLA / (total - open) * 100).toFixed(1))
      : 0;
    return {
      success: true,
      total,
      open,
      resolved: withinSLA + breached,
      withinSLA,
      slaBreached: breached,
      slaComplianceRate,
      categoryStats
    };
  }

  async autoRouteComplaint(body) {
    const { complaintId } = body;
    if (!complaintId) throw new ValidationError('complaintId is required.');
    const ref = db.collection('obhs_complaints').doc(complaintId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Complaint not found');
    const complaint = doc.data();
    const description = (complaint.description || '').toLowerCase();
    const category = (complaint.category || '').toLowerCase();
    const text = `${category} ${description}`;
    const keywordMap = [
      { keywords: ['toilet', 'bathroom', 'restroom', 'washroom', 'sanitary', 'urinal', 'foul smell', 'stink'], taskType: 'Toilet Cleaning', priority: 2 },
      { keywords: ['clean', 'dirty', 'dust', 'sweep', 'mop', 'garbage', 'waste', 'litter', 'rubbish', 'spill'], taskType: 'Coach Cleaning', priority: 3 },
      { keywords: ['linen', 'bedsheet', 'pillow', 'blanket', 'bed roll', 'curtain'], taskType: 'Linen Distribution', priority: 3 },
      { keywords: ['light', 'fan', 'ac', 'air conditioner', 'cooling', 'electrical', 'plug', 'charging', 'switch'], taskType: 'Electrical Issue', priority: 2 },
      { keywords: ['water', 'drinking', 'supply', 'tap', 'leak', 'pipeline', 'overflow'], taskType: 'Water Issue', priority: 2 },
      { keywords: ['seat', 'berth', 'broken', 'damage', 'repair', 'maintenance', 'crack', 'rust'], taskType: 'Maintenance Issue', priority: 2 },
      { keywords: ['security', 'theft', 'safety', 'suspicious', 'unauthorized'], taskType: 'Security Issue', priority: 1 },
      { keywords: ['staff', 'behaviour', 'rude', 'misbehave', 'attitude', 'service'], taskType: 'Staff Behaviour', priority: 3 },
    ];
    let assignedTaskType = 'Coach Cleaning';
    let assignedPriority = 'medium';
    let bestScore = 0;
    keywordMap.forEach(entry => {
      const score = entry.keywords.reduce((sum, kw) => sum + (text.includes(kw) ? 1 : 0), 0);
      if (score > bestScore) {
        bestScore = score;
        assignedTaskType = entry.taskType;
        assignedPriority = entry.priority;
      }
    });
    await ref.update({
      suggestedTaskType: assignedTaskType,
      suggestedPriority: assignedPriority,
      autoRoutedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });
    const auditRef = db.collection('auditLogs').doc();
    await auditRef.set({
      logId: auditRef.id,
      action: 'COMPLAINT_AUTO_ROUTED',
      performedBy: 'system',
      performedByName: 'System',
      targetEntity: complaintId,
      targetEntityType: 'obhs_complaints',
      timestamp: new Date().toISOString(),
      details: `Auto-routed complaint ${complaintId} → Task: ${assignedTaskType}, Priority: ${assignedPriority}`
    });
    return {
      success: true,
      message: 'Complaint auto-routed',
      suggestedTaskType: assignedTaskType,
      suggestedPriority: assignedPriority
    };
  }

  // ─── SUPERVISOR DASHBOARD ────────────────────────────────────────────────

  async getSupervisorDashboard(userData) {
    const allowedRoles = ['Admin', 'Supervisor', 'Company Master', 'Railway Supervisor'];
    if (!allowedRoles.includes(userData.role)) {
      throw new ForbiddenError('Access denied. Supervisor role required.');
    }

    const activeRunsSnap = await db.collection('RunInstance').where('status', '==', 'Active').limit(200).get();
    const activeTrains = activeRunsSnap.size;
    const activeWorkersSet = new Set();
    activeRunsSnap.forEach(doc => {
      const data = doc.data();
      if (data.coaches) data.coaches.forEach(c => { if (c.workerId) activeWorkersSet.add(c.workerId); });
    });

    const openDetailsSnap = await db.collection('task_details').where('status', 'in', ['OPEN', 'OVERDUE']).limit(200).get();
    let missedTasks = 0, overdueTasks = 0;
    openDetailsSnap.forEach(doc => {
      if (doc.data().status === 'OVERDUE') overdueTasks++;
      else missedTasks++;
    });

    const escalatedDetailsSnap = await db.collection('task_details').where('status', '==', 'ESCALATED').limit(200).get();
    const escalatedTasks = escalatedDetailsSnap.size;

    const openComplaintsSnap = await db.collection('obhs_complaints').where('status', '==', 'OPEN').limit(200).get();
    const openComplaints = openComplaintsSnap.size;

    const ratingsSnap = await db.collection('obhs_ratings').limit(200).get();
    let totalRating = 0, ratingCount = 0;
    ratingsSnap.forEach(doc => { totalRating += doc.data().rating || 0; ratingCount++; });
    const averageRating = ratingCount > 0 ? parseFloat((totalRating / ratingCount).toFixed(2)) : 0;

    const lowWaterSnap = await db.collection('water_checks').where('status', '==', 'PENDING').where('lowWaterAlert', '==', true).limit(200).get();
    const waterIssues = lowWaterSnap.size;

    const safetySnap = await db.collection('safety_checks').where('status', '==', 'PENDING').limit(200).get();
    let safetyIssues = 0;
    safetySnap.forEach(doc => {
      const d = doc.data();
      if (d.fireExtinguisherStatus === 'deficient' || d.fsdsStatus === 'deficient') safetyIssues++;
    });

    return {
      success: true,
      dashboard: {
        activeTrains,
        activeWorkers: activeWorkersSet.size,
        missedTasks,
        overdueTasks,
        escalatedTasks,
        openComplaints,
        averageRating,
        waterIssues,
        safetyIssues,
        lastUpdated: new Date().toISOString()
      }
    };
  }

  // ─── WORKER ACTIVE RUN ───────────────────────────────────────────────────

  async getWorkerActiveRun(uid) {
    const snapshot = await db.collection('RunInstance')
      .where('status', 'in', ['ALLOCATED', 'ACTIVE', 'Active', 'active', 'READY', 'ready', 'Running', 'running'])
      .limit(200).get();

    const runs = [];
    snapshot.forEach(doc => runs.push({ id: doc.id, ...doc.data() }));
    runs.sort((a, b) => ((b.createdAt || '') > (a.createdAt || '') ? 1 : -1));

    let runDoc = null;
    for (const r of runs) {
      const coaches = r.coaches || [];
      if (coaches.some(c => c.workerId === uid)) {
        runDoc = r;
        break;
      }
    }

    if (!runDoc) {
      return { success: true, hasAssignment: false, run: null };
    }
    const runData = runDoc;
    const myCoaches = (runData.coaches || []).filter(c => c.workerId === uid);

    return {
      success: true,
      hasAssignment: true,
      run: {
        runInstanceId: runData.id,
        trainNo: runData.trainNo || runData.trainNumber || 'N/A',
        trainName: runData.trainName || runData.name || '',
        status: runData.status,
        departureDate: runData.departureDate || '',
        departureTime: runData.departureTime || '',
      },
      coaches: myCoaches.map(c => ({
        coachNo: c.coachPosition || c.coachNo || c.id || 'N/A',
        coachType: c.coachType || 'general',
        workerId: c.workerId,
        workerName: c.workerName || c.name || '',
        workerRole: c.workerRole || 'janitor'
      }))
    };
  }
}

export const obhsService = new ObhsService();
