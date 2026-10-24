/*
 * Weightage / performance-based billing (SRS Workflow 15).
 *
 * Payment is derived from ACTUAL CLEANING WORK VALUED BY AREA:
 *
 * Supports TWO billing modes:
 *   A) Manual rate mode  — admin sets a ₹/sqft rate in config
 *   B) Weightage mode    — admin allocates area weightages (100%),
 *                          daily money per area is derived from ACV / contractDays × weightage%
 *
 * When weightages are configured (mode B), ratePerSqft is NOT required.
 *
 *   area sqft x cleaning rate -> one execution value
 *   AREA -> SQFT -> RATE -> ACTUAL EXECUTION -> GROSS WORK VALUE
 *
 *   1. Scheduled Work Value (the value of every required execution in the
 *      period)  = SUM over areas( areaSqft x ratePerSqft x requiredExecutions )
 *   2. Gross Work Value (the value of every VERIFIED execution in the period)
 *                = SUM over areas( areaSqft x ratePerSqft x verifiedExecutions )
 *   3. Execution achievement = gross / scheduled * 100  (value-weighted, so a
 *      missed pass on a large platform costs more than one in a small toilet).
 *
 *   The PERFORMANCE SCORECARD weights three categories (must total 100):
 *     - Cleaning Execution   (50%)  <- value-weighted achievement
 *     - Railway Inspection   (20%)  <- avg overallScore of inspections
 *     - Passenger Feedback   (30%)  <- avg overallRating / 5 * 100
 *
 *   overallScore = SUM( categoryAchievement x maxMarks / 100 )
 *     -> lessExecutionPercent = 100 - overallScore
 *     -> lessExecutionAmount  = scheduledWorkValue x lessExecutionPercent / 100
 *     -> eligibleAmount       = min( grossWorkValue,
 *                                    scheduledWorkValue - lessExecutionAmount )
 *        (capped at the actual verified work so unexecuted passes are never
 *         paid, while low inspection/feedback scores still bite)
 *     -> penalty (SEPARATE, configurable slabs keyed off overall score)
 *     -> other recoveries (manual deductions like advances)
 *     -> netAmount -> GST -> totalPayable
 *
 * There is NO individual task approval. A task is COMPLETED directly by the
 * contractor supervisor. A VERIFIED execution is a cleaning pass acknowledged
 * in an APPROVED shift summary (the approval unit): each approved summary's
 * area entries contribute their `times` to that area's verified count for the
 * period, capped at the area's required executions. Tasks submitted but with no
 * approved shift summary are never counted.
 */

import { db } from '../database/index.js';
import { NotFoundError, ValidationError } from '../errors/index.js';
import logger from '../logger/index.js';
import { roundMoney, mulMoney } from '../utils/money.js';
import { computeContractDays } from '../utils/period.js';
import { auditService } from './auditService.js';
import {
  dailyContractValue,
  areaDailyMoneyValue,
  areaRatePerSqFt,
  perExecutionValue,
  executionDeduction,
  validateAreaWeightages,
} from './areaWeightageModel.js';

const LIFECYCLE = ['DRAFT', 'CALCULATED', 'SUBMITTED', 'VERIFIED', 'APPROVED', 'LOCKED'];
const ACTIVE_STATUSES = ['DRAFT', 'CALCULATED', 'SUBMITTED', 'VERIFIED', 'APPROVED', 'LOCKED'];

const DEFAULT_CATEGORIES = [
  { code: 'EXECUTION', name: 'Task Execution', maxMarks: 50, dataSource: 'execution', enabled: true, order: 1 },
  { code: 'INSPECTION', name: 'Railway Inspection', maxMarks: 20, dataSource: 'inspection', enabled: true, order: 2 },
  { code: 'FEEDBACK', name: 'Passenger Feedback', maxMarks: 30, dataSource: 'feedback', enabled: true, order: 3 },
];

const DEFAULT_PENALTY_RULES = [
  { uid: 'r1', name: 'Score >= 85% — no penalty', fromScore: 85, toScore: 101, action: 'NONE', value: 0, maxAmount: null, enabled: true },
  { uid: 'r2', name: 'Score 60% – 85% — 2% of eligible', fromScore: 60, toScore: 85, action: 'PERCENT_OF_ELIGIBLE', value: 2, maxAmount: null, enabled: true },
  { uid: 'r3', name: 'Score below 60% — 5% of eligible', fromScore: 0, toScore: 60, action: 'PERCENT_OF_ELIGIBLE', value: 5, maxAmount: null, enabled: true },
];

const round2 = (n) => Math.round((n + Number.EPSILON) * 100) / 100;
const clamp = (n, lo, hi) => Math.min(hi, Math.max(lo, n));

class PerformanceBillingService {
  /* ────────────────────────── configuration ────────────────────────── */

  async getOrCreateConfig(contractId) {
    const contractDoc = await db.collection('contracts').doc(contractId).get();
    const contract = contractDoc.exists ? contractDoc.data() : {};
    const snap = await db.collection('billing_configs')
      .where('contractId', '==', contractId).limit(1).get();
    if (!snap.empty) {
      const existing = { id: snap.docs[0].id, ...snap.docs[0].data() };
      // Migrate legacy docs: drop the removed activity-weightage config.
      if (Array.isArray(existing.activities)) existing.activities = [];
      if (existing.ratePerSqft === undefined) existing.ratePerSqft = null;
      if (existing.otherDeductions === undefined) existing.otherDeductions = 0;
      if (existing.dailyIncompleteExecutionPenalty === undefined) existing.dailyIncompleteExecutionPenalty = 200;
      if (!existing.areaRateOverrides || typeof existing.areaRateOverrides !== 'object') existing.areaRateOverrides = {};
      if (!existing.areaWeightages || typeof existing.areaWeightages !== 'object') existing.areaWeightages = {};
      if (existing.renormaliseInactiveActivities !== undefined) existing.renormaliseInactiveActivities = undefined;
      const acv = Number(existing.annualContractValue || contract.contractValue || contract.annualContractValue || 0);
      const contractDays = computeContractDays(contract.startDate, contract.endDate) || 365;
      existing.annualContractValue = acv;
      existing.contractDays = contractDays;
      existing.dailyContractValue = dailyContractValue(acv, contractDays);
      return existing;
    }

    const ref = db.collection('billing_configs').doc();
    const now = new Date().toISOString();
    const contractDays = computeContractDays(contract.startDate, contract.endDate) || 365;
    const config = {
      uid: ref.id,
      contractId,
      stationId: contract.stationIds?.[0] || contract.stationId || '',
      billingMethod: 'PERFORMANCE_WEIGHTAGE',
      annualContractValue: contract.contractValue || contract.annualContractValue || 0,
      contractDays,
      dailyContractValue: dailyContractValue(contract.contractValue || contract.annualContractValue || 0, contractDays),
      ratePerSqft: null,
      areaRateOverrides: {},
      areaWeightages: {},
      gstRate: contract.gstRate || 18,
      otherDeductions: 0,
      dailyIncompleteExecutionPenalty: 200,
      verifiedStatuses: ['approved'],
      categories: JSON.parse(JSON.stringify(DEFAULT_CATEGORIES)),
      activities: [],
      penaltyRules: JSON.parse(JSON.stringify(DEFAULT_PENALTY_RULES)),
      status: 'ACTIVE',
      createdBy: 'system', createdByName: 'System',
      createdAt: now, updatedAt: now,
    };
    await ref.set(config);
    return { id: ref.id, ...config };
  }

  async getConfig(contractId) {
    return this.getOrCreateConfig(contractId);
  }

  _validateConfig(config) {
    const cats = (config.categories || []).filter(c => c.enabled !== false);
    const catTotal = cats.reduce((s, c) => s + (Number(c.maxMarks) || 0), 0);
    const codes = new Set(cats.map(c => c.code));
    if (cats.length === 0) throw new ValidationError('At least one enabled performance category is required');
    if (catTotal !== 100) throw new ValidationError(`Enabled category maxMarks must sum to exactly 100 (currently ${catTotal})`);
    if (codes.size !== cats.length) throw new ValidationError('Duplicate category code found');

    const rules = config.penaltyRules || [];
    for (const r of rules) {
      if (r.enabled === false) continue;
      const from = Number(r.fromScore) || 0;
      const to = Number(r.toScore) || 0;
      if (from < 0 || from >= to || to > 101) throw new ValidationError(`Invalid penalty slab range in rule "${r.name}"`);
      if (r.action !== 'NONE' && !['PERCENT_OF_ELIGIBLE', 'PERCENT_OF_MONTHLY_BASE', 'FIXED_AMOUNT'].includes(r.action)) {
        throw new ValidationError(`Invalid penalty action "${r.action}" in rule "${r.name}"`);
      }
      const value = Number(r.value);
      if (r.action !== 'NONE' && Number.isNaN(value)) {
        throw new ValidationError(`Penalty value must be a number in rule "${r.name}"`);
      }
      if (r.action === 'FIXED_AMOUNT') {
        if (value < 0) throw new ValidationError(`Fixed penalty amount must be a non-negative number in rule "${r.name}"`);
      } else if (r.action !== 'NONE' && (value < 0 || value > 100)) {
        throw new ValidationError(`Penalty percentage must be between 0 and 100 in rule "${r.name}" (got ${value})`);
      }
      if (r.maxAmount !== null && r.maxAmount !== undefined && Number(r.maxAmount) < 0) {
        throw new ValidationError(`Penalty cap amount must be a non-negative number in rule "${r.name}"`);
      }
    }

    const rate = config.ratePerSqft;
    if (rate !== null && rate !== undefined && (Number.isNaN(Number(rate)) || Number(rate) < 0)) {
      throw new ValidationError('Cleaning rate must be a non-negative number');
    }
    const overrides = config.areaRateOverrides || {};
    if (typeof overrides !== 'object') throw new ValidationError('Area rate overrides must be a map of areaId to rate');
    for (const [areaId, val] of Object.entries(overrides)) {
      if (val !== null && (Number.isNaN(Number(val)) || Number(val) < 0)) {
        throw new ValidationError(`Invalid cleaning rate for area "${areaId}"`);
      }
    }

    const weightages = config.areaWeightages || {};
    if (typeof weightages !== 'object') throw new ValidationError('Area weightages must be a map of areaId to percentage');
    for (const [areaId, val] of Object.entries(weightages)) {
      if (val !== null && (Number.isNaN(Number(val)) || Number(val) < 0)) {
        throw new ValidationError(`Invalid weightage for area "${areaId}"`);
      }
    }
    const entries = Object.entries(weightages).filter(([, v]) => v !== null);
    if (entries.length > 0) {
      const total = entries.reduce((s, [, v]) => s + Number(v), 0);
      if (Math.abs(total - 100) > 0.01) {
        throw new ValidationError(`Area weightages must total exactly 100% (currently ${Math.round(total * 100) / 100}%)`);
      }
    }

    const gst = Number(config.gstRate);
    if (Number.isNaN(gst) || gst < 0) throw new ValidationError('GST rate must be a non-negative number');
    const other = Number(config.otherDeductions);
    if (Number.isNaN(other) || other < 0) throw new ValidationError('Other contractual deductions must be a non-negative number');
    const dPenalty = Number(config.dailyIncompleteExecutionPenalty);
    if (Number.isNaN(dPenalty) || dPenalty < 0) throw new ValidationError('Incomplete task execution penalty must be a non-negative number');
    return true;
  }

  async saveConfig(contractId, body, user) {
    const contractDoc = await db.collection('contracts').doc(contractId).get();
    if (!contractDoc.exists) throw new NotFoundError('Contract not found');
    const contract = contractDoc.data();

    const existing = await this.getOrCreateConfig(contractId);
    const base = existing;
    const now = new Date().toISOString();

    const next = { ...base };
    if (body.billingMethod) next.billingMethod = body.billingMethod;
    if (body.ratePerSqft !== undefined) next.ratePerSqft = body.ratePerSqft === null || body.ratePerSqft === '' ? null : Number(body.ratePerSqft);
    if (body.areaRateOverrides !== undefined) {
      const overrides = {};
      for (const [areaId, val] of Object.entries(body.areaRateOverrides || {})) {
        if (areaId === '') continue;
        if (val === null || val === undefined || val === '') continue;
        overrides[areaId] = Number(val);
      }
      next.areaRateOverrides = overrides;
    }
    if (body.areaWeightages !== undefined) {
      const weightages = {};
      for (const [areaId, val] of Object.entries(body.areaWeightages || {})) {
        if (areaId === '') continue;
        if (val === null || val === undefined || val === '') continue;
        weightages[areaId] = Number(val);
      }
      next.areaWeightages = weightages;
    }
    if (body.gstRate !== undefined) next.gstRate = Number(body.gstRate);
    if (body.otherDeductions !== undefined) next.otherDeductions = Number(body.otherDeductions) || 0;
    if (body.dailyIncompleteExecutionPenalty !== undefined) {
      next.dailyIncompleteExecutionPenalty =
        body.dailyIncompleteExecutionPenalty === null || body.dailyIncompleteExecutionPenalty === ''
          ? 0
          : Number(body.dailyIncompleteExecutionPenalty);
    }
    if (body.verifiedStatuses !== undefined) next.verifiedStatuses = Array.isArray(body.verifiedStatuses) ? body.verifiedStatuses : ['approved'];
    if (body.categories !== undefined) next.categories = body.categories;
    if (body.penaltyRules !== undefined) next.penaltyRules = body.penaltyRules;
    if (body.activities !== undefined) next.activities = []; // activity weightage removed

    this._validateConfig(next);
    next.updatedAt = now;
    next.updatedBy = user.uid;
    next.updatedByName = user.fullName || user.name || 'User';

    await db.collection('billing_configs').doc(base.id).set(next, { merge: true });
    await auditService.logAudit(
      'BILLING_CONFIG_UPDATED', user.uid, user.fullName || 'User',
      base.id, 'billing_configs',
      `Billing configuration updated for contract ${contractId}`
    );
    return { message: 'Billing configuration saved', config: { id: base.id, ...next } };
  }

  /* ───────────────────────── period helpers ────────────────────────── */

  _monthWindow(month, year) {
    const mm = String(month).padStart(2, '0');
    const lastDay = new Date(year, month, 0).getDate();
    return {
      startDate: `${year}-${mm}-01`,
      endDate: `${year}-${mm}-${String(lastDay).padStart(2, '0')}`,
    };
  }

  _daysBetween(a, b) {
    const ms = new Date(`${b}T00:00:00`) - new Date(`${a}T00:00:00`);
    return Math.round(ms / 86400000) + 1;
  }

  _effectivePeriod(contract, month, year) {
    const window = this._monthWindow(month, year);
    const cStart = String(contract.startDate || '').substring(0, 10);
    const cEnd = String(contract.endDate || '').substring(0, 10);
    let actualStart = window.startDate;
    let actualEnd = window.endDate;
    if (cStart && cStart > actualStart) actualStart = cStart;
    if (cEnd && cEnd < actualEnd) actualEnd = cEnd;
    if (actualStart > actualEnd) throw new ValidationError('Billing period has no overlap with the contract validity period');
    return {
      startDate: actualStart, endDate: actualEnd,
      contractStart: cStart, contractEnd: cEnd,
      requestedStart: window.startDate, requestedEnd: window.endDate,
      applicableDays: this._daysBetween(actualStart, actualEnd),
    };
  }

  /* ────────────────────────── scorecard ────────────────────────────── */

  async _loadApprovedShiftSummaries(stationId, startDate, endDate) {
    let summaries = [];
    try {
      const snap = await db.collection('stationShiftSummaries').where('stationId', '==', stationId).get();
      snap.forEach(d => summaries.push({ id: d.id, ...d.data() }));
    } catch (err) {
      logger.warn(`stationShiftSummaries read failed for ${stationId}: ${err.message}`);
    }
    return summaries.filter(s => {
      const approved = String(s.status || '').toLowerCase() === 'approved';
      const d = String(s.date || '');
      return approved && d >= startDate && d <= endDate;
    });
  }

  async computeScorecard({ contractId, stationId, month, year }) {
    if (!contractId || !stationId || !month || !year) throw new ValidationError('contractId, stationId, month, and year are required');
    const config = await this.getOrCreateConfig(contractId);

    const ratePerSqft = Number(config.ratePerSqft);
    const weightages = config.areaWeightages || {};
    const hasWeightages = Object.keys(weightages).length > 0;
    const acv = Number(config.annualContractValue || 0);
    const useWeightageMode = hasWeightages && acv > 0;

    // Allow either manual rate OR weightage-derived rates
    if ((Number.isNaN(ratePerSqft) || ratePerSqft <= 0) && !useWeightageMode) {
      throw new ValidationError('Cleaning rate (₹/sqft per execution) is not configured. Set it in Billing Configuration → General, or configure area weightages in Area Rates & Weightage.');
    }

    const contractDoc = await db.collection('contracts').doc(contractId).get();
    if (!contractDoc.exists) throw new NotFoundError('Contract not found');
    const contract = contractDoc.data();

    const stationDoc = await db.collection('stations').doc(stationId).get();
    if (!stationDoc.exists) throw new NotFoundError('Station not found');
    const stationName = stationDoc.data().stationName || '';

    const period = this._effectivePeriod(contract, parseInt(month), parseInt(year));
    const contractDays = computeContractDays(contract.startDate, contract.endDate) || 365;

    // Execution data — pulled by station then filtered to the window to avoid
    // composite index requirements (mirrors existing billing services).
    let tasks = [];
    try {
      const taskSnap = await db.collection('cleaningTasks').where('stationId', '==', stationId).get();
      taskSnap.forEach(d => tasks.push({ id: d.id, ...d.data() }));
    } catch (err) {
      logger.warn(`cleaningTasks read failed for ${stationId}: ${err.message}`);
    }
    tasks = tasks.filter(t => {
      const d = t.date || t.scheduledDate || '';
      return d >= period.startDate && d <= period.endDate;
    });

    let areas = [];
    try {
      const areaSnap = await db.collection('stationAreas').where('stationId', '==', stationId).get();
      areaSnap.forEach(d => areas.push({ id: d.id, uid: d.id, ...d.data() }));
    } catch (err) {
      logger.warn(`stationAreas read failed for ${stationId}: ${err.message}`);
    }
    areas = areas.filter(a => (a.status || 'active') !== 'inactive' && (a.status || 'active') !== 'removed');

    // Execution source = APPROVED shift summaries (the approval unit). Tasks have
    // no individual approval step, so task status is never read for counting.
    const summaries = await this._loadApprovedShiftSummaries(stationId, period.startDate, period.endDate);
    const executedByArea = {};
    summaries.forEach(s => {
      (s.areas || []).forEach(entry => {
        const areaId = entry.areaId;
        if (!areaId) return;
        const times = Number(entry.times) || 0;
        if (times > 0) executedByArea[areaId] = (executedByArea[areaId] || 0) + times;
      });
    });

    const overrides = config.areaRateOverrides || {};
    const rateOf = (areaId) => {
      const o = overrides[areaId];
      if (o !== undefined && o !== null && o !== '' && !Number.isNaN(Number(o)) && Number(o) >= 0) return Number(o);
      return Number.isFinite(ratePerSqft) && ratePerSqft > 0 ? ratePerSqft : 0;
    };
    const sqftOf = (a) => {
      const sqft = Number(a.basicAreaSqFt || a.areaSqFt || a.sqft || 0);
      return Number.isFinite(sqft) && sqft >= 0 ? sqft : 0;
    };

    const areaMeta = {};
    areas.forEach(a => { areaMeta[a.id || a.uid] = a; });

    // Per-area execution rows (value-weighted, no activity buckets).
    const areaRows = [];
    const rowMap = {};
    const totals = { required: 0, verified: 0 };
    tasks.forEach(t => {
      const areaId = t.areaId;
      if (!areaMeta[areaId]) return; // task belongs to an inactive/unknown area
      if (!rowMap[areaId]) {
        rowMap[areaId] = {
          areaId,
          areaName: t.areaName || areaMeta[areaId].areaName || areaMeta[areaId].name || '',
          sqft: sqftOf(areaMeta[areaId]),
          rate: rateOf(areaId),
          frequency: areaMeta[areaId].cleaningFrequency || areaMeta[areaId].frequencyType || '',
          weightage: (() => {
            const w = weightages[areaId];
            if (w !== undefined && w !== null && w !== '' && !Number.isNaN(Number(w))) return Number(w);
            return null;
          })(),
          required: 0, verified: 0,
        };
        areaRows.push(rowMap[areaId]);
      }
      rowMap[areaId].required += 1;
      totals.required += 1;
    });

    areaRows.forEach(r => {
      r.verified = Math.min(r.required, Math.max(0, executedByArea[r.areaId] || 0));
      totals.verified += r.verified;
      r.achievement = r.required > 0 ? clamp(Math.round((r.verified / r.required) * 10000) / 100, 0, 100) : null;
      // Use weightage-derived values when in weightage mode, mirroring daily billing
      if (useWeightageMode && r.weightage !== null) {
        const areaDaily = areaDailyMoneyValue(acv, r.weightage, contractDays);
        const perExec = perExecutionValue(areaDaily, r.required);
        r.rate = areaRatePerSqFt(areaDaily, r.sqft);
        r.scheduledValue = roundMoney(perExec * r.required);
        r.actualValue = roundMoney(perExec * r.verified);
      } else {
        r.scheduledValue = Math.round(r.sqft * r.rate * r.required);
        r.actualValue = Math.round(r.sqft * r.rate * r.verified);
      }
    });

    const scheduledWorkValue = areaRows.reduce((s, r) => s + r.scheduledValue, 0);
    const grossWorkValue = areaRows.reduce((s, r) => s + r.actualValue, 0);

    const executionAchievement = scheduledWorkValue > 0
      ? clamp(Math.round((grossWorkValue / scheduledWorkValue) * 10000) / 100, 0, 100)
      : 0;

    // Inspection category.
    let inspectionCount = 0; let inspectionAchievement = null;
    try {
      const inspSnap = await db.collection('inspections').where('stationId', '==', stationId).get();
      const scored = [];
      inspSnap.forEach(d => {
        const r = d.data();
        const ts = r.inspectionDate || r.createdAt || '';
        const day = String(ts).substring(0, 10);
        if (day >= period.startDate && day <= period.endDate && ['COMPLETED', 'APPROVED'].includes(r.status) && typeof r.overallScore === 'number') {
          scored.push(r.overallScore);
        }
      });
      inspectionCount = scored.length;
      if (inspectionCount > 0) inspectionAchievement = clamp(Math.round((scored.reduce((s, v) => s + v, 0) / inspectionCount) * 100) / 100, 0, 100);
    } catch (err) { logger.warn(`inspections read failed: ${err.message}`); }

    // Feedback category.
    let feedbackCount = 0; let feedbackAchievement = null;
    try {
      const fbSnap = await db.collection('passenger_feedback').where('stationId', '==', stationId).get();
      const ratings = [];
      fbSnap.forEach(d => {
        const r = d.data();
        if (r.status === 'CANCELLED') return;
        const ts = r.createdAt || '';
        const day = String(ts).substring(0, 10);
        if (day >= period.startDate && day <= period.endDate && typeof r.overallRating === 'number') {
          ratings.push(clamp(r.overallRating, 0, 5));
        }
      });
      feedbackCount = ratings.length;
      if (feedbackCount > 0) {
        const avg = ratings.reduce((s, v) => s + v, 0) / feedbackCount;
        feedbackAchievement = clamp(Math.round(((avg / 5) * 100) * 100) / 100, 0, 100);
      }
    } catch (err) { logger.warn(`passenger_feedback read failed: ${err.message}`); }

    // Category marks, overall score.
    const cats = (config.categories || []).filter(c => c.enabled !== false).sort((a, b) => a.order - b.order);
    const categories = cats.map(c => {
      let achievement = null; let notApplicable = false;
      if (c.dataSource === 'execution') { achievement = executionAchievement; }
      else if (c.dataSource === 'inspection') {
        if (inspectionCount === 0) { notApplicable = true; }
        achievement = inspectionAchievement;
      } else if (c.dataSource === 'feedback') {
        if (feedbackCount === 0) { notApplicable = true; }
        achievement = feedbackAchievement;
      }
      if (achievement === null) achievement = 0;
      const marks = round2((achievement * (Number(c.maxMarks) || 0)) / 100);
      const out = {
        code: c.code, name: c.name, dataSource: c.dataSource, maxMarks: c.maxMarks,
        enabled: c.enabled !== false, achievement, marks, notApplicable,
      };
      if (c.dataSource === 'execution') out.execution = { verified: totals.verified, required: totals.required };
      if (c.dataSource === 'inspection') out.count = inspectionCount;
      if (c.dataSource === 'feedback') out.count = feedbackCount;
      return out;
    });

    const overallScore = round2(categories.reduce((s, c) => s + c.marks, 0));
    const grade = overallScore >= 90 ? 'A' : overallScore >= 80 ? 'B' : overallScore >= 70 ? 'C' : overallScore >= 60 ? 'D' : 'E';

    const lessExecutionPercent = round2(clamp(100 - overallScore, 0, 100));
    const lessExecutionAmount = Math.round((scheduledWorkValue * lessExecutionPercent) / 100);
    const eligibleAmount = Math.max(0, Math.min(grossWorkValue, scheduledWorkValue - lessExecutionAmount));

    const penaltyPreview = this._applyPenaltyRules(config, overallScore, scheduledWorkValue, eligibleAmount);

    return {
      contractId, stationId, stationName,
      contractNumber: contract.contractNumber || '',
      contractorName: contract.contractorName || contract.entityName || '',
      month: parseInt(month), year: parseInt(year),
      period: {
        startDate: period.startDate, endDate: period.endDate,
        contractStart: period.contractStart, contractEnd: period.contractEnd,
        applicableDays: period.applicableDays,
      },
      ratePerSqft: useWeightageMode ? null : ratePerSqft,
      executionSource: 'approved_shift_summaries',
      approvedShiftSummaries: summaries.length,
      // Value pipeline (AREA -> SQFT -> RATE -> ACTUAL EXECUTION).
      scheduledWorkValue,
      grossWorkValue,
      execution: {
        achievement: executionAchievement,
        required: totals.required,
        verified: totals.verified,
        scheduledValue: scheduledWorkValue,
        actualValue: grossWorkValue,
        areaRows,
      },
      // Score (50% execution / 20% inspection / 30% feedback) -> deductions.
      categories,
      inspection: { count: inspectionCount, achievement: inspectionAchievement },
      feedback: { count: feedbackCount, achievement: feedbackAchievement },
      overallScore, grade,
      // Financial pipeline -> penalty/deduction -> net payable (base for
      // bill-level less% amounts is scheduledWorkValue).
      monthlyBase: scheduledWorkValue,
      lessExecutionPercent, lessExecutionAmount, eligibleAmount,
      penaltyPreview,
      generatedAt: new Date().toISOString(),
    };
  }

  _applyPenaltyRules(config, overallScore, monthlyBase, eligibleAmount) {
    const rules = (config.penaltyRules || []).filter(r => r.enabled !== false).sort((a, b) => a.fromScore - b.fromScore);
    if (rules.length === 0) return { applied: false, rows: [], totalPenalty: 0 };
    const match = rules.find(r => overallScore >= r.fromScore && overallScore < r.toScore) || rules[rules.length - 1];
    if (!match || match.action === 'NONE') return { applied: false, rows: [], totalPenalty: 0 };
    let amount = 0;
    if (match.action === 'PERCENT_OF_ELIGIBLE') amount = Math.round((eligibleAmount * Number(match.value)) / 100);
    else if (match.action === 'PERCENT_OF_MONTHLY_BASE') amount = Math.round((monthlyBase * Number(match.value)) / 100);
    else if (match.action === 'FIXED_AMOUNT') amount = Math.round(Number(match.value) || 0);
    if (match.maxAmount && amount > Number(match.maxAmount)) amount = Math.round(Number(match.maxAmount));
    return {
      applied: true,
      rows: [{
        uid: match.uid, name: match.name, action: match.action, value: match.value,
        fromScore: match.fromScore, toScore: match.toScore, amount,
      }],
      totalPenalty: amount,
    };
  }

  /* ──────────────────────────── bills ──────────────────────────────── */

  async _nextBillNumber(contractNumber, month, year) {
    const mm = String(month).padStart(2, '0');
    const prefix = `BIL-${(contractNumber || 'CON').replace(/[^A-Za-z0-9]/g, '')}-${year}${mm}`;
    const snap = await db.collection('billing_bills')
      .where('billNumber', '>=', prefix + '-')
      .where('billNumber', '<=', prefix + '~\uFFFF')
      .limit(500).get();
    return `${prefix}-${String(snap.size + 1).padStart(3, '0')}`;
  }

  _configSnapshot(config) {
    return {
      billingMethod: config.billingMethod,
      ratePerSqft: config.ratePerSqft ?? null,
      areaRateOverrides: { ...(config.areaRateOverrides || {}) },
      areaWeightages: { ...(config.areaWeightages || {}) },
      categories: (config.categories || []).map(c => ({ ...c })),
      activities: [],
      penaltyRules: (config.penaltyRules || []).map(r => ({ ...r })),
      verifiedStatuses: config.verifiedStatuses || ['approved'],
      gstRate: config.gstRate,
      otherDeductions: Number(config.otherDeductions) || 0,
      dailyIncompleteExecutionPenalty: Number(config.dailyIncompleteExecutionPenalty) || 0,
    };
  }

  async generateBill(user, { contractId, stationId, month, year }) {
    if (!contractId || !stationId || !month || !year) throw new ValidationError('contractId, stationId, month, and year are required');

    const existingSnap = await db.collection('billing_bills')
      .where('contractId', '==', contractId)
      .where('stationId', '==', stationId)
      .where('month', '==', parseInt(month))
      .where('year', '==', parseInt(year))
      .limit(20).get();
    const existing = [];
    existingSnap.forEach(d => { const r = d.data(); if (ACTIVE_STATUSES.includes(r.status)) existing.push({ id: d.id, ...r }); });
    if (existing.length > 0) {
      existing.sort((a, b) => (b.createdAt || '').localeCompare(a.createdAt || ''));
      return { message: 'Existing active bill returned', uid: existing[0].id, bill: existing[0] };
    }

    const config = await this.getOrCreateConfig(contractId);
    const contractDoc = await db.collection('contracts').doc(contractId).get();
    const contract = contractDoc.data();

    const scorecard = await this.computeScorecard({ contractId, stationId, month, year });
    const scheduledWorkValue = scorecard.scheduledWorkValue;
    const grossWorkValue = scorecard.grossWorkValue;
    const eligibleAmount = scorecard.eligibleAmount;
    const penalty = this._applyPenaltyRules(config, scorecard.overallScore, scheduledWorkValue, eligibleAmount);

    const id = db.collection('billing_bills').doc();
    const now = new Date().toISOString();
    const ref = db.collection('billing_bills').doc(id.id);
    const bill = {
      uid: id.id,
      billNumber: await this._nextBillNumber(contract.contractNumber || '', month, year),
      contractId, stationId, stationName: scorecard.stationName,
      contractNumber: scorecard.contractNumber,
      contractorName: scorecard.contractorName,
      month: parseInt(month), year: parseInt(year),
      billingMethod: config.billingMethod,
      configSnapshot: this._configSnapshot(config),
      scorecard,
      scheduledWorkValue,
      grossWorkValue,
      ratePerSqft: scorecard.ratePerSqft,
      monthlyBase: scheduledWorkValue,
      lessExecutionPercent: scorecard.lessExecutionPercent,
      lessExecutionAmount: scorecard.lessExecutionAmount,
      eligibleAmount: scorecard.eligibleAmount,
      penalty: { rows: penalty.rows, totalPenalty: penalty.totalPenalty, applied: penalty.applied },
      otherRecoveries: [],
      otherRecoveriesAmount: 0,
      netAmount: Math.max(0, scorecard.eligibleAmount - penalty.totalPenalty),
      gstRate: config.gstRate,
      gstAmount: Math.round(Math.max(0, scorecard.eligibleAmount - penalty.totalPenalty) * (config.gstRate || 0) / 100),
      totalPayable: Math.round(Math.max(0, scorecard.eligibleAmount - penalty.totalPenalty) * (1 + (config.gstRate || 0) / 100)),
      status: 'DRAFT',
      paymentStatus: 'unpaid', paymentAmount: null, paymentRef: null, paymentDate: null,
      auditTrail: [{
        action: 'BILL_CREATED', by: user.uid, byName: user.fullName || 'User',
        message: 'Bill drafted', at: now,
      }],
      createdBy: user.uid, createdByName: user.fullName || 'User',
      createdAt: now, updatedAt: now,
    };
    await ref.set(bill);
    await auditService.logAudit('BILL_CREATED', user.uid, user.fullName || 'User', id.id, 'billing_bills',
      `Bill ${bill.billNumber} drafted for ${scorecard.stationName} ${month}/${year}`);
    return { message: 'Bill drafted', uid: id.id, bill };
  }

  async _getBill(uid) {
    const doc = await db.collection('billing_bills').doc(uid).get();
    if (!doc.exists || doc.data().status === 'DELETED') throw new NotFoundError('Bill not found');
    return { id: doc.id, ...doc.data() };
  }

  async _pushAudit(billRef, bill, user, action, message) {
    const entry = { action, by: user.uid, byName: user.fullName || 'User', message, at: new Date().toISOString() };
    const trail = [...(bill.auditTrail || []), entry];
    bill.auditTrail = trail;
    await billRef.update({ auditTrail: trail, updatedAt: new Date().toISOString() });
    await auditService.logAudit(action, user.uid, user.fullName || 'User', bill.uid, 'billing_bills', message);
    return entry;
  }

  async recalculateBill(user, uid) {
    const bill = await this._getBill(uid);
    if (!['DRAFT', 'CALCULATED'].includes(bill.status)) throw new ValidationError('Only DRAFT or CALCULATED bills can be recalculated');

    const config = await this.getOrCreateConfig(bill.contractId);
    const scorecard = await this.computeScorecard({ contractId: bill.contractId, stationId: bill.stationId, month: bill.month, year: bill.year });
    const scheduledWorkValue = scorecard.scheduledWorkValue;
    const grossWorkValue = scorecard.grossWorkValue;
    const eligibleAmount = scorecard.eligibleAmount;
    const penalty = this._applyPenaltyRules(config, scorecard.overallScore, scheduledWorkValue, eligibleAmount);

    const recoveries = Array.isArray(bill.otherRecoveries) ? bill.otherRecoveries : [];
    const recoveriesAmount = recoveries.reduce((s, r) => s + (Number(r.amount) || 0), 0);
    const netAmount = Math.max(0, eligibleAmount - penalty.totalPenalty - recoveriesAmount);

    const ref = db.collection('billing_bills').doc(uid);
    const now = new Date().toISOString();
    const updates = {
      scorecard,
      scheduledWorkValue,
      grossWorkValue,
      ratePerSqft: scorecard.ratePerSqft,
      monthlyBase: scheduledWorkValue,
      lessExecutionPercent: scorecard.lessExecutionPercent,
      lessExecutionAmount: scorecard.lessExecutionAmount,
      eligibleAmount,
      penalty: { rows: penalty.rows, totalPenalty: penalty.totalPenalty, applied: penalty.applied },
      configSnapshot: this._configSnapshot(config),
      otherRecoveries: recoveries,
      otherRecoveriesAmount: recoveriesAmount,
      netAmount,
      gstRate: config.gstRate,
      gstAmount: Math.round(netAmount * (config.gstRate || 0) / 100),
      totalPayable: Math.round(netAmount * (1 + (config.gstRate || 0) / 100)),
      status: 'CALCULATED',
      updatedAt: now,
    };
    await ref.update(updates);
    const updated = { id: uid, ...(await ref.get()).data() };
    await this._pushAudit(ref, updated, user, 'BILL_CALCULATED', `Bill ${updated.billNumber} recalculated. Overall score ${scorecard.overallScore}/100`);
    return { message: 'Bill calculated', uid, bill: updated };
  }

  async submitBill(user, uid) {
    const bill = await this._getBill(uid);
    if (bill.status !== 'CALCULATED') throw new ValidationError('Only CALCULATED bills can be submitted');
    const ref = db.collection('billing_bills').doc(uid);
    await ref.update({ status: 'SUBMITTED', submittedBy: user.uid, submittedByName: user.fullName || 'User', submittedAt: new Date().toISOString(), updatedAt: new Date().toISOString() });
    const updated = { id: uid, ...(await ref.get()).data() };
    await this._pushAudit(ref, updated, user, 'BILL_SUBMITTED', `Bill ${bill.billNumber} submitted for railway verification`);
    return { message: 'Bill submitted', uid, bill: updated };
  }

  async verifyBill(user, uid) {
    const bill = await this._getBill(uid);
    if (bill.status !== 'SUBMITTED') throw new ValidationError('Only SUBMITTED bills can be verified');
    const ref = db.collection('billing_bills').doc(uid);
    await ref.update({ status: 'VERIFIED', verifiedBy: user.uid, verifiedByName: user.fullName || 'User', verifiedAt: new Date().toISOString(), updatedAt: new Date().toISOString() });
    const updated = { id: uid, ...(await ref.get()).data() };
    await this._pushAudit(ref, updated, user, 'BILL_VERIFIED', `Bill ${bill.billNumber} verified against execution records`);
    return { message: 'Bill verified', uid, bill: updated };
  }

  async approveBill(user, uid) {
    const bill = await this._getBill(uid);
    if (bill.status !== 'VERIFIED') throw new ValidationError('Only VERIFIED bills can be approved');
    const ref = db.collection('billing_bills').doc(uid);
    await ref.update({ status: 'APPROVED', approvedBy: user.uid, approvedByName: user.fullName || 'User', approvedAt: new Date().toISOString(), updatedAt: new Date().toISOString() });
    const updated = { id: uid, ...(await ref.get()).data() };
    await this._pushAudit(ref, updated, user, 'BILL_APPROVED', `Bill ${bill.billNumber} approved for payment`);
    return { message: 'Bill approved', uid, bill: updated };
  }

  async lockBill(user, uid) {
    const bill = await this._getBill(uid);
    if (bill.status !== 'APPROVED') throw new ValidationError('Only APPROVED bills can be locked');
    const ref = db.collection('billing_bills').doc(uid);
    await ref.update({ status: 'LOCKED', lockedBy: user.uid, lockedByName: user.fullName || 'User', lockedAt: new Date().toISOString(), updatedAt: new Date().toISOString() });
    const updated = { id: uid, ...(await ref.get()).data() };
    await this._pushAudit(ref, updated, user, 'BILL_LOCKED', `Bill ${bill.billNumber} locked (final)`);
    return { message: 'Bill locked', uid, bill: updated };
  }

  async reopenBill(user, uid, reason) {
    const bill = await this._getBill(uid);
    if (!['CALCULATED', 'SUBMITTED', 'VERIFIED', 'APPROVED', 'LOCKED'].includes(bill.status)) throw new ValidationError('This bill cannot be reopened');
    if (!reason || !reason.trim()) throw new ValidationError('A reason is required to reopen a bill');
    const ref = db.collection('billing_bills').doc(uid);
    await ref.update({ status: 'DRAFT', reopenedAt: new Date().toISOString(), reopenedBy: user.uid, reopenedByName: user.fullName || 'User', updatedAt: new Date().toISOString() });
    const updated = { id: uid, ...(await ref.get()).data() };
    await this._pushAudit(ref, updated, user, 'BILL_REOPENED', `Bill ${bill.billNumber} reopened to draft. Reason: ${reason}`);
    return { message: 'Bill reopened to draft', uid, bill: updated };
  }

  async updateBillRecoveries(user, uid, body) {
    const bill = await this._getBill(uid);
    if (!['DRAFT', 'CALCULATED'].includes(bill.status)) throw new ValidationError('Recoveries can only be edited on DRAFT or CALCULATED bills');
    const recoveries = Array.isArray(body.otherRecoveries) ? body.otherRecoveries.map(r => ({
      label: String(r.label || 'Other recovery').slice(0, 120),
      amount: Math.round(Number(r.amount) || 0),
    })) : [];
    const recoveriesAmount = recoveries.reduce((s, r) => s + r.amount, 0);
    const gstRate = body.gstRate !== undefined ? Number(body.gstRate) : bill.gstRate;
    if (Number.isNaN(gstRate) || gstRate < 0) throw new ValidationError('Invalid GST rate');

    const netAmount = Math.max(0, bill.eligibleAmount - (bill.penalty?.totalPenalty || 0) - recoveriesAmount);
    const ref = db.collection('billing_bills').doc(uid);
    await ref.update({
      otherRecoveries: recoveries,
      otherRecoveriesAmount: recoveriesAmount,
      gstRate,
      netAmount,
      gstAmount: Math.round(netAmount * gstRate / 100),
      totalPayable: Math.round(netAmount * (1 + gstRate / 100)),
      updatedAt: new Date().toISOString(),
    });
    const updated = { id: uid, ...(await ref.get()).data() };
    await this._pushAudit(ref, updated, user, 'BILL_RECOVERIES_UPDATED', `Bill ${bill.billNumber} recoveries updated`);
    return { message: 'Bill recoveries updated', uid, bill: updated };
  }

  async listBills(query = {}) {
    const { contractId, stationId, month, year, status, limit = 100 } = query;
    let q = db.collection('billing_bills');
    if (contractId) q = q.where('contractId', '==', contractId);
    if (stationId) q = q.where('stationId', '==', stationId);
    if (month) q = q.where('month', '==', parseInt(month));
    if (year) q = q.where('year', '==', parseInt(year));
    if (status) q = q.where('status', '==', status);
    const snapshot = await q.limit(parseInt(limit) * 2).get();
    const bills = [];
    snapshot.forEach(d => { const r = d.data(); if (r.status !== 'DELETED') bills.push({ id: d.id, ...r }); });
    bills.sort((a, b) => (b.year - a.year) || (b.month - a.month) || (b.createdAt || '').localeCompare(a.createdAt || ''));
    return { count: bills.length, bills };
  }

  async getBill(uid) {
    return this._getBill(uid);
  }

  async deleteBill(user, uid) {
    const bill = await this._getBill(uid);
    if (!['DRAFT', 'CALCULATED'].includes(bill.status)) throw new ValidationError('Only DRAFT or CALCULATED bills can be deleted');
    const ref = db.collection('billing_bills').doc(uid);
    await ref.update({ status: 'DELETED', deletedBy: user.uid, deletedAt: new Date().toISOString(), updatedAt: new Date().toISOString() });
    await auditService.logAudit('BILL_DELETED', user.uid, user.fullName || 'User', uid, 'billing_bills', `Bill ${bill.billNumber} deleted`);
    return { message: 'Bill deleted', uid };
  }

  async recordPayment(user, uid, body) {
    const bill = await this._getBill(uid);
    if (!['APPROVED', 'LOCKED'].includes(bill.status)) throw new ValidationError('Only APPROVED or LOCKED bills can have payments recorded');
    const { amount, paymentRef, paymentDate, mode } = body;
    if (!amount || !paymentRef) throw new ValidationError('amount and paymentRef are required');
    if (bill.paymentStatus === 'paid') throw new ValidationError(`Bill ${bill.billNumber} is already fully paid`);
    const thisPayment = Number(amount);
    const cumulative = (bill.paymentStatus === 'partial' ? Number(bill.paymentAmount) || 0 : 0) + thisPayment;
    const paid = cumulative >= bill.totalPayable;
    const ref = db.collection('billing_bills').doc(uid);
    await ref.update({
      paymentStatus: paid ? 'paid' : 'partial',
      paymentAmount: Math.round(cumulative),
      paymentRef, paymentDate: paymentDate || new Date().toISOString(),
      paymentMode: mode || 'bank_transfer',
      paidAt: paid ? new Date().toISOString() : bill.paidAt || null,
      paidBy: paid ? user.uid : bill.paidBy || user.uid,
      updatedAt: new Date().toISOString(),
    });
    const updated = { id: uid, ...(await ref.get()).data() };
    await this._pushAudit(ref, updated, user, 'BILL_PAYMENT_RECORDED', `Payment of ${thisPayment} recorded against ${bill.billNumber} (ref ${paymentRef})`);
    return { message: 'Payment recorded', uid, bill: updated };
  }

  async getDashboard(user, query = {}) {
    const { contractId, stationId } = query;
    let q = db.collection('billing_bills');
    if (contractId) q = q.where('contractId', '==', contractId);
    if (stationId) q = q.where('stationId', '==', stationId);
    const snapshot = await q.limit(500).get();
    const bills = [];
    snapshot.forEach(d => { const r = d.data(); if (r.status !== 'DELETED') bills.push(r); });
    const byStatus = {};
    let totalBilled = 0; let totalPayable = 0; let totalPaid = 0;
    bills.forEach(b => {
      byStatus[b.status] = (byStatus[b.status] || 0) + 1;
      if (['CALCULATED', 'SUBMITTED', 'VERIFIED', 'APPROVED', 'LOCKED'].includes(b.status)) totalBilled += b.totalPayable || 0;
      if (b.paymentStatus === 'paid') totalPaid += b.paymentAmount || 0;
      if (['APPROVED', 'LOCKED'].includes(b.status)) totalPayable += b.totalPayable || 0;
    });
    return { totalBills: bills.length, byStatus, totalBilled, totalPayable, totalPaid, bills };
  }
}

export const performanceBillingService = new PerformanceBillingService();