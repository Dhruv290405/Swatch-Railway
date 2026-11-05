/*
 * Required Firestore composite indexes:
 *  1. `station_billing_packs` – `contractId` ASC, `stationId` ASC, `month` ASC, `year` ASC
 *  2. `station_billing_packs` – `stationId` ASC, `createdAt` DESC
 *  3. `machine_downtime` – `stationId` ASC, `startTime` ASC
 *  4. `inspections` – `stationId` ASC, `createdAt` ASC
 */

import { db, admin } from '../database/index.js';
import { NotFoundError, ValidationError } from '../errors/index.js';
import logger from '../logger/index.js';
import { auditService } from './auditService.js';
import { executionSheetService } from './executionSheetService.js';
import { contractEstimationService } from './contractEstimationService.js';
import { isActiveStatus } from '../utils/monthlyBill.js';

class StationBillingService {
  async generateBillingSupportPack(user, data) {
    const { contractId, stationId, month, year } = data;
    if (!contractId || !stationId || !month || !year) throw new ValidationError('contractId, stationId, month, and year are required');

    const contractDoc = await db.collection('contracts').doc(contractId).get();
    if (!contractDoc.exists) throw new NotFoundError('Contract not found');
    const contractData = contractDoc.data();
    const stationDoc = await db.collection('stations').doc(stationId).get();
    if (!stationDoc.exists) throw new NotFoundError('Station not found');
    const stationName = stationDoc.data().stationName || '';

    const monthPad = String(month).padStart(2, '0');
    const startDate = `${year}-${monthPad}-01`;
    const lastDay = new Date(parseInt(year), parseInt(month), 0).getDate();
    const endDate = `${year}-${monthPad}-${String(lastDay).padStart(2, '0')}`;

    const existingSnap = await db.collection('station_billing_packs')
      .where('contractId', '==', contractId).where('stationId', '==', stationId)
      .where('month', '==', parseInt(month)).where('year', '==', parseInt(year)).limit(5).get();
    const existingPacks = []; existingSnap.forEach(d => existingPacks.push({ id: d.id, ...d.data() }));
    const existingPack = existingPacks.find(p => p.status !== 'DELETED');
    if (existingPack) return { message: 'Existing billing support pack returned', uid: existingPack.id, pack: existingPack };

    const [attendanceSnap, cleaningAttSnap, activitySnap, scorecardSnap, complaintSnap, feedbackSnap, passengerFeedbackSnap, inspectionSnap, machineSnap, downtimeSnap, stationRunSnap, formsSnap] = await Promise.all([
      db.collection('station_attendance').where('stationId', '==', stationId).get(),
      db.collection('station_cleaning_attendance').where('stationId', '==', stationId).get(),
      db.collection('cleaningTasks').where('stationId', '==', stationId).get(),
      db.collection('daily_scorecards').where('stationId', '==', stationId).get(),
      db.collection('complaints').where('stationId', '==', stationId).get(),
      db.collection('station_feedback').where('stationId', '==', stationId).get(),
      db.collection('passenger_feedback').where('stationId', '==', stationId).get(),
      db.collection('inspections').where('stationId', '==', stationId).get(),
      db.collection('machines').where('stationId', '==', stationId).get(),
      db.collection('machine_downtime').where('stationId', '==', stationId).get(),
      db.collection('stationRuns').where('stationId', '==', stationId).get(),
      db.collection('stationCleaningForms').where('stationId', '==', stationId).get(),
    ]);

    const allAttendance = []; attendanceSnap.forEach(d => { const r = d.data(); if (r.date >= startDate && r.date <= endDate) allAttendance.push(r); });
    const cleaningAtt = []; cleaningAttSnap.forEach(d => { const r = d.data(); const d2 = r.date || (r.createdAt || '').substring(0, 10); if (d2 >= startDate && d2 <= endDate) cleaningAtt.push({ ...r, status: r.attendanceStatus === 'LATE' ? 'late' : 'present' }); });
    const attendanceRecords = [...allAttendance, ...cleaningAtt];
    const presentCount = attendanceRecords.filter(r => ['present', 'late'].includes(r.status)).length;
    const uniqueDates = [...new Set(attendanceRecords.map(r => r.date))].length;
    const attendanceSummary = { totalDaysRecorded: uniqueDates, totalAttendanceEntries: attendanceRecords.length, totalPresent: presentCount, totalAbsent: attendanceRecords.filter(r => r.status === 'absent').length, averageDailyManpower: uniqueDates > 0 ? Math.round(presentCount / uniqueDates) : 0, attendancePercentage: attendanceRecords.length > 0 ? Math.round(presentCount / attendanceRecords.length * 100) : 0 };

    const activities = []; activitySnap.forEach(d => { const r = d.data(); const d2 = r.scheduledDate || r.date || ''; if (d2 >= startDate && d2 <= endDate) activities.push(r); });
    const actSummary = { total: activities.length, APPROVED: 0, COMPLETED: 0, REJECTED: 0, PENDING: 0, IN_PROGRESS: 0, PARTIALLY_COMPLETED: 0, RESUBMITTED: 0 };
    activities.forEach(a => { const s = (a.status || '').toUpperCase(); if (actSummary[s] !== undefined) actSummary[s]++; });
    const activityCompletionRate = actSummary.total > 0 ? Math.round((actSummary.APPROVED + actSummary.COMPLETED) / actSummary.total * 100) : 0;

    const scorecards = []; scorecardSnap.forEach(d => { const r = d.data(); if (r.date >= startDate && r.date <= endDate) scorecards.push(r); });
    const totalScore = scorecards.reduce((s, c) => s + (c.overallStationScore || 0), 0);
    const avgScore = scorecards.length > 0 ? Math.round(totalScore / scorecards.length * 10) / 10 : 0;
    const gradeMap = {}; scorecards.forEach(c => { const g = c.grade || 'N/A'; gradeMap[g] = (gradeMap[g] || 0) + 1; });
    const scorecardSummary = { daysWithScorecard: scorecards.length, averageScore: avgScore, gradeDistribution: gradeMap, certified: scorecards.every(c => c.certified) };

    const complaints = []; complaintSnap.forEach(d => { const r = d.data(); const ts = r.createdAt || ''; if (ts >= startDate && ts <= endDate + 'T23:59:59') complaints.push(r); });
    const cmpSummary = { total: complaints.length, closed: complaints.filter(c => c.status === 'CLOSED').length, open: complaints.filter(c => ['REPORTED', 'ASSIGNED', 'IN_PROGRESS'].includes(c.status)).length, rejected: complaints.filter(c => c.status === 'REJECTED').length };

    const feedbackRecords = []; feedbackSnap.forEach(d => { const r = d.data(); const ts = r.createdAt || ''; if (ts >= startDate && ts <= endDate + 'T23:59:59') feedbackRecords.push(r); });
    passengerFeedbackSnap.forEach(d => {
      const r = d.data();
      if (r.status === 'CANCELLED') return;
      const ts = r.createdAt || '';
      if (ts >= startDate && ts <= endDate + 'T23:59:59') {
        const rating = r.overallRating || 0;
        feedbackRecords.push({ ...r, rating, isNegative: r.isNegative || rating <= 2 });
      }
    });
    const totalRating = feedbackRecords.reduce((s, f) => s + (f.rating || 0), 0);
    const feedbackSummary = { totalFeedbacks: feedbackRecords.length, averageRating: feedbackRecords.length > 0 ? Math.round(totalRating / feedbackRecords.length * 10) / 10 : 0, negativeFeedbacks: feedbackRecords.filter(f => f.isNegative).length };

    const inspections = []; inspectionSnap.forEach(d => { const r = d.data(); const ts = r.createdAt || ''; if (ts >= startDate && ts <= endDate + 'T23:59:59') inspections.push(r); });
    const totalDeficiencies = inspections.reduce((s, i) => s + (i.deficiencies || []).length, 0);
    const closedDeficiencies = inspections.reduce((s, i) => s + ((i.deficiencies || []).filter(d => d.status === 'CLOSED' || d.status === 'VERIFIED').length), 0);
    const inspectionScoreSummary = inspections.map(i => ({ id: i.id || '', type: i.inspectionType || '', score: i.overallScore ?? null, status: i.status || '', date: i.inspectionDate || i.createdAt || '' }));
    const inspectionSummary = { totalInspections: inspections.length, totalDeficiencies, closedDeficiencies, openDeficiencies: totalDeficiencies - closedDeficiencies, inspectionTypes: [...new Set(inspections.map(i => i.inspectionType || 'standard'))].length, averageScore: inspections.length > 0 ? Math.round(inspections.reduce((s, i) => s + (i.overallScore || 0), 0) / inspections.length) : 0, scores: inspectionScoreSummary };

    // ── Petty issue summary (from complaints with petty_issue category) ──
    const pettyIssues = complaints.filter(c => (c.category || '').toLowerCase().includes('petty') || c.type === 'petty_issue');
    const pettyIssueSummary = { total: pettyIssues.length, resolved: pettyIssues.filter(c => c.status === 'CLOSED' || c.status === 'RESOLVED').length, open: pettyIssues.filter(c => ['REPORTED', 'ASSIGNED', 'IN_PROGRESS'].includes(c.status)).length };

    // ── Photo evidence summary ──
    const forms = []; formsSnap.forEach(d => { const r = d.data(); const ts = r.createdAt || ''; if (ts >= startDate && ts <= endDate + 'T23:59:59') forms.push(r); });
    const formsWithPhotos = forms.filter(f => {
      const photos = f.photos || f.photoEvidence || f.beforePhotos || f.afterPhotos || [];
      return photos.length > 0;
    });
    const totalPhotos = forms.reduce((s, f) => {
      const photos = f.photos || f.photoEvidence || f.beforePhotos || f.afterPhotos || [];
      return s + photos.length;
    }, 0);
    const evidenceSummary = { totalForms: forms.length, formsWithPhotos: formsWithPhotos.length, totalPhotos, evidenceComplianceRate: forms.length > 0 ? Math.round(formsWithPhotos.length / forms.length * 100) : 0 };

    const downtimeRecords = []; downtimeSnap.forEach(d => { const r = d.data(); const ts = r.startTime || ''; if (ts >= startDate && ts <= endDate + 'T23:59:59') downtimeRecords.push(r); });
    const totalDowntimeHours = downtimeRecords.reduce((s, d) => s + (d.totalDowntimeHours || 0), 0);
    const totalMachinePenalty = downtimeRecords.reduce((s, d) => s + (d.penaltyAmount || 0), 0);
    const machineDowntimeSummary = { incidents: downtimeRecords.length, totalHours: totalDowntimeHours, totalPenalty: totalMachinePenalty };

    const billingRuleSnap = await db.collection('billingRules').where('contractId', '==', contractId).limit(1).get();
    const extraPenalties = [];
    let extraPenaltyAmount = 0;
    const monthlyBase = (contractData.contractValue || 0) / 12;

    if (!billingRuleSnap.empty) {
      const rules = billingRuleSnap.docs[0].data();
      if (attendanceSummary.attendancePercentage < 90 && rules.attendancePenaltyRate) {
        const amt = Math.round(((90 - attendanceSummary.attendancePercentage) / 100) * monthlyBase * (rules.attendancePenaltyRate || 0.01));
        extraPenalties.push({ reason: 'Attendance Shortfall', percentage: 90 - attendanceSummary.attendancePercentage, amount: amt });
        extraPenaltyAmount += amt;
      }
      if (avgScore < 70 && rules.scorePenaltyRate) {
        const amt = Math.round(((70 - avgScore) / 100) * monthlyBase * (rules.scorePenaltyRate || 0.02));
        extraPenalties.push({ reason: 'Score Below 70%', percentage: 70 - avgScore, amount: amt });
        extraPenaltyAmount += amt;
      }
    }

    if (machineDowntimeSummary.totalPenalty > 0) {
      extraPenalties.push({ reason: 'Machine Downtime Penalty', percentage: 0, amount: machineDowntimeSummary.totalPenalty });
      extraPenaltyAmount += machineDowntimeSummary.totalPenalty;
    }
    
    // 20% Supervisor Approval Deduction
    const stationRuns = []; 
    if (stationRunSnap) stationRunSnap.forEach(d => { const r = d.data(); if (r.date >= startDate && r.date <= endDate) stationRuns.push(r); });
    
    const unapprovedRuns = stationRuns.filter(r => r.status !== 'approved');
    if (stationRuns.length > 0 && unapprovedRuns.length > 0) {
      const unapprovedRatio = unapprovedRuns.length / stationRuns.length;
      // 20% of the monthly base is subject to approval
      const approvalSubjectAmount = monthlyBase * 0.20;
      const approvalPenalty = Math.round(approvalSubjectAmount * unapprovedRatio);
      if (approvalPenalty > 0) {
        extraPenalties.push({ reason: 'Unapproved Station Runs (20% conditional billing)', percentage: Math.round(unapprovedRatio * 100), amount: approvalPenalty });
        extraPenaltyAmount += approvalPenalty;
      }
    }

    // ── Annexure-AB Work Execution Sheet (50% billing component) ──
    let executionSheetSummary = { configured: false, items: [], executionScore: null, shortfallDeduction: 0, daysLogged: 0, itemScores: [] };
    try {
      const summary = await executionSheetService.getMonthlySummary({ contractId, stationId, month, year });
      executionSheetSummary = {
        configured: summary.itemScores.length > 0,
        items: summary.itemScores.length,
        executionScore: summary.itemScores.length > 0 ? summary.executionScore : null,
        shortfallDeduction: summary.itemScores.length > 0 ? summary.shortfallDeduction : 0,
        daysLogged: summary.daysLogged,
        monthlyBase,
        executionComponentNetBase: summary.executionComponentNetBase,
        achievedAmount: summary.achievedAmount,
        itemScores: summary.itemScores,
      };
    } catch (err) {
      logger.warn(`Execution sheet summary skipped for ${stationId} ${month}/${year}: ${err.message}`);
    }

    // ── Task Execution (50% billing component, shift-wise on APPROVED shift summaries) ──
    let shiftSummarySnap = null;
    try {
      shiftSummarySnap = await db.collection('stationShiftSummaries')
        .where('stationId', '==', stationId)
        .where('date', '>=', startDate)
        .where('date', '<=', endDate)
        .get();
    } catch {
      shiftSummarySnap = await db.collection('stationShiftSummaries').where('stationId', '==', stationId).get();
    }
    const submittedShiftSummaries = [];
    const approvedShiftSummaries = [];
    if (shiftSummarySnap) {
      shiftSummarySnap.forEach(d => {
        const r = d.data();
        if (!(r.date && r.date >= startDate && r.date <= endDate)) return;
        if (r.status === 'approved') approvedShiftSummaries.push(r);
        else if (r.status === 'submitted') submittedShiftSummaries.push(r);
      });
    }
    const approvedAreas = approvedShiftSummaries.reduce((s, r) => s + (Array.isArray(r.areas) ? r.areas.length : 0), 0);
    const approvedAreasWithPhoto = approvedShiftSummaries.reduce((s, r) => s + (Array.isArray(r.areas) ? r.areas.filter(a => a.photoUrl && String(a.photoUrl).trim()).length : 0), 0);
    const shiftPhotoComplianceRate = approvedAreas > 0 ? Math.round(approvedAreasWithPhoto / approvedAreas * 100) : null;
    const totalWorkDone = approvedShiftSummaries.reduce((s, r) => s + (r.totalWorkDone || 0), 0);
    const totalTenderedArea = approvedShiftSummaries.reduce((s, r) => s + (r.totalTenderedArea || 0), 0);
    const shiftExecutionRate = totalTenderedArea > 0 ? Math.round(Math.min(totalWorkDone / totalTenderedArea, 1) * 100) : null;
    const approvedDayCount = new Set(approvedShiftSummaries.map(r => r.date)).size;
    const submittedDayCount = new Set(submittedShiftSummaries.map(r => r.date)).size;
    // Area-wise execution (flat, sq.ft. based — area weightage is not used).
    const flatAreas = approvedShiftSummaries.flatMap(r => Array.isArray(r.areas) ? r.areas : []);
    const flatAgg = {};
    flatAreas.forEach(a => {
      const key = String(a.areaName || a.areaId || 'other').trim();
      if (!flatAgg[key]) flatAgg[key] = { areaName: key, areaId: a.areaId || '', executedSqFt: 0, expectedSqFt: 0 };
      flatAgg[key].executedSqFt += parseFloat(a.workDone) || 0;
      flatAgg[key].expectedSqFt += parseFloat(a.tenderedAreaPerDay) || 0;
    });
    const flatRows = Object.values(flatAgg);
    const flatExecuted = flatRows.reduce((s, r) => s + r.executedSqFt, 0);
    const flatExpected = flatRows.reduce((s, r) => s + r.expectedSqFt, 0);
    const flatRatio = flatExpected > 0 ? Math.min(flatExecuted / flatExpected, 1) * 100 : null;
    const executionParts = [];
    if (shiftExecutionRate !== null) executionParts.push(shiftExecutionRate);
    if (shiftPhotoComplianceRate !== null) executionParts.push(shiftPhotoComplianceRate);
    if (flatRatio !== null) executionParts.push(flatRatio);
    const taskExecutionScore = executionParts.length > 0
      ? Math.round((executionParts.reduce((s, v) => s + v, 0) / executionParts.length) * 100) / 100
      : null;
    const taskExecutionNetBase = Math.round(monthlyBase * 0.50);
    const taskExecutionSummary = {
      configured: taskExecutionScore !== null,
      approvedShiftSummaries: approvedShiftSummaries.length,
      submittedShiftSummaries: submittedShiftSummaries.length,
      approvedDays: approvedDayCount,
      submittedDays: submittedDayCount,
      shiftExecutionRate,
      totalWorkDone,
      totalTenderedArea,
      shiftAreasTotal: approvedAreas,
      shiftAreasWithPhoto: approvedAreasWithPhoto,
      shiftPhotoComplianceRate,
      taskExecutionScore,
      areaRows: flatRows,
      executedAreaSqFt: Math.round(flatExecuted * 100) / 100,
      expectedAreaSqFt: Math.round(flatExpected * 100) / 100,
      monthlyBase,
      taskExecutionComponentNetBase: taskExecutionNetBase,
      achievedAmount: taskExecutionScore !== null ? Math.round(taskExecutionNetBase * (taskExecutionScore / 100)) : 0,
      shortfallDeduction: taskExecutionScore !== null ? Math.round(taskExecutionNetBase * (1 - taskExecutionScore / 100)) : 0,
    };

    // ── Inspection Score (20% billing component) ──
    let inspectionBillingSummary = {
      configured: false,
      totalScoredInspections: 0,
      inspectionScore: null,
      monthlyBase,
      inspectionComponentNetBase: Math.round(monthlyBase * 0.20),
      achievedAmount: 0,
      shortfallDeduction: 0,
    };
    const scoredInspections = inspections.filter(i => ['COMPLETED', 'APPROVED'].includes(i.status) && typeof i.overallScore === 'number');
    if (scoredInspections.length > 0) {
      const inspectionScore = Math.round((scoredInspections.reduce((s, i) => s + i.overallScore, 0) / scoredInspections.length) * 100) / 100;
      const inspectionComponent = Math.round(monthlyBase * 0.20);
      const achievedAmount = Math.round(inspectionComponent * (inspectionScore / 100));
      const shortfallDeduction = inspectionComponent - achievedAmount;
      inspectionBillingSummary = {
        configured: true,
        totalScoredInspections: scoredInspections.length,
        inspectionScore,
        monthlyBase,
        inspectionComponentNetBase: inspectionComponent,
        achievedAmount,
        shortfallDeduction,
      };
    }

    const machines = []; machineSnap.forEach(d => machines.push(d.data()));
    const inMaintenanceCount = machines.filter(m => m.workingStatus === 'under_maintenance' || m.workingStatus === 'broken').length;

    // ── Overall score: 50% task execution + 20% inspection + 30% passenger feedback ──
    const feedbackScore = feedbackRecords.length > 0
      ? Math.round(((feedbackSummary.averageRating / 5) * 100) * 100) / 100
      : null;
    const scoreBreakdown = [];
    if (taskExecutionSummary.configured) scoreBreakdown.push({ component: 'Task Execution', weight: 50, score: taskExecutionSummary.taskExecutionScore });
    if (inspectionBillingSummary.configured) scoreBreakdown.push({ component: 'Inspection', weight: 20, score: inspectionBillingSummary.inspectionScore });
    if (feedbackScore !== null) scoreBreakdown.push({ component: 'Passenger Feedback', weight: 30, score: feedbackScore });

    let weightedScore = 0;
    let weightedAmount = 0;
    scoreBreakdown.forEach(c => { weightedScore += c.score * c.weight; weightedAmount += c.weight; });
    // Scores are 0-100 and weights are percentages; missing components are treated
    // as fully achieved (neutral), mirroring OBHS default when no data.
    const overallScore = Math.round(((weightedScore + (100 - weightedAmount) * 100) / 100) * 100) / 100;
    const grade = overallScore >= 90 ? 'A' : overallScore >= 80 ? 'B' : overallScore >= 70 ? 'C' : 'D';
    const deductionRate = billingRuleSnap.empty ? 100 : (billingRuleSnap.docs[0].data().deductionRate ?? 100);

    // OBHS score-aligned bill: billable = monthlyBase × (1 − (deductionRate/100) × (1 − overallScore/100)).
    // Specific operational penalties (attendance, score, machine downtime, unapproved runs)
    // are deducted on top; task-execution and inspection shortfalls are already reflected
    // via the Task Execution and Inspection components of overallScore.
    const scoreBasedBill = Math.max(0, Math.round(monthlyBase * (1 - (deductionRate / 100) * ((100 - overallScore) / 100))));
    const scoreDeductionAmount = Math.max(0, monthlyBase - scoreBasedBill);
    const billableAmount = Math.max(0, scoreBasedBill - extraPenaltyAmount);
    const deductions = [...extraPenalties];
    if (scoreDeductionAmount > 0) {
      deductions.push({ reason: 'OBHS Score Based Deduction', percentage: Math.round((100 - overallScore) * 100) / 100, amount: Math.round(scoreDeductionAmount) });
    }
    deductions.sort((a, b) => b.amount - a.amount);
    const penalties = { deductions, totalPenaltyAmount: Math.round(Math.max(0, monthlyBase - billableAmount)) };

    // Estimation / variation / SWO transparency layer (traceability).
    let estimateContribution = { total: 0, rows: [] };
    let amendedValue = null;
    try {
      estimateContribution = await contractEstimationService.getPeriodContribution({ contractId, stationId, month, year });
    } catch (e) {
      logger.warn(`Estimate contribution skipped for ${stationId} ${month}/${year}: ${e.message}`);
    }
    try {
      amendedValue = await contractEstimationService.getAmendedContractValue({ contractId });
    } catch (e) {
      logger.warn(`Amended value skipped for ${contractId}: ${e.message}`);
    }

    const ref = db.collection('station_billing_packs').doc();
    const now = new Date().toISOString();
    const pack = {
      uid: ref.id, contractId, stationId, stationName,
      month: parseInt(month), year: parseInt(year),
      contractNumber: contractData.contractNumber || '',
      contractorName: contractData.contractorName || contractData.entityName || '',
      monthlyContractValue: Math.round((contractData.contractValue || 0) / 12),
      gstRate: contractData.gstRate || 18,
      gstAmount: Math.round((billableAmount * (contractData.gstRate || 18)) / 100),
      totalPayableWithGst: Math.round(billableAmount * (1 + (contractData.gstRate || 18) / 100)),
      attendanceSummary, activitySummary: { ...actSummary, completionRate: activityCompletionRate },
      scorecardSummary, complaintSummary: cmpSummary, feedbackSummary, inspectionSummary,
      pettyIssueSummary, evidenceSummary,
      machineSummary: { total: machines.length, inMaintenance: inMaintenanceCount, deployed: machines.length - inMaintenanceCount, downtime: machineDowntimeSummary },
      taskExecutionSummary, executionSheetSummary, inspectionBillingSummary,
      overallScore, grade, deductionRate, scoreBreakdown, feedbackScore,
      penalties, billableAmount, status: 'DRAFT',
      estimateContribution, amendedValue,
      paymentStatus: 'unpaid', paymentDate: null, paymentRef: null, paymentAmount: null,
      complianceChecklist: { attendanceSheetAttached: false, wagesheetAttached: false, bankStatementAttached: false, policeVerificationAttached: false, medicalCertificateAttached: false, biometricSheetAttached: false, scorecardAttached: scorecardSummary.daysWithScorecard > 0, gstInvoiceAttached: false },
      generatedBy: user.uid, generatedByName: user.fullName || '', generatedAt: now, createdAt: now, updatedAt: now,
    };
    await ref.set(pack);
    await auditService.logAudit('STATION_BILL_PACK_CREATED', user.uid, user.fullName || 'System', ref.id, 'station_billing_packs', `Billing support pack generated for station ${stationName} period ${month}/${year}`);
    return { message: 'Billing support pack generated', uid: ref.id, pack };
  }

  async getPackById(uid) {
    const doc = await db.collection('station_billing_packs').doc(uid).get();
    if (!doc.exists) throw new NotFoundError('Billing pack not found');
    return { id: doc.id, ...doc.data() };
  }

  async listPacks(query = {}) {
    const { contractId, stationId, month, year, status, paymentStatus, limit = 50 } = query;
    let q = db.collection('station_billing_packs');
    if (contractId) q = q.where('contractId', '==', contractId);
    if (stationId) q = q.where('stationId', '==', stationId);
    if (month) q = q.where('month', '==', parseInt(month));
    if (year) q = q.where('year', '==', parseInt(year));
    if (status) q = q.where('status', '==', status);
    if (paymentStatus) q = q.where('paymentStatus', '==', paymentStatus);
    const snapshot = await q.limit(parseInt(limit) * 2).get();
    const packs = []; snapshot.forEach(doc => packs.push({ id: doc.id, ...doc.data() }));
    packs.sort((a, b) => ((b.createdAt || '') > (a.createdAt || '') ? 1 : -1));
    return { count: packs.length, packs };
  }

  async updateCompliance(uid, checklist, user) {
    const ref = db.collection('station_billing_packs').doc(uid);
    if (!(await ref.get()).exists) throw new NotFoundError('Billing pack not found');
    await ref.update({ complianceChecklist: checklist, updatedAt: new Date().toISOString() });
    if (user) {
      await auditService.logAudit('STATION_BILL_PACK_COMPLIANCE_UPDATED', user.uid, user.fullName || 'User', uid, 'station_billing_packs', `Compliance checklist updated`);
    }
    return { message: 'Compliance checklist updated', uid };
  }

  async submitPack(uid, user) {
    const ref = db.collection('station_billing_packs').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Billing pack not found');
    if (doc.data().status !== 'DRAFT') throw new ValidationError('Only DRAFT packs can be submitted');

    const pack = doc.data();
    const checklist = pack.complianceChecklist || {};
    const allComplete = Object.values(checklist).every(v => v === true);
    await ref.update({ status: 'SUBMITTED', submittedBy: user.uid, submittedAt: new Date().toISOString(), autoVerified: allComplete, updatedAt: new Date().toISOString() });
    await auditService.logAudit('STATION_BILL_PACK_SUBMITTED', user.uid, user.fullName || 'User', uid, 'station_billing_packs', `Billing support pack submitted`);
    return { message: 'Billing pack submitted', uid, autoVerified: allComplete };
  }

  async approvePack(uid, user) {
    const ref = db.collection('station_billing_packs').doc(uid);
    if (!(await ref.get()).exists) throw new NotFoundError('Billing pack not found');
    await ref.update({ status: 'APPROVED', approvedBy: user.uid, approvedAt: new Date().toISOString(), updatedAt: new Date().toISOString() });
    await auditService.logAudit('STATION_BILL_PACK_APPROVED', user.uid, user.fullName || 'User', uid, 'station_billing_packs', `Billing support pack approved`);
    return { message: 'Billing pack approved', uid };
  }

  async rejectPack(uid, reason, user) {
    const ref = db.collection('station_billing_packs').doc(uid);
    if (!(await ref.get()).exists) throw new NotFoundError('Billing pack not found');
    if (!reason) throw new ValidationError('Rejection reason is required');
    await ref.update({ status: 'REJECTED', rejectionReason: reason, rejectedBy: user.uid, rejectedAt: new Date().toISOString(), updatedAt: new Date().toISOString() });
    await auditService.logAudit('STATION_BILL_PACK_REJECTED', user.uid, user.fullName || 'User', uid, 'station_billing_packs', `Billing support pack rejected. Reason: ${reason}`);
    return { message: 'Billing pack rejected', uid };
  }

  async recordPayment(uid, user, body) {
    const ref = db.collection('station_billing_packs').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Billing pack not found');
    if (doc.data().status !== 'APPROVED') throw new ValidationError('Only APPROVED packs can have payments recorded');
    const { amount, paymentRef, paymentDate } = body;
    if (!amount || !paymentRef) throw new ValidationError('amount and paymentRef are required');
    await ref.update({ paymentStatus: amount >= doc.data().totalPayableWithGst ? 'paid' : 'partial', paymentAmount: amount, paymentRef, paymentDate: paymentDate || new Date().toISOString(), paidAt: new Date().toISOString(), paidBy: user.uid, updatedAt: new Date().toISOString() });
    await auditService.logAudit('STATION_BILL_PACK_PAYMENT_RECORDED', user.uid, user.fullName || 'User', uid, 'station_billing_packs', `Payment recorded. Ref: ${paymentRef}`);
    return { message: 'Payment recorded', uid };
  }

  async updatePack(uid, data, user) {
    const ref = db.collection('station_billing_packs').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Billing pack not found');
    if (!['DRAFT', 'REJECTED'].includes(doc.data().status)) throw new ValidationError('Only DRAFT or REJECTED packs can be edited');
    const allowed = ['complianceChecklist', 'attendanceSummary', 'activitySummary', 'scorecardSummary', 'complaintSummary', 'feedbackSummary', 'machineSummary', 'penalties', 'billableAmount', 'overallScore', 'grade', 'deductionRate', 'scoreBreakdown', 'feedbackScore', 'taskExecutionSummary'];
    const updates = { updatedAt: new Date().toISOString() };
    for (const key of allowed) { if (data[key] !== undefined) updates[key] = data[key]; }
    await ref.update(updates);
    if (user) {
      await auditService.logAudit('STATION_BILL_PACK_UPDATED', user.uid, user.fullName || 'User', uid, 'station_billing_packs', `Billing support pack updated`);
    }
    return { message: 'Billing pack updated', uid };
  }

  async deletePack(uid, user) {
    const ref = db.collection('station_billing_packs').doc(uid);
    if (!(await ref.get()).exists) throw new NotFoundError('Billing pack not found');
    await ref.update({ status: 'DELETED', deletedAt: new Date().toISOString(), updatedAt: new Date().toISOString() });
    if (user) {
      await auditService.logAudit('STATION_BILL_PACK_DELETED', user.uid, user.fullName || 'User', uid, 'station_billing_packs', `Billing support pack deleted`);
    }
    return { message: 'Billing pack deleted' };
  }

  async returnToDraft(uid, user) {
    const ref = db.collection('station_billing_packs').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Billing pack not found');
    if (doc.data().status !== 'REJECTED') throw new ValidationError('Only REJECTED packs can be returned to draft');
    await ref.update({ status: 'DRAFT', rejectionReason: null, updatedAt: new Date().toISOString(), returnedToDraftBy: user.uid });
    await auditService.logAudit('STATION_BILL_PACK_RETURNED_TO_DRAFT', user.uid, user.fullName || 'User', uid, 'station_billing_packs', `Billing support pack returned to draft`);
    return { message: 'Billing pack returned to draft', uid };
  }

  /* ---------------------------------------------------------------
     Monthly billing auto-generation (Workflow 15.3)
     --------------------------------------------------------------- */

  async generateMonthlyBillingPacks(month, year, user) {
    if (!month || !year) throw new ValidationError('month and year are required');
    const userObj = user || { uid: 'system', fullName: 'System', role: 'SUPER_ADMIN' };
    // Contract status is stored as 'Active' by the app (older rows may be 'ACTIVE'), so filter in code.
    const contractsSnap = await db.collection('contracts').limit(500).get();
    const contractDocs = contractsSnap.docs.filter((d) => {
      const c = d.data();
      return isActiveStatus(c.status) && String(c.contractType || '').toLowerCase() === 'station_cleaning';
    });
    if (contractDocs.length === 0) return { generated: 0, message: 'No active station cleaning contracts found' };

    const generated = [];
    const errors = [];

    for (const contractDoc of contractDocs) {
      const contract = contractDoc.data();
      const contractId = contractDoc.id;
      // Contracts store their stations in `stationIds`; `stationId` is accepted for older records.
      const contractStationIds = Array.isArray(contract.stationIds) && contract.stationIds.length
        ? contract.stationIds
        : (contract.stationId ? [contract.stationId] : []);
      let stationList = [];
      if (contractStationIds.length) {
        for (const sid of contractStationIds) {
          const stationDoc = await db.collection('stations').doc(sid).get();
          if (stationDoc.exists && stationDoc.data().active !== false) stationList.push(stationDoc);
        }
      } else {
        const all = await db.collection('stations').where('active', '==', true).limit(200).get();
        stationList = all.docs;
      }
      for (const stationDoc of stationList) {
        const stationId = stationDoc.id;
        try {
          const existSnap = await db.collection('station_billing_packs')
            .where('contractId', '==', contractId).where('stationId', '==', stationId)
            .where('month', '==', parseInt(month)).where('year', '==', parseInt(year)).limit(5).get();
          const existingPacks = []; existSnap.forEach(d => existingPacks.push(d.data()));
          if (existingPacks.some(p => ['DRAFT', 'SUBMITTED', 'APPROVED'].includes(p.status))) {
            errors.push({ contractId, stationId, error: 'Pack already exists for this period' });
            continue;
          }
          const result = await this.generateBillingSupportPack(userObj, { contractId, stationId, month, year });
          generated.push({ contractId, stationId, packUid: result.uid });
        } catch (err) {
          errors.push({ contractId, stationId, error: err.message });
        }
      }
    }
    return { generated: generated.length, packs: generated, errors };
  }

  /** Generates packs for every completed month that has none yet (covers months missed while the server was down). */
  async ensureMonthlyBillingPacks(user, { monthsBack = 6 } = {}) {
    const now = new Date();
    let generated = 0;
    for (let i = monthsBack; i >= 1; i--) {
      const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - i, 1));
      try {
        const res = await this.generateMonthlyBillingPacks(d.getUTCMonth() + 1, d.getUTCFullYear(), user);
        generated += res.generated || 0;
      } catch (_) { /* nothing to bill for this month */ }
    }
    return { generated };
  }
}

export const stationBillingService = new StationBillingService();
