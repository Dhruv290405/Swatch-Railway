import { scopedLocation } from '../utils/locationScope.js';

/*
 * Required Firestore composite indexes (create in Firebase Console before deploying):
 *  1. Collection `daily_scorecards` – fields: `stationId` ASC, `date` ASC
 *  2. Collection `station_attendance` – fields: `stationId` ASC, `date` ASC
 *  3. Collection `station_feedback` – fields: `stationId` ASC, `createdAt` ASC
 *  4. Collection `complaints` – fields: `stationId` ASC, `createdAt` ASC
 *  5. Collection `station_daily_activities` – fields: `stationId` ASC, `date` ASC
 *  6. Collection `execution_logs` – fields: `stationId` ASC, `date` ASC
 *  7. Collection `email_history` – fields: `stationId` ASC, `sentAt` ASC
 */

import { db, admin } from '../database/index.js';
import { ValidationError } from '../errors/index.js';
import config from '../config/index.js';
import logger from '../logger/index.js';

const CACHE_TTL = 300;
const cache = {};

class DashboardService {
  _cacheKey(prefix, params) {
    return prefix + '_' + JSON.stringify(params);
  }
  _getCached(key) {
    const entry = cache[key];
    if (entry && Date.now() - entry.ts < CACHE_TTL * 1000) return entry.data;
    return null;
  }
  _setCache(key, data) {
    cache[key] = { data, ts: Date.now() };
    if (Object.keys(cache).length > 200) {
      const oldest = Object.entries(cache).sort((a, b) => a[1].ts - b[1].ts)[0][0];
      delete cache[oldest];
    }
  }

  async getDashboardStats(requesterData, query = {}) {
    const { role, userType, zone: userZone, division: userDiv } = requesterData;
    const { zone: queryZone, division: queryDivision } = scopedLocation(requesterData, query);
    const cacheKey = this._cacheKey('stats', { role, userZone, userDiv, queryZone, queryDivision });
    const cached = this._getCached(cacheKey);
    if (cached) return cached;

    const isSuperAdminRole = (role || '').trim().toLowerCase().replace(/_/g, ' ').includes('super admin');
    const filterZone = queryZone || (isSuperAdminRole ? null : userZone);
    const filterDivision = queryDivision || (isSuperAdminRole ? null : userDiv);

    const [userSnap, entitySnap, trainSnap, contractSnap, coachSnap, premisesSnap, ctsSnap] = await Promise.all([
      db.collection('users').get(),
      db.collection('entities').get(),
      db.collection('trains').get(),
      db.collection('contracts').get(),
      (() => { let q = db.collection('coachForms'); if (filterZone) q = q.where('submittedByZone', '==', filterZone); if (filterDivision) q = q.where('submittedByDivision', '==', filterDivision); return q.get(); })(),
      (() => { let q = db.collection('premisesForms'); if (filterZone) q = q.where('submittedByZone', '==', filterZone); if (filterDivision) q = q.where('submittedByDivision', '==', filterDivision); return q.get(); })(),
      (() => { let q = db.collection('ctsForms'); if (filterZone) q = q.where('submittedByZone', '==', filterZone); if (filterDivision) q = q.where('submittedByDivision', '==', filterDivision); return q.get(); })()
    ]);

    const userRole = (role || '').trim().toLowerCase().replace(/_/g, ' ');
    const isSuperAdmin = userRole.includes('super admin');
    const isMaster = userRole.includes('master');
    const isAdmin = (!userRole.includes("super admin") && userRole.includes("admin")) || userRole.includes("supervisor");

    const stats = {
      user: { total: 0, approved: 0, pending: 0, railway: 0, contractor: 0 },
      entity: { total: 0, approved: 0, pending: 0 },
      train: { total: 0, active: 0 }
    };

    userSnap.docs.forEach(doc => {
      const d = doc.data();
      let visible = isSuperAdmin || (isMaster && d.zone === userZone) || (isAdmin && d.division === userDiv);
      if (filterZone && d.zone && d.zone !== filterZone) visible = false;
      if (filterDivision && d.division && d.division !== filterDivision) visible = false;
      if (visible) {
        stats.user.total++;
        if (d.status === 'APPROVED') stats.user.approved++;
        else if (d.status === 'PENDING') stats.user.pending++;
        if (d.userType === 'railway') stats.user.railway++;
        if (d.userType === 'contractor') stats.user.contractor++;
      }
    });
    entitySnap.docs.forEach(doc => {
      const d = doc.data();
      stats.entity.total++;
      if (d.status === 'APPROVED') stats.entity.approved++;
      if (d.status === 'PENDING') stats.entity.pending++;
    });
    trainSnap.docs.forEach(doc => {
      const d = doc.data();
      let visible = isSuperAdmin || (isMaster && d.zone === userZone) || (isAdmin && d.division === userDiv);
      if (filterZone && d.zone && d.zone !== filterZone) visible = false;
      if (filterDivision && d.division && d.division !== filterDivision) visible = false;
      if (visible) { stats.train.total++; if (d.status === 'ACTIVE' || d.status === 'active') stats.train.active++; }
    });

    const countStatuses = (snapshot) => {
      let total = 0, pending = 0, manpowerApproved = 0, rejected = 0,
          scoringProgress = 0, autoApproved = 0, locked = 0;
      snapshot.forEach(doc => {
        const d = doc.data();
        total++;
        const s = (d.status || '').toUpperCase().replace(/-/g, '_');
        if (['PENDING', 'SUBMITTED', 'RE_SUBMITTED', 'RESUBMITTED', 'DRAFT'].includes(s)) pending++;
        else if (['APPROVED', 'APPROVED_BY_RAILWAY', 'MANPOWER_APPROVED'].includes(s)) manpowerApproved++;
        else if (['REJECTED', 'REJECTED_BY_RAILWAY'].includes(s)) rejected++;
        else if (['SCORING_PROGRESS', 'SCORING_IN_PROGRESS', 'SCORED'].includes(s)) scoringProgress++;
        else if (['AUTO_APPROVED'].includes(s)) autoApproved++;
        else if (['LOCKED', 'ACKNOWLEDGED', 'COMPLETED'].includes(s)) locked++;
      });
      return { total, pending, manpowerApproved, rejected, scoringProgress, autoApproved, locked };
    };

    const coachFormStats = countStatuses(coachSnap);
    const premisesFormStats = countStatuses(premisesSnap);
    const ctsFormStats = countStatuses(ctsSnap);
    const totalForms = coachFormStats.total + premisesFormStats.total + ctsFormStats.total;

    const stationCleaning = await this._getStationCleaningOverview(filterZone, filterDivision);

    const result = {
      systemOverview: {
        railwayEmployees: stats.user.railway, contractorEmployees: stats.user.contractor,
        totalRegisteredEntities: stats.entity.total,
        activeContracts: contractSnap.docs.filter(c => c.data().status === 'ACTIVE').length,
        totalFormsProcessed: totalForms
      },
      userOverview: stats.user, entityOverview: stats.entity, trainOverview: stats.train,
      formsOverview: {
        total: totalForms,
        pending: coachFormStats.pending + premisesFormStats.pending + ctsFormStats.pending,
        manpowerApproved: coachFormStats.manpowerApproved + premisesFormStats.manpowerApproved + ctsFormStats.manpowerApproved,
        rejected: coachFormStats.rejected + premisesFormStats.rejected + ctsFormStats.rejected,
        scoringProgress: coachFormStats.scoringProgress + premisesFormStats.scoringProgress + ctsFormStats.scoringProgress,
        autoApproved: coachFormStats.autoApproved + premisesFormStats.autoApproved + ctsFormStats.autoApproved,
        locked: coachFormStats.locked + premisesFormStats.locked + ctsFormStats.locked
      },
      stationCleaning
    };
    this._setCache(cacheKey, result);
    return result;
  }

  async _getStationCleaningOverview(filterZone, filterDivision) {
    const todayIST = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' });
    let stationQuery = db.collection('stations');
    if (filterZone) stationQuery = stationQuery.where('zone', '==', filterZone);
    const [stationSnap, areaSnap, taskSnap, shiftSnap] = await Promise.all([
      stationQuery.get(),
      db.collection('stationAreas').get(),
      db.collection('cleaningTasks').where('scheduledDate', '==', todayIST).get(),
      db.collection('stationShiftSummaries').get(),
    ]);
    let stationData = stationSnap.docs.map(d => d.data());
    if (filterDivision) stationData = stationData.filter(s => s.division === filterDivision);
    let tasksToday = 0, tasksPending = 0, tasksCompleted = 0, tasksInProgress = 0;
    taskSnap.docs.forEach(doc => {
      const st = (doc.data().status || '').toLowerCase();
      tasksToday++;
      if (st === 'pending' || st === 'assigned') tasksPending++;
      else if (st === 'completed') tasksCompleted++;
      else if (st === 'in_progress' || st === 'started') tasksInProgress++;
    });
    let pendingShiftSummaries = 0;
    shiftSnap.docs.forEach(doc => {
      if ((doc.data().status || '').toLowerCase() === 'pending') pendingShiftSummaries++;
    });
    return {
      totalStations: stationData.length,
      totalAreas: areaSnap.size,
      tasksToday,
      tasksPending,
      tasksCompleted,
      tasksInProgress,
      pendingShiftSummaries,
    };
  }

  async getRailwayDashboardStats(requesterData) {
    const { uid: userId, role, division: userDivision, entityId: userEntityId } = requesterData;
    const cacheKey = this._cacheKey('railStats', { role, userDivision, userEntityId });
    const cached = this._getCached(cacheKey);
    if (cached) return cached;

    const [divisionsSnap, depotsSnap, usersSnap, companiesSnap, contractsSnap, formsSnap] = await Promise.all([
      db.collection('divisions').get(), db.collection('depots').get(),
      db.collection('users').get(), db.collection('companies').get(),
      db.collection('contracts').get(), db.collection('forms_processed').get()
    ]);
    const allUsers = usersSnap.docs.map(d => ({ id: d.id, ...d.data() }));
    const allContracts = contractsSnap.docs.map(d => ({ id: d.id, ...d.data() }));
    const allDepots = depotsSnap.docs.map(d => ({ id: d.id, ...d.data() }));

    let stats = { divisions: 0, depots: 0, railwayEmployees: 0, contractorEmployees: 0,
      registeredEntities: 0, activeContracts: 0, totalFormProcessed: formsSnap.size };
    const nr = (role || "").toLowerCase().replace(/_/g, " ");

    if (nr === 'admin' || (nr === "super_admin" || nr === "super admin")) {
      stats.divisions = divisionsSnap.size;
      stats.depots = depotsSnap.size;
      stats.registeredEntities = companiesSnap.size;
      stats.railwayEmployees = allUsers.filter(u => u.userType === 'railway' || (u.role || '').toLowerCase().includes('railway')).length;
      stats.contractorEmployees = allUsers.filter(u => u.userType === 'contractor').length;
      stats.activeContracts = allContracts.filter(c => c.status === 'Active' || c.status === 'active').length;
    } else if (nr.includes('railway') || nr.includes('supervisor')) {
      stats.divisions = userDivision ? 1 : 0;
      stats.depots = allDepots.filter(d => d.division === userDivision).length;
      stats.railwayEmployees = allUsers.filter(u => u.division === userDivision && (u.userType === 'railway' || (u.role || '').toLowerCase().includes('railway'))).length;
      stats.contractorEmployees = allUsers.filter(u => u.division === userDivision && u.userType === 'contractor').length;
      stats.activeContracts = allContracts.filter(c => c.division === userDivision && (c.status === 'Active' || c.status === 'active')).length;
      stats.totalFormProcessed = formsSnap.docs.filter(f => f.data().division === userDivision).length;
    } else if (nr.includes('company')) {
      stats.registeredEntities = 1;
      stats.contractorEmployees = allUsers.filter(u => u.entityId === userEntityId).length;
      stats.activeContracts = allContracts.filter(c => c.entityId === userEntityId && (c.status === 'Active' || c.status === 'active')).length;
      const myContracts = allContracts.filter(c => c.entityId === userEntityId);
      stats.divisions = [...new Set(myContracts.map(c => c.division))].length;
      stats.depots = [...new Set(myContracts.map(c => c.depot))].length;
    }

    const result = { success: true, data: stats };
    this._setCache(cacheKey, result);
    return result;
  }

  async getAdminDashboard() {
    const cacheKey = this._cacheKey('adminDash', {});
    const cached = this._getCached(cacheKey);
    if (cached) return cached;

    const [stationsSnap, zonesSnap, platformsSnap, areasSnap, stationAreasSnap, tasksSnap, usersSnap] = await Promise.all([
      db.collection('stations').get(),
      db.collection('zones').get(),
      db.collection('platforms').get(),
      db.collection('areas').get(),
      db.collection('stationAreas').get(),
      db.collection('cleaningTasks').limit(1000).get(),
      db.collection('users').get()
    ]);

    const tasks = [];
    tasksSnap.forEach(d => tasks.push(d.data()));
    const totalTasks = tasks.length;
    const pendingTasks = tasks.filter(t => t.status === 'pending').length;
    const inProgressTasks = tasks.filter(t => t.status === 'in_progress').length;
    const completedTasks = tasks.filter(t => t.status === 'completed').length;
    const approvedTasks = tasks.filter(t => t.status === 'approved').length;
    const rejectedTasks = tasks.filter(t => t.status === 'rejected').length;

    const zones = [];
    zonesSnap.forEach(d => zones.push({ id: d.id, ...d.data() }));
    const stations = [];
    stationsSnap.forEach(d => stations.push({ id: d.id, ...d.data() }));

    const zoneSummaries = zones.map(z => ({
      zoneId: z.id,
      zoneName: z.name || z.zoneName || '',
      stationCount: stations.filter(s => s.zoneId === z.id || s.zone === z.id).length
    }));

    const users = [];
    usersSnap.forEach(d => users.push(d.data()));
    const totalWorkers = users.filter(u => u.userType === 'contractor' || u.role === 'CLEANING_STAFF' || u.role === 'WORKER').length;
    const totalSupervisors = users.filter(u => u.role === 'SUPERVISOR' || u.role === 'RAILWAY_SUPERVISOR' || u.role === 'CONTRACTOR_SUPERVISOR').length;

    const uniqueAreaIds = new Set();
    areasSnap.forEach(doc => uniqueAreaIds.add(doc.id));
    stationAreasSnap.forEach(doc => uniqueAreaIds.add(doc.id));

    const result = {
      level: 'admin',
      summary: {
        totalZones: zones.length,
        totalStations: stations.length,
        totalPlatforms: platformsSnap.size,
        totalAreas: uniqueAreaIds.size,
        totalWorkers,
        totalSupervisors
      },
      cleaningTasks: {
        total: totalTasks,
        pending: pendingTasks,
        inProgress: inProgressTasks,
        completed: completedTasks,
        approved: approvedTasks,
        rejected: rejectedTasks
      },
      zones: zoneSummaries
    };
    this._setCache(cacheKey, result);
    return result;
  }

  async getZoneDashboard(zoneId) {
    if (!zoneId) throw new ValidationError('zoneId is required');
    const cacheKey = this._cacheKey('zoneDash', { zoneId });
    const cached = this._getCached(cacheKey);
    if (cached) return cached;

    const [stationsSnap, zoneSnap] = await Promise.all([
      db.collection('stations').where('zoneId', '==', zoneId).get(),
      db.collection('zones').doc(zoneId).get()
    ]);

    const zoneData = zoneSnap.exists ? zoneSnap.data() : {};
    const stations = [];
    stationsSnap.forEach(d => stations.push({ id: d.id, ...d.data() }));

    const stationSummaries = await Promise.all(stations.map(async s => {
      const [platSnap, taskSnap] = await Promise.all([
        db.collection('platforms').where('stationId', '==', s.id).get(),
        db.collection('cleaningTasks').where('stationId', '==', s.id).where('scheduledDate', '==', new Date().toISOString().split('T')[0]).limit(200).get()
      ]);
      const todayTasks = [];
      taskSnap.forEach(d => todayTasks.push(d.data()));
      return {
        stationId: s.id,
        stationName: s.name || s.stationName || '',
        stationCode: s.stationCode || '',
        platformCount: platSnap.size,
        todayTasks: {
          total: todayTasks.length,
          pending: todayTasks.filter(t => t.status === 'pending').length,
          inProgress: todayTasks.filter(t => t.status === 'in_progress').length,
          completed: todayTasks.filter(t => t.status === 'completed').length,
          approved: todayTasks.filter(t => t.status === 'approved').length
        }
      };
    }));

    const result = {
      level: 'zone',
      zoneId,
      zoneName: zoneData.name || zoneData.zoneName || '',
      stationCount: stations.length,
      stations: stationSummaries
    };
    this._setCache(cacheKey, result);
    return result;
  }

  async _safeQuery(fn) {
    try { return await fn(); } catch (e) {
      const code = e.code;
      if (code === 9 || (typeof code === 'string' && ['failed_precondition', 'FAILED_PRECONDITION'].includes(code)) || (e.message && e.message.includes('FAILED_PRECONDITION'))) {
        logger.warn('Firestore index missing, returning empty snapshot');
        return { forEach: () => {}, empty: true, size: 0, docs: [], exists: false, data: () => ({}) };
      }
      throw e;
    }
  }

  async getStationDashboard(stationId, query = {}) {
    if (!stationId) throw new ValidationError('stationId is required');
    const { startDate, endDate, month, year } = query;
    let sDate, eDate;
    if (month && year) {
      const m = String(month).padStart(2, '0');
      sDate = `${year}-${m}-01`; eDate = `${year}-${m}-31`;
    } else {
      sDate = startDate || new Date(Date.now() - 30 * 86400000).toISOString().split('T')[0];
      eDate = endDate || new Date().toISOString().split('T')[0];
    }

    const cacheKey = this._cacheKey('stnDash', { stationId, sDate, eDate });
    const cached = this._getCached(cacheKey);
    if (cached) return cached;

    const safe = (fn) => this._safeQuery(fn);
    const [scoreSnap, attendSnap, feedbackSnap, passengerFeedbackSnap, complaintSnap, machineSnap, actSnap, logSnap, freqSnap, billingSnap, emailSnap, platSnap, stationSnap, tasksSnap] = await Promise.all([
      safe(() => db.collection('daily_scorecards').where('stationId', '==', stationId).where('date', '>=', sDate).where('date', '<=', eDate).get()),
      safe(() => db.collection('station_attendance').where('stationId', '==', stationId).where('date', '>=', sDate).where('date', '<=', eDate).get()),
      safe(() => db.collection('station_feedback').where('stationId', '==', stationId).where('createdAt', '>=', sDate).where('createdAt', '<=', eDate + 'T23:59:59').get()),
      safe(() => db.collection('passenger_feedback').where('stationId', '==', stationId).where('createdAt', '>=', sDate).where('createdAt', '<=', eDate + 'T23:59:59').get()),
      safe(() => db.collection('complaints').where('stationId', '==', stationId).where('createdAt', '>=', sDate).where('createdAt', '<=', eDate + 'T23:59:59').get()),
      safe(() => db.collection('machines').where('stationId', '==', stationId).get()),
      safe(() => db.collection('station_daily_activities').where('stationId', '==', stationId).where('date', '>=', sDate).where('date', '<=', eDate).get()),
      safe(() => db.collection('execution_logs').where('stationId', '==', stationId).where('date', '>=', sDate).where('date', '<=', eDate).get()),
      safe(() => db.collection('activity_frequencies').where('stationId', '==', stationId).get()),
      safe(() => db.collection('station_billing_packs').where('stationId', '==', stationId).get()),
      safe(() => db.collection('email_history').where('stationId', '==', stationId).get()),
      safe(() => db.collection('platforms').where('stationId', '==', stationId).get()),
      safe(() => db.collection('stations').doc(stationId).get()),
      safe(() => db.collection('cleaningTasks').where('stationId', '==', stationId).where('scheduledDate', '>=', sDate).where('scheduledDate', '<=', eDate).limit(500).get())
    ]);

    const stationData = stationSnap.exists ? stationSnap.data() : {};

    const scores = []; scoreSnap.forEach(d => scores.push(d.data()));
    const avgScore = scores.length > 0 ? Math.round(scores.reduce((s, c) => s + (c.overallStationScore || 0), 0) / scores.length) : 0;
    const scoreTrend = scores.sort((a, b) => a.date.localeCompare(b.date)).map(c => ({ date: c.date, score: c.overallStationScore, grade: c.grade }));

    const attendance = []; attendSnap.forEach(d => attendance.push(d.data()));
    const present = attendance.filter(r => r.status === 'present' || r.status === 'late').length;
    const absent = attendance.filter(r => r.status === 'absent').length;

    const feedbacks = []; feedbackSnap.forEach(d => feedbacks.push(d.data()));
    passengerFeedbackSnap.forEach(d => {
      const r = d.data();
      if (r.status === 'CANCELLED') return;
      feedbacks.push({ ...r, rating: r.overallRating || 0 });
    });
    const avgFeedback = feedbacks.length > 0 ? Math.round(feedbacks.reduce((s, f) => s + (f.rating || 0), 0) / feedbacks.length * 10) / 10 : 0;

    const complaints = []; complaintSnap.forEach(d => complaints.push(d.data()));
    const openComplaints = complaints.filter(c => !['CLOSED', 'RAILWAY_VERIFIED', 'REJECTED'].includes(c.status)).length;

    const machines = []; machineSnap.forEach(d => machines.push(d.data()));
    const inMaintenance = machines.filter(m => m.workingStatus === 'under_maintenance' || m.workingStatus === 'broken').length;

    const activities = []; actSnap.forEach(d => activities.push(d.data()));
    const completedActs = activities.filter(a => a.status === 'COMPLETED' || a.status === 'APPROVED').length;

    const execLogs = []; logSnap.forEach(d => execLogs.push(d.data()));
    const plannedManpower = execLogs.reduce((s, l) => s + (l.plannedManpower || 0), 0);
    const actualManpower = execLogs.reduce((s, l) => s + (l.actualManpower || 0), 0);

    const frequencies = []; freqSnap.forEach(d => frequencies.push(d.data()));
    const missedAlerts = frequencies.filter(f => {
      if (!f.frequency || !f.lastCompletedDate) return false;
      const last = new Date(f.lastCompletedDate);
      const now = new Date();
      const daysSinceLast = (now - last) / 86400000;
      if (f.frequency === 'daily' && daysSinceLast > 1.5) return true;
      if (f.frequency === 'weekly' && daysSinceLast > 8) return true;
      if (f.frequency === 'monthly' && daysSinceLast > 32) return true;
      return false;
    }).length;

    const billingPacks = []; billingSnap.forEach(d => billingPacks.push(d.data()));
    const billingReady = billingPacks.filter(b => b.status === 'SUBMITTED' || b.status === 'APPROVED').length;
    const billingDraft = billingPacks.filter(b => b.status === 'DRAFT').length;

    const emailLogs = []; emailSnap.forEach(d => emailLogs.push(d.data()));
    const reportsSent = emailLogs.length;

    const platforms = [];
    platSnap.forEach(d => platforms.push({ id: d.id, ...d.data() }));

    const tasks = [];
    tasksSnap.forEach(d => tasks.push(d.data()));
    const cleaningStats = {
      total: tasks.length,
      pending: tasks.filter(t => t.status === 'pending').length,
      inProgress: tasks.filter(t => t.status === 'in_progress').length,
      completed: tasks.filter(t => t.status === 'completed').length,
      approved: tasks.filter(t => t.status === 'approved').length,
      rejected: tasks.filter(t => t.status === 'rejected').length
    };

    const platformSummaries = platforms.map(p => ({
      platformId: p.id,
      platformName: p.name || p.platformName || '',
      platformNumber: p.platformNumber || ''
    }));

    const result = {
      level: 'station',
      stationId,
      stationName: stationData.name || stationData.stationName || '',
      stationCode: stationData.stationCode || '',
      period: { start: sDate, end: eDate },
      scorecard: { daysWithScore: scores.length, averageScore: avgScore, trend: scoreTrend },
      attendance: { total: attendance.length, present, absent, attendanceRate: attendance.length > 0 ? Math.round(present / attendance.length * 100) : 0 },
      feedback: { total: feedbacks.length, averageRating: avgFeedback, negative: feedbacks.filter(f => f.isNegative).length },
      complaints: { total: complaints.length, open: openComplaints, closed: complaints.filter(c => c.status === 'CLOSED').length },
      machines: { total: machines.length, inMaintenance, operational: machines.length - inMaintenance },
      activities: { total: activities.length, completed: completedActs, completionRate: activities.length > 0 ? Math.round(completedActs / activities.length * 100) : 0 },
      plannedVsCompleted: { planned: plannedManpower, actual: actualManpower, variance: plannedManpower - actualManpower },
      missedAlerts: { count: missedAlerts, alert: missedAlerts > 0 },
      billingReadiness: { total: billingPacks.length, ready: billingReady, draft: billingDraft },
      reportsSent: { count: reportsSent },
      cleaning: cleaningStats,
      platforms: platformSummaries
    };
    this._setCache(cacheKey, result);
    return result;
  }

  async getPlatformDashboard(platformId, query = {}) {
    if (!platformId) throw new ValidationError('platformId is required');
    const { startDate, endDate, date } = query;
    const targetDate = date || new Date().toISOString().split('T')[0];

    const cacheKey = this._cacheKey('platDash', { platformId, targetDate });
    const cached = this._getCached(cacheKey);
    if (cached) return cached;

    const [platformSnap, areasSnap, stationAreasSnap, tasksSnap, runsSnap] = await Promise.all([
      db.collection('platforms').doc(platformId).get(),
      db.collection('areas').where('platformId', '==', platformId).get(),
      db.collection('stationAreas').where('platformId', '==', platformId).get(),
      db.collection('cleaningTasks').where('platformId', '==', platformId).where('scheduledDate', '==', targetDate).limit(500).get(),
      db.collection('stationCleaningRuns').where('platformId', '==', platformId).where('date', '==', targetDate).limit(200).get()
    ]);

    const platformData = platformSnap.exists ? platformSnap.data() : {};

    const areas = [];
    areasSnap.forEach(d => areas.push({ id: d.id, ...d.data() }));
    stationAreasSnap.forEach(d => {
      if (!areas.some(a => a.id === d.id)) {
        areas.push({ id: d.id, ...d.data() });
      }
    });

    const tasks = [];
    tasksSnap.forEach(d => tasks.push(d.data()));

    const runs = [];
    runsSnap.forEach(d => runs.push(d.data()));

    const areaSummaries = areas.map(a => ({
      areaId: a.id,
      areaName: a.areaName || a.name || '',
      areaCode: a.areaCode || '',
      cleaningFrequency: a.cleaningFrequency || a.frequency || 'daily',
      defaultShift: a.defaultShift || 'morning',
      workerCount: 0
    }));

    const cleaningStats = {
      total: tasks.length,
      pending: tasks.filter(t => t.status === 'pending').length,
      inProgress: tasks.filter(t => t.status === 'in_progress').length,
      completed: tasks.filter(t => t.status === 'completed').length,
      approved: tasks.filter(t => t.status === 'approved').length,
      rejected: tasks.filter(t => t.status === 'rejected').length
    };

    const result = {
      level: 'platform',
      platformId,
      platformName: platformData.name || platformData.platformName || '',
      platformNumber: platformData.platformNumber || '',
      stationId: platformData.stationId || '',
      date: targetDate,
      areaCount: areas.length,
      runCount: runs.length,
      cleaning: cleaningStats,
      areas: areaSummaries
    };
    this._setCache(cacheKey, result);
    return result;
  }

  async getAreaDashboard(areaId, query = {}) {
    if (!areaId) throw new ValidationError('areaId is required');
    const { startDate, endDate, date } = query;
    const targetDate = date || new Date().toISOString().split('T')[0];

    const cacheKey = this._cacheKey('areaDash', { areaId, targetDate });
    const cached = this._getCached(cacheKey);
    if (cached) return cached;

    const [areaSnap, tasksSnap, assignmentsSnap, runsSnap] = await Promise.all([
      db.collection('areas').doc(areaId).get(),
      db.collection('cleaningTasks').where('areaId', '==', areaId).where('scheduledDate', '==', targetDate).limit(200).get(),
      db.collection('areaWorkerAssignments').where('areaId', '==', areaId).where('isActive', '==', true).get(),
      db.collection('stationCleaningRuns').where('areaId', '==', areaId).where('date', '==', targetDate).limit(100).get()
    ]);

    let areaDoc = areaSnap;
    if (!areaDoc.exists) {
      areaDoc = await db.collection('stationAreas').doc(areaId).get();
    }

    if (!areaDoc.exists) throw new ValidationError('Area not found');
    const areaData = areaDoc.data();

    const tasks = [];
    tasksSnap.forEach(d => tasks.push({ id: d.id, ...d.data() }));

    const assignments = [];
    assignmentsSnap.forEach(d => assignments.push({ id: d.id, ...d.data() }));

    const runs = [];
    runsSnap.forEach(d => runs.push(d.data()));

    const workerSummaries = assignments.map(a => ({
      assignmentId: a.uid || a.id,
      workerId: a.workerId,
      workerName: a.workerName,
      shift: a.shift,
      isPrimary: a.isPrimary || false,
      status: a.status || 'active'
    }));

    const cleaningStats = {
      total: tasks.length,
      pending: tasks.filter(t => t.status === 'pending').length,
      inProgress: tasks.filter(t => t.status === 'in_progress').length,
      completed: tasks.filter(t => t.status === 'completed').length,
      approved: tasks.filter(t => t.status === 'approved').length,
      rejected: tasks.filter(t => t.status === 'rejected').length,
      resubmitted: tasks.filter(t => t.status === 'resubmitted').length
    };

    const result = {
      level: 'area',
      areaId,
      areaName: areaData.areaName || areaData.name || '',
      areaCode: areaData.areaCode || '',
      stationId: areaData.stationId || '',
      platformId: areaData.platformId || '',
      cleaningFrequency: areaData.cleaningFrequency || areaData.frequency || 'daily',
      frequencyTimes: areaData.frequencyTimes || [],
      defaultShift: areaData.defaultShift || 'morning',
      defaultWorkers: areaData.defaultWorkers || 1,
      priority: areaData.priority || 3,
      date: targetDate,
      cleaning: cleaningStats,
      workerCount: workerSummaries.length,
      workers: workerSummaries,
      runs: runs.length,
      scheduledTasks: tasks.map(t => ({
        taskId: t.uid || t.id,
        scheduledTime: t.scheduledTime,
        workerId: t.workerId,
        workerName: t.workerName,
        status: t.status,
        startedAt: t.startedAt,
        completedAt: t.completedAt
      }))
    };
    this._setCache(cacheKey, result);
    return result;
  }

  // Aggregate-only user counts (no user documents leave the server).
  async getUserCounts(query = {}, requester = null) {
    const { zone, division } = scopedLocation(requester, query);
    const depot = query.depot;
    const snap = await db.collection('users').get();
    const zones = new Set();
    const divisions = new Set();
    const depots = new Set();
    let railwayUsers = 0;
    let contractorUsers = 0;
    snap.forEach((doc) => {
      const u = doc.data();
      if (u.zone) zones.add(String(u.zone));
      if (zone && u.zone !== zone) return;
      if (u.division) divisions.add(String(u.division));
      if (division && u.division !== division) return;
      if (u.depot) depots.add(String(u.depot));
      if (depot && u.depot !== depot) return;
      if (u.userType === 'railway') railwayUsers += 1;
      if (u.userType === 'contractor') contractorUsers += 1;
    });
    return { zones: zones.size, divisions: divisions.size, depots: depots.size, railwayUsers, contractorUsers };
  }

  async getUserStats(requesterData = {}, query = {}) {
    const { role, userType, zone: userZone, division: userDiv } = requesterData;
    const { zone, division } = scopedLocation(requesterData, {
      zone: query.selectedZone || query.zone,
      division: query.selectedDivision || query.division,
    });
    const depot = query.selectedDepot || query.depot || null;

    const userRole = (role || '').trim().toLowerCase().replace(/_/g, ' ');
    const isSuperAdmin = userRole.includes('super admin');
    const isMaster = userRole.includes('master');
    const isAdmin = (!userRole.includes('super admin') && userRole.includes('admin')) || userRole.includes('supervisor');

    const filterZone = zone || (isSuperAdmin ? null : userZone);
    const filterDivision = division || (isSuperAdmin ? null : userDiv);

    const snapshot = await db.collection('users').get();
    const users = snapshot.docs.map(d => d.data()).filter(u => {
      if (!isSuperAdmin) {
        if (isMaster && u.zone !== userZone) return false;
        if (isAdmin && u.division !== userDiv) return false;
      }
      if (filterZone && u.zone && u.zone !== filterZone) return false;
      if (filterDivision && u.division && u.division !== filterDivision) return false;
      if (depot && u.depot && u.depot !== depot) return false;
      return true;
    });
    const total = users.length;
    const approved = users.filter(u => u.status === 'APPROVED').length;
    const pending = users.filter(u => u.status === 'PENDING').length;
    const rejected = users.filter(u => u.status === 'REJECTED').length;
    const railway = users.filter(u => u.userType === 'railway').length;
    const contractor = users.filter(u => u.userType === 'contractor').length;
    return {
      total, approved, pending, rejected, railway, contractor,
      data: {
        totalRegistered: total,
        approvedUsers: approved,
        pendingApproval: pending,
        rejectedUsers: rejected,
        railwayStaff: railway,
        contractorStaff: contractor,
      }
    };
  }

  async getTrainStats(requesterData = {}, query = {}) {
    const { role, zone: userZone, division: userDiv } = requesterData;
    const { zone, division } = scopedLocation(requesterData, {
      zone: query.selectedZone || query.zone,
      division: query.selectedDivision || query.division,
    });
    const depot = query.selectedDepot || query.depot || null;

    const userRole = (role || '').trim().toLowerCase().replace(/_/g, ' ');
    const isSuperAdmin = userRole.includes('super admin');
    const isMaster = userRole.includes('master');
    const isAdmin = (!userRole.includes('super admin') && userRole.includes('admin')) || userRole.includes('supervisor');

    const filterZone = zone || (isSuperAdmin ? null : userZone);
    const filterDivision = division || (isSuperAdmin ? null : userDiv);

    const snapshot = await db.collection('trains').get();
    const trains = snapshot.docs.map(d => d.data()).filter(t => {
      if (!isSuperAdmin) {
        if (isMaster && t.zone !== userZone) return false;
        if (isAdmin && t.division !== userDiv) return false;
      }
      if (filterZone && t.zone && t.zone !== filterZone) return false;
      if (filterDivision && t.division && t.division !== filterDivision) return false;
      if (depot && t.depot && t.depot !== depot) return false;
      return true;
    });
    const total = trains.length;
    const active = trains.filter(t => t.status === 'ACTIVE' || t.status === 'active').length;
    const obhsEnabled = trains.filter(t => (t.TrainApplicableFor || []).includes('OBHS')).length;
    const ctsEnabled = trains.filter(t => (t.TrainApplicableFor || []).includes('CTS')).length;
    return {
      total, active, obhsEnabled, ctsEnabled,
      data: {
        totalTrains: total,
        activeTrains: active,
        inactiveTrains: total - active,
        obhsEnabled,
        ctsEnabled,
      }
    };
  }

  async getSupervisorStats(requesterData) {
    const { division } = requesterData;
    const [usersSnap, formsSnap, tasksSnap] = await Promise.all([
      db.collection('users').where('division', '==', division).get(),
      db.collection('coachForms').where('division', '==', division).get(),
      db.collection('obhs_tasks').where('division', '==', division).get()
    ]);
    const users = usersSnap.docs.map(d => d.data());
    const forms = formsSnap.docs.map(d => d.data());
    const tasks = tasksSnap.docs.map(d => d.data());
    return { totalWorkers: users.filter(u => u.userType === 'contractor').length,
      activeForms: forms.filter(f => f.status === 'SUBMITTED' || f.status === 'APPROVED').length,
      pendingReview: tasks.filter(t => t.status === 'PENDING_REVIEW').length,
      completedToday: tasks.filter(t => t.status === 'COMPLETED').length };
  }

  async getActiveTrains() {
    const snapshot = await db.collection('trains').where('status', '==', 'active').get();
    return { count: snapshot.size, trains: snapshot.docs.map(d => ({ uid: d.id, ...d.data() })) };
  }

  async getActiveWorkers(requesterData = {}) {
    let query = db.collection('users').where('userType', '==', 'contractor').where('status', '==', 'APPROVED');
    if (requesterData.userType === 'contractor' && requesterData.domain) {
      query = query.where('domain', '==', requesterData.domain);
    }
    const snapshot = await query.get();
    return { count: snapshot.size, workers: snapshot.docs.map(d => ({ id: d.id, ...d.data() })) };
  }

  async getAllFormsStats(query = {}, requester = null) {
    const { formType, days } = query;
    const { zone, division } = scopedLocation(requester, query);
    // Contractor users only ever see their own company's forms.
    const isContractor = String(requester?.userType || '').toLowerCase() === 'contractor';
    const entityId = (isContractor && requester?.entityId) ? requester.entityId : query.entityId;

    // Helper to count statuses from a Firestore snapshot
    const countStatuses = (snapshot, minDate) => {
      let total = 0, pending = 0, manpowerApproved = 0, rejected = 0,
          scoringProgress = 0, autoApproved = 0, locked = 0;
      snapshot.forEach(doc => {
        const d = doc.data();
        if (minDate && d.createdAt) {
          if (new Date(d.createdAt) < minDate) return;
        }
        total++;
        const s = (d.status || '').toUpperCase().replace(/-/g, '_');
        if (['PENDING', 'SUBMITTED', 'RE_SUBMITTED', 'RESUBMITTED', 'DRAFT'].includes(s)) pending++;
        else if (['APPROVED', 'APPROVED_BY_RAILWAY', 'MANPOWER_APPROVED'].includes(s)) manpowerApproved++;
        else if (['REJECTED', 'REJECTED_BY_RAILWAY'].includes(s)) rejected++;
        else if (['SCORING_PROGRESS', 'SCORING_IN_PROGRESS', 'SCORED'].includes(s)) scoringProgress++;
        else if (['AUTO_APPROVED'].includes(s)) autoApproved++;
        else if (['LOCKED', 'ACKNOWLEDGED', 'COMPLETED'].includes(s)) locked++;
      });
      return { total, pending, manpowerApproved, rejected, scoringProgress, autoApproved, locked };
    };

    const now = new Date();
    const minDate = days ? new Date(now.setDate(now.getDate() - parseInt(days))) : null;

    // Map formType to its Firestore collection
    const getCollection = (type) => {
      if (type === 'coach') return 'coachForms';
      if (type === 'premises' || type === 'premise') return 'premisesForms';
      if (type === 'cts') return 'ctsForms';
      return 'cleaningForms';
    };

    const buildQuery = (collectionName) => {
      let q = db.collection(collectionName);
      // All form collections use submittedByZone / submittedByDivision / submittedByEntityId
      if (zone) q = q.where('submittedByZone', '==', zone);
      if (division) q = q.where('submittedByDivision', '==', division);
      if (entityId) q = q.where('submittedByEntityId', '==', entityId);
      return q;
    };

    if (!formType) {
      // Return counts per type when no formType specified
      const [coachSnap, premisesSnap, ctsSnap] = await Promise.all([
        buildQuery('coachForms').select('status', 'createdAt').get(),
        buildQuery('premisesForms').select('status', 'createdAt').get(),
        buildQuery('ctsForms').select('status', 'createdAt').get(),
      ]);
      const coachStats = countStatuses(coachSnap, minDate);
      const premisesStats = countStatuses(premisesSnap, minDate);
      const ctsStats = countStatuses(ctsSnap, minDate);
      return {
        coachForms: coachStats.total,
        premisesForms: premisesStats.total,
        ctsForms: ctsStats.total,
        total: coachStats.total + premisesStats.total + ctsStats.total
      };
    }

    const collectionName = getCollection(formType);
    const snapshot = await buildQuery(collectionName).select('status', 'createdAt').get();
    return countStatuses(snapshot, minDate);
  }
}

export const dashboardService = new DashboardService();
