import { db } from '../database/index.js';
import { ValidationError, NotFoundError } from '../errors/index.js';
import logger from '../logger/index.js';

class ObhsAnalyticsService {
  async _resolveRunInstanceIds(filters = {}) {
    const { runInstanceId, division, zone, startDate, endDate } = filters;
    if (runInstanceId) return [runInstanceId];
    // Without a run or any division/zone scope there is nothing safe to
    // aggregate over — returning [] would silently report 0% compliance.
    if (!division && !zone && !startDate && !endDate) {
      throw new ValidationError('Provide runInstanceId, or a division/zone, or a date range.');
    }
    let query = db.collection('RunInstance');
    if (division) query = query.where('division', '==', division);
    if (zone) query = query.where('zone', '==', zone);
    if (startDate) query = query.where('departureDate', '>=', startDate);
    if (endDate) query = query.where('departureDate', '<=', endDate);
    const snap = await query.limit(200).get();
    return snap.docs.map(d => d.id);
  }

  async _buildDateRangeFilter(dateField, startDate, endDate) {
    if (!startDate && !endDate) return null;
    let query = null;
    if (startDate && endDate) {
      query = { field: dateField, op: '>=', val: startDate };
    } else if (startDate) {
      query = { field: dateField, op: '>=', val: startDate };
    } else if (endDate) {
      query = { field: dateField, op: '<=', val: endDate };
    }
    return query;
  }

  async getJanitorPerformance(filters = {}) {
    try {
      const runIds = await this._resolveRunInstanceIds(filters);
      const janitors = {};

      const runDocs = (await Promise.all(runIds.map(runId =>
        db.collection('RunInstance').doc(runId).get()
      ))).filter(d => d.exists).map(d => d.data());
      for (const runData of runDocs) {
        for (const coach of (runData.coaches || [])) {
          if (coach.workerId && !janitors[coach.workerId]) {
            janitors[coach.workerId] = {
              janitorId: coach.workerId, janitorName: coach.workerName || 'Unknown',
              tasksCompleted: 0, tasksMissed: 0, tasksOverdue: 0, totalTasks: 0,
              averageRating: 0, completionPercentage: 0, coachCleanlinessScore: 0
            };
          }
        }
      }

      const detailsSnaps = await Promise.all(runIds.map(runId =>
        db.collection('task_details').where('runInstanceId', '==', runId).limit(200).get()
      ));
      for (const detailsSnap of detailsSnaps) {
        detailsSnap.forEach(doc => {
          const d = doc.data();
          const wId = d.workerId;
          if (wId && janitors[wId]) {
            janitors[wId].totalTasks++;
            if (d.status === 'COMPLETED') janitors[wId].tasksCompleted++;
            else if (d.status === 'OVERDUE') janitors[wId].tasksOverdue++;
            else if (d.status === 'PLANNED') janitors[wId].tasksMissed++;
          }
        });
      }

      const ratingMap = {};
      const ratingCountMap = {};
      const ratingsSnaps = await Promise.all(runIds.map(runId =>
        db.collection('ratings').where('runInstanceId', '==', runId).limit(200).get()
      ));
      for (const ratingsSnap of ratingsSnaps) {
        ratingsSnap.forEach(doc => {
          const r = doc.data();
          const eid = r.employeeId;
          if (eid) {
            ratingMap[eid] = (ratingMap[eid] || 0) + (r.rating || 0);
            ratingCountMap[eid] = (ratingCountMap[eid] || 0) + 1;
          }
        });
      }

      const result = Object.values(janitors).map(j => ({
        ...j,
        averageRating: ratingCountMap[j.janitorId]
          ? parseFloat((ratingMap[j.janitorId] / ratingCountMap[j.janitorId]).toFixed(2)) : 0,
        completionPercentage: j.totalTasks > 0
          ? parseFloat(((j.tasksCompleted / j.totalTasks) * 100).toFixed(1)) : 0
      }));

      return { success: true, performance: result, count: result.length };
    } catch (error) {
      logger.error('ObhsAnalyticsService', 'getJanitorPerformance error', error);
      throw error;
    }
  }

  async getCoachCleanliness(filters = {}) {
    try {
      const runIds = await this._resolveRunInstanceIds(filters);

      const coaches = {};
      const detailsSnaps = await Promise.all(runIds.map(runId =>
        db.collection('task_details').where('runInstanceId', '==', runId).limit(200).get()
      ));
      for (const detailsSnap of detailsSnaps) {
        detailsSnap.forEach(doc => {
          const d = doc.data();
          const cn = d.coachNo;
          if (!cn) return;
          if (!coaches[cn]) {
            coaches[cn] = { coachNo: cn, totalToiletTasks: 0, toiletCompletions: 0, totalTasks: 0, completedTasks: 0 };
          }
          coaches[cn].totalTasks++;
          if (d.status === 'COMPLETED') {
            coaches[cn].completedTasks++;
            if (d.taskType === 'toilet_cleaning') coaches[cn].toiletCompletions++;
          }
          if (d.taskType === 'toilet_cleaning') coaches[cn].totalToiletTasks++;
        });
      }

      const garbageMap = {};
      const garbageSnaps = await Promise.all(runIds.map(runId =>
        db.collection('garbage_tasks').where('runInstanceId', '==', runId).limit(200).get()
      ));
      for (const garbageSnap of garbageSnaps) {
        garbageSnap.forEach(doc => {
          const g = doc.data();
          if (g.coachNo) garbageMap[g.coachNo] = (garbageMap[g.coachNo] || 0) + 1;
        });
      }

      const waterIssuesMap = {};
      const waterSnaps = await Promise.all(runIds.map(runId =>
        db.collection('water_checks').where('runInstanceId', '==', runId).where('lowWaterAlert', '==', true).limit(200).get()
      ));
      for (const waterSnap of waterSnaps) {
        waterSnap.forEach(doc => {
          const w = doc.data();
          if (w.coachNo) waterIssuesMap[w.coachNo] = (waterIssuesMap[w.coachNo] || 0) + 1;
        });
      }

      const result = Object.values(coaches).map(c => ({
        ...c,
        cleanlinessScore: c.totalTasks > 0 ? parseFloat(((c.completedTasks / c.totalTasks) * 100).toFixed(1)) : 0,
        garbageIssues: garbageMap[c.coachNo] || 0,
        waterIssues: waterIssuesMap[c.coachNo] || 0
      }));

      return { success: true, coaches: result, count: result.length };
    } catch (error) {
      logger.error('ObhsAnalyticsService', 'getCoachCleanliness error', error);
      throw error;
    }
  }

  async getAttendanceCompliance(filters = {}) {
    try {
      const runIds = await this._resolveRunInstanceIds(filters);

      let total = 0, onTime = 0, late = 0;
      const attendanceSnaps = await Promise.all(runIds.map(runId =>
        db.collection('obhs_attendance').where('runInstanceId', '==', runId).limit(200).get()
      ));
      for (const snapshot of attendanceSnaps) {
        snapshot.forEach(doc => {
          const d = doc.data();
          total++;
          const startLate = d.startAttendance && d.startAttendance.isLate;
          const midLate = d.midAttendance && d.midAttendance.isLate;
          const endLate = d.endAttendance && d.endAttendance.isLate;
          if (startLate || midLate || endLate) late++;
          else onTime++;
        });
      }

      return {
        success: true, total, onTime, late,
        complianceRate: total > 0 ? parseFloat(((onTime / total) * 100).toFixed(1)) : 0,
        // Alias kept for the mobile client, which reads compliancePercentage.
        compliancePercentage: total > 0 ? parseFloat(((onTime / total) * 100).toFixed(1)) : 0
      };
    } catch (error) {
      logger.error('ObhsAnalyticsService', 'getAttendanceCompliance error', error);
      throw error;
    }
  }

  async getTaskCompletion(filters = {}) {
    try {
      const runIds = await this._resolveRunInstanceIds(filters);

      let total = 0, completed = 0, overdue = 0, planned = 0, open = 0, escalated = 0;
      const taskSnaps = await Promise.all(runIds.map(runId =>
        db.collection('task_details').where('runInstanceId', '==', runId).limit(200).get()
      ));
      for (const snapshot of taskSnaps) {
        snapshot.forEach(doc => {
          const d = doc.data();
          total++;
          switch (d.status) {
            case 'COMPLETED': completed++; break;
            case 'OVERDUE': overdue++; break;
            case 'PLANNED': planned++; break;
            case 'OPEN': open++; break;
            case 'ESCALATED': escalated++; break;
          }
        });
      }

      const completionRate = total > 0 ? parseFloat(((completed / total) * 100).toFixed(1)) : 0;
      const overdueRate = total > 0 ? parseFloat(((overdue / total) * 100).toFixed(1)) : 0;
      return {
        success: true, total, completed, overdue, planned, open, escalated,
        completionRate, overdueRate,
        // Aliases consumed by the mobile analytics screen.
        completionPercentage: completionRate,
        completedTasks: completed,
        pendingTasks: planned + open,
        overdueTasks: overdue,
        totalTasks: total
      };
    } catch (error) {
      logger.error('ObhsAnalyticsService', 'getTaskCompletion error', error);
      throw error;
    }
  }

  async getPassengerRatingTrend(filters = {}) {
    try {
      const runIds = await this._resolveRunInstanceIds(filters);
      const dailyRates = {};

      if (runIds.length > 0) {
        const feedbackSnaps = await Promise.all(runIds.map(runId =>
          db.collection('obhs_feedbacks').where('runInstanceId', '==', runId).limit(200).get()
        ));
        for (const snapshot of feedbackSnaps) {
          snapshot.forEach(doc => {
            const f = doc.data();
            if (f.feedbackType === 'PASSENGER' && f.overallRating) {
              const date = f.date || (f.createdAt ? new Date(f.createdAt).toISOString().split('T')[0] : '');
              if (!date) return;
              if (!dailyRates[date]) dailyRates[date] = { total: 0, count: 0 };
              dailyRates[date].total += f.overallRating;
              dailyRates[date].count++;
            }
          });
        }
      } else {
        const snapshot = await db.collection('obhs_feedbacks').limit(200).get();
        snapshot.forEach(doc => {
          const f = doc.data();
          if (f.feedbackType === 'PASSENGER' && f.overallRating) {
            const date = f.date || (f.createdAt ? new Date(f.createdAt).toISOString().split('T')[0] : '');
            if (!date) return;
            if (!dailyRates[date]) dailyRates[date] = { total: 0, count: 0 };
            dailyRates[date].total += f.overallRating;
            dailyRates[date].count++;
          }
        });
      }

      const trend = Object.entries(dailyRates)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([date, data]) => ({
          date,
          averageRating: parseFloat((data.total / data.count).toFixed(2)),
          count: data.count
        }));

      const overallAvg = trend.length > 0
        ? parseFloat((trend.reduce((s, d) => s + d.averageRating, 0) / trend.length).toFixed(2))
        : 0;

      return { success: true, trend, overallAverageRating: overallAvg };
    } catch (error) {
      logger.error('ObhsAnalyticsService', 'getPassengerRatingTrend error', error);
      throw error;
    }
  }

  async getPenaltyRisk(filters = {}) {
    try {
      const runIds = await this._resolveRunInstanceIds(filters);
      const overdueByWorker = {};

      if (runIds.length > 0) {
        const overdueSnaps = await Promise.all(runIds.map(runId =>
          db.collection('task_details')
            .where('runInstanceId', '==', runId)
            .where('status', '==', 'OVERDUE')
            .limit(200).get()
        ));
        for (const overdueSnap of overdueSnaps) {
          overdueSnap.forEach(doc => {
            const d = doc.data();
            const key = d.workerId || 'unknown';
            if (!overdueByWorker[key]) {
              overdueByWorker[key] = { workerId: key, workerName: d.workerName || 'Unknown', overdueCount: 0, missedCount: 0, penaltyAmount: 0 };
            }
            overdueByWorker[key].overdueCount++;
            overdueByWorker[key].penaltyAmount += 50;
          });
        }

        const attendSnaps = await Promise.all(runIds.map(runId =>
          db.collection('obhs_attendance').where('runInstanceId', '==', runId).limit(200).get()
        ));
        for (const attendSnap of attendSnaps) {
          attendSnap.forEach(doc => {
            const d = doc.data();
            const key = d.uid ? d.uid.split('_')[1] : 'unknown';
            if (!d.startAttendance || !d.endAttendance) {
              if (!overdueByWorker[key]) {
                overdueByWorker[key] = { workerId: key, workerName: 'Unknown', overdueCount: 0, missedCount: 0, penaltyAmount: 0 };
              }
              overdueByWorker[key].missedCount++;
              overdueByWorker[key].penaltyAmount += 100;
            }
          });
        }
      } else {
        const overdueSnap = await db.collection('task_details').where('status', '==', 'OVERDUE').limit(200).get();
        overdueSnap.forEach(doc => {
          const d = doc.data();
          const key = d.workerId || 'unknown';
          if (!overdueByWorker[key]) {
            overdueByWorker[key] = { workerId: key, workerName: d.workerName || 'Unknown', overdueCount: 0, missedCount: 0, penaltyAmount: 0 };
          }
          overdueByWorker[key].overdueCount++;
          overdueByWorker[key].penaltyAmount += 50;
        });

        const attendSnap = await db.collection('obhs_attendance').limit(200).get();
        attendSnap.forEach(doc => {
          const d = doc.data();
          const key = d.uid ? d.uid.split('_')[1] : 'unknown';
          if (!d.startAttendance || !d.endAttendance) {
            if (!overdueByWorker[key]) {
              overdueByWorker[key] = { workerId: key, workerName: 'Unknown', overdueCount: 0, missedCount: 0, penaltyAmount: 0 };
            }
            overdueByWorker[key].missedCount++;
            overdueByWorker[key].penaltyAmount += 100;
          }
        });
      }

      const riskReport = Object.values(overdueByWorker);
      const totalPenaltyRisk = riskReport.reduce((s, r) => s + r.penaltyAmount, 0);
      return {
        success: true,
        riskReport,
        totalPenaltyRisk,
        // Aliases consumed by the mobile analytics screen.
        riskScore: riskReport.length > 0
          ? Math.min(100, Math.round(totalPenaltyRisk / Math.max(1, riskReport.length) / 5)) : 0,
        riskLevel: totalPenaltyRisk >= 500 ? 'high' : totalPenaltyRisk >= 200 ? 'medium' : 'low',
        atRiskWorkers: riskReport.filter(r => r.overdueCount > 0 || r.missedCount > 0).length,
        penaltiesPending: riskReport.length
      };
    } catch (error) {
      logger.error('ObhsAnalyticsService', 'getPenaltyRisk error', error);
      throw error;
    }
  }

  async getComprehensiveReport(runInstanceId) {
    try {
      if (!runInstanceId) throw new ValidationError('runInstanceId is required.');

      const runDoc = await db.collection('RunInstance').doc(runInstanceId).get();
      if (!runDoc.exists) throw new NotFoundError('RunInstance not found.');
      const runData = runDoc.data();

      const [
        attendSnap, taskSnap, complaintSnap, ratingSnap,
        waterSnap, safetySnap, repairSnap, taskDetailsSnap
      ] = await Promise.all([
        db.collection('obhs_attendance').where('runInstanceId', '==', runInstanceId).limit(200).get(),
        db.collection('obhs_tasks').where('runInstanceId', '==', runInstanceId).limit(200).get(),
        db.collection('obhs_complaints').where('runInstanceId', '==', runInstanceId).limit(200).get(),
        db.collection('obhs_feedbacks').where('runInstanceId', '==', runInstanceId).limit(200).get(),
        db.collection('water_checks').where('runInstanceId', '==', runInstanceId).limit(200).get(),
        db.collection('safety_checks').where('runInstanceId', '==', runInstanceId).limit(200).get(),
        db.collection('petty_repairs').where('runInstanceId', '==', runInstanceId).limit(200).get(),
        db.collection('task_details').where('runInstanceId', '==', runInstanceId).limit(200).get()
      ]);

      const attendance = { total: 0, present: 0, late: 0, missed: 0, records: [] };
      attendSnap.forEach(doc => {
        const d = doc.data();
        attendance.total++;
        if (d.status === 'LATE') attendance.late++;
        else if (d.status === 'PRESENT') attendance.present++;
        attendance.records.push({
          workerName: d.workerName,
          status: d.status,
          lateByMinutes: d.lateByMinutes
        });
      });

      const tasks = { total: 0, completed: 0, overdue: 0, missed: 0 };
      taskSnap.forEach(doc => {
        const d = doc.data();
        tasks.total++;
        if (d.status === 'COMPLETED' || d.status === 'APPROVED') tasks.completed++;
        else if (d.status === 'OVERDUE') tasks.overdue++;
        else tasks.missed++;
      });

      const complaints = { total: 0, open: 0, resolved: 0 };
      complaintSnap.forEach(doc => {
        const d = doc.data();
        complaints.total++;
        if (d.status === 'OPEN') complaints.open++;
        else complaints.resolved++;
      });

      const ratings = { total: 0, sum: 0, average: 0 };
      ratingSnap.forEach(doc => {
        const d = doc.data();
        ratings.total++;
        ratings.sum += (d.passengerScore || d.officialScore || 0);
      });
      if (ratings.total > 0) ratings.average = parseFloat((ratings.sum / ratings.total).toFixed(2));

      const waterStats = { total: 0, lowWaterAlerts: 0 };
      waterSnap.forEach(doc => {
        const d = doc.data();
        waterStats.total++;
        if (d.lowWaterAlert) waterStats.lowWaterAlerts++;
      });

      const safetyStats = { total: 0, passed: 0, failed: 0 };
      safetySnap.forEach(doc => {
        const d = doc.data();
        safetyStats.total++;
        if (d.status === 'PASS' || d.passed === true) safetyStats.passed++;
        else safetyStats.failed++;
      });

      let repairCount = 0;
      repairSnap.forEach(() => repairCount++);

      const taskDetails = { total: 0, completed: 0, overdue: 0, planned: 0 };
      taskDetailsSnap.forEach(doc => {
        const d = doc.data();
        taskDetails.total++;
        if (d.status === 'COMPLETED') taskDetails.completed++;
        else if (d.status === 'OVERDUE') taskDetails.overdue++;
        else if (d.status === 'PLANNED') taskDetails.planned++;
      });

      const cleanlinessScore = taskDetails.total > 0
        ? parseFloat(((taskDetails.completed / taskDetails.total) * 100).toFixed(1))
        : 0;
      const attendanceRate = attendance.total > 0
        ? parseFloat(((attendance.present / attendance.total) * 100).toFixed(1))
        : 0;
      const taskCompletionRate = tasks.total > 0
        ? parseFloat(((tasks.completed / tasks.total) * 100).toFixed(1))
        : 0;
      const overallScore = parseFloat((
        (cleanlinessScore * 0.3) + (attendanceRate * 0.25) +
        (taskCompletionRate * 0.25) + ((ratings.average / 5) * 100 * 0.2)
      ).toFixed(1));

      const grade = overallScore >= 90 ? 'A' : overallScore >= 75 ? 'B' : overallScore >= 60 ? 'C' : 'D';

      return {
        success: true,
        runInstanceId,
        trainId: runData.parentTrainId,
        trainNo: runData.trainNo,
        date: runData.departureDate,
        division: runData.division,
        zone: runData.zone,
        attendance,
        tasks,
        taskDetails,
        complaints,
        ratings,
        waterStats,
        safetyStats,
        repairCount,
        cleanlinessScore,
        attendanceRate,
        taskCompletionRate,
        overallScore,
        grade
      };
    } catch (error) {
      logger.error('ObhsAnalyticsService', 'getComprehensiveReport error', error);
      throw error;
    }
  }
}

export const obhsAnalyticsService = new ObhsAnalyticsService();
