/*
 * Work Execution Sheet (Annexure-AB) service.
 * Tracks daily execution of the 25 weighted items and computes the monthly
 * execution score used for the 50% billing component of station cleaning
 * contracts.
 *
 * Required Firestore composite indexes:
 *  1. `execution_sheet_daily_logs` – `contractId` ASC, `stationId` ASC, `date` ASC
 */

import { db, admin } from '../database/index.js';
import { NotFoundError, ValidationError } from '../errors/index.js';
import { auditService } from './auditService.js';
import { roundMoney, mulMoney, ratioSafe, clampPct } from '../utils/money.js';

const STATUS_SET = new Set(['EXECUTED', 'PARTIAL', 'NOT_EXECUTED', 'N/A']);
const WEIGHTAGE_EPS = 0.01;

function daysInMonth(month, year) {
  return new Date(parseInt(year), parseInt(month), 0).getDate();
}

function round2(x) {
  if (typeof x !== 'number' || !Number.isFinite(x)) return 0;
  return Math.round((x + Number.EPSILON) * 100) / 100;
}

function near100(value) {
  return Math.abs(round2(value) - 100) <= WEIGHTAGE_EPS + 1e-9;
}

/** Required cleaning passes per day for an area (ECR §2.2). */
function passesPerDay(area) {
  const boqTimes = parseInt(area?.boqTimesPerPeriod, 10) || 1;
  const freq = String(area?.cleaningFrequency || '').toLowerCase();
  if (freq === 'weekly') return boqTimes / 7;
  if (freq === 'monthly') return boqTimes / 30;
  return boqTimes;
}

/**
 * Hydrate an area Firestore doc for weightage math.
 * Returns null when the doc is missing or not active (callers record skippedAreas).
 */
function hydrateArea(doc) {
  if (!doc || !doc.exists) return null;
  const a = doc.data() || {};
  const status = a.status === undefined ? 'active' : String(a.status).toLowerCase();
  if (status !== 'active') return null;
  const basicAreaSqFt = Number(a.basicAreaSqFt) || 0;
  const unitCount = Number(a.unitCount) || 0;
  const tenderedAreaPerDay = Number(a.tenderedAreaPerDay) || 0;
  let requiredPassesPerDay = Number(a.requiredPassesPerDay) || 0;
  if (!(requiredPassesPerDay > 0)) {
    if (basicAreaSqFt > 0 && tenderedAreaPerDay > 0) {
      requiredPassesPerDay = tenderedAreaPerDay / basicAreaSqFt;
    } else {
      requiredPassesPerDay = passesPerDay(a);
    }
  }
  return {
    areaId: doc.id,
    uid: a.uid || doc.id,
    stationId: a.stationId || '',
    mainArea: a.mainArea || '',
    areaName: a.areaName || '',
    sectionName: a.sectionName ?? a.section ?? '',
    basicAreaSqFt,
    unitCount,
    unit: a.unit || 'sqft',
    tenderedAreaPerDay,
    requiredPassesPerDay,
    cleaningFrequency: a.cleaningFrequency || '',
    boqTimesPerPeriod: Number(a.boqTimesPerPeriod) || 1,
  };
}

/**
 * Fraction of the item this area receives under the item's splitBasis.
 * `splitBasis:'count'` falls back to an equal split when Σ unitCount = 0.
 */
function areaShare(area, item, hydratedAreas) {
  const n = hydratedAreas.length;
  if (n === 0) return 0;
  const basis = item?.splitBasis || 'sqft';
  if (basis === 'equal') return 1 / n;
  const denom = hydratedAreas.reduce(
    (sum, a) => sum + (basis === 'count' ? Number(a.unitCount) || 0 : Number(a.basicAreaSqFt) || 0),
    0
  );
  if (denom <= 0) return 1 / n;
  const num = basis === 'count' ? Number(area.unitCount) || 0 : Number(area.basicAreaSqFt) || 0;
  return num / denom;
}

/**
 * Build a hybrid mappedAreas entry: { areaId, manualWeightage, mainArea, subAreas }.
 * Engine fields (mainArea/subAreas) preserved so getMonthlySummary's
 * _matchesMappedArea keeps matching shift summaries (C3/AC7).
 */
function attachEngineFields(areaId, manualWeightage, area, oldMapped) {
  const existing = (oldMapped || []).find((m) => m && m.areaId === areaId);
  if (existing) {
    return {
      areaId,
      manualWeightage,
      mainArea: existing.mainArea ?? area.mainArea ?? '',
      subAreas: existing.subAreas ?? [],
    };
  }
  const mainArea = area.mainArea || '';
  const areaName = String(area.areaName || '').toLowerCase();
  const sameMain = (oldMapped || []).filter(
    (m) => m && !m.areaId && String(m.mainArea || '').toLowerCase() === mainArea.toLowerCase()
  );
  let subAreas = [];
  if (sameMain.length) {
    const exact = sameMain.find((m) =>
      (m.subAreas || []).some((s) => String(s).trim().toLowerCase() === areaName)
    );
    if (exact) subAreas = [...(exact.subAreas || [])];
    else if (sameMain.some((m) => !m.subAreas || m.subAreas.length === 0)) subAreas = [];
    else subAreas = [...(sameMain[0].subAreas || [])];
  }
  return { areaId, manualWeightage, mainArea, subAreas };
}

function istNow() {
  return new Date(Date.now() + 5.5 * 60 * 60 * 1000);
}

class ExecutionSheetService {
  /* ---------- Template items ---------- */

  async getItems({ contractId, stationId, status = 'active' } = {}) {
    let query = db.collection('execution_sheet_items');
    if (status) query = query.where('status', '==', status);
    if (stationId) query = query.where('stationId', '==', stationId);
    const snapshot = await query.get();
    let items = [];
    snapshot.forEach((doc) => {
      const d = doc.data();
      if (contractId && d.contractId && d.contractId !== contractId) return;
      items.push({ id: doc.id, ...d });
    });
    items.sort((a, b) => (a.itemNo || 0) - (b.itemNo || 0));
    return { count: items.length, items };
  }

  async getItemById(uid) {
    const doc = await db.collection('execution_sheet_items').doc(uid).get();
    if (!doc.exists) throw new NotFoundError('Execution sheet item not found');
    return { id: doc.id, ...doc.data() };
  }

  async createItem(userData, body) {
    const { contractId, stationId, itemNo, weightage } = body;
    if (!contractId || !stationId || !itemNo) {
      throw new ValidationError('contractId, stationId, and itemNo are required');
    }
    if (weightage === undefined || weightage === null || isNaN(weightage)) {
      throw new ValidationError('weightage is required');
    }
    const stationDoc = await db.collection('stations').doc(stationId).get();
    if (!stationDoc.exists) throw new NotFoundError('Station not found');

    const existing = await db.collection('execution_sheet_items')
      .where('stationId', '==', stationId).where('itemNo', '==', parseInt(itemNo)).get();
    if (!existing.empty) throw new ValidationError(`Item ${itemNo} already exists for this station`);

    const ref = db.collection('execution_sheet_items').doc();
    const data = {
      uid: ref.id,
      contractId,
      stationId,
      stationName: stationDoc.data().stationName || '',
      itemNo: parseInt(itemNo),
      description: body.description || body.areaDetails || `Item ${itemNo}`,
      areaDetails: body.areaDetails || [],
      shiftMonitoring: body.shiftMonitoring || '',
      weightage: parseFloat(weightage),
      requiredFrequencyPerMonth: parseInt(body.requiredFrequencyPerMonth) || 0,
      status: 'active',
      createdBy: userData.uid,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    await ref.set(data);
    await auditService.logAudit('EXECUTION_SHEET_ITEM_CREATED', userData.uid, userData.fullName || 'User', ref.id, 'execution_sheet_items', `Execution sheet item ${itemNo} created`);
    return { message: 'Execution sheet item created', uid: ref.id, item: data };
  }

  async updateItem(uid, userData, body) {
    const ref = db.collection('execution_sheet_items').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Execution sheet item not found');
    const allowed = ['description', 'areaDetails', 'shiftMonitoring', 'weightage', 'requiredFrequencyPerMonth', 'status'];
    const updates = { updatedAt: new Date().toISOString() };
    for (const key of allowed) {
      if (body[key] !== undefined) {
        if (key === 'weightage') updates[key] = parseFloat(body[key]);
        else if (key === 'requiredFrequencyPerMonth') updates[key] = parseInt(body[key]);
        else updates[key] = body[key];
      }
    }
    await ref.update(updates);
    await auditService.logAudit('EXECUTION_SHEET_ITEM_UPDATED', userData.uid, userData.fullName || 'User', uid, 'execution_sheet_items', `Execution sheet item ${doc.data().itemNo} updated`);
    return { message: 'Execution sheet item updated', uid };
  }

  async deleteItem(uid, userData) {
    const ref = db.collection('execution_sheet_items').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Execution sheet item not found');
    await ref.update({ status: 'deleted', updatedAt: new Date().toISOString(), deletedBy: userData.uid });
    await auditService.logAudit('EXECUTION_SHEET_ITEM_DELETED', userData.uid, userData.fullName || 'User', uid, 'execution_sheet_items', `Execution sheet item ${doc.data().itemNo} deleted`);
    return { message: 'Execution sheet item deleted', uid };
  }

  /* ---------- Daily execution logs ---------- */

  _normalizeEntries(entries, itemsById = null) {
    if (!Array.isArray(entries)) throw new ValidationError('entries array is required');
    const byItem = {};
    for (const e of entries) {
      const itemNo = parseInt(e.itemNo);
      const status = (e.status || 'EXECUTED').toUpperCase();
      if (!itemNo) throw new ValidationError('Each entry needs a valid itemNo');
      if (!STATUS_SET.has(status)) throw new ValidationError(`Invalid status "${status}" for item ${itemNo}`);
      const entry = {
        itemNo,
        status,
        count: parseInt(e.count || (status === 'EXECUTED' ? 1 : 0), 10),
        remarks: e.remarks || '',
      };
      const item = itemsById ? itemsById[itemNo] : null;
      if (item) {
        const enriched = computeEntryExecution(entry, item);
        Object.assign(entry, enriched);
      }
      byItem[itemNo] = entry;
    }
    return byItem;
  }

  async saveDailySheet(userData, body) {
    const { contractId, stationId, date, shift } = body;
    if (!contractId || !stationId || !date) {
      throw new ValidationError('contractId, stationId, and date are required');
    }
    const itemsResult = stationId ? await this.getItems({ contractId, stationId }) : null;
    const itemsById = {};
    if (itemsResult) for (const it of itemsResult.items) itemsById[parseInt(it.itemNo, 10)] = it;
    const entries = this._normalizeEntries(body.entries || [], itemsById);

    // Upsert the daily log document for the given (station, date, shift).
    let query = db.collection('execution_sheet_daily_logs')
      .where('stationId', '==', stationId).where('date', '==', date);
    if (shift) query = query.where('shift', '==', shift);
    const existing = await query.get();

    const entriesArray = Object.values(entries).sort((a, b) => a.itemNo - b.itemNo);
    const now = new Date().toISOString();
    const payload = {
      contractId,
      stationId,
      date,
      shift: shift || 'full_day',
      entries: entriesArray,
      status: body.submit === true ? 'SUBMITTED' : 'DRAFT',
      submittedBy: body.submit === true ? userData.uid : null,
      submittedAt: body.submit === true ? now : null,
      updatedAt: now,
    };

    if (existing.empty) {
      const ref = db.collection('execution_sheet_daily_logs').doc();
      payload.uid = ref.id;
      payload.createdBy = userData.uid;
      payload.createdAt = now;
      await ref.set(payload);
      await auditService.logAudit('EXECUTION_SHEET_DAILY_SAVED', userData.uid, userData.fullName || 'User', ref.id, 'execution_sheet_daily_logs', `Daily execution sheet saved for ${date}${shift ? ' (' + shift + ')' : ''}`);
      return { message: 'Daily execution sheet saved', uid: ref.id, log: payload };
    }

    const ref = existing.docs[0].ref;
    const current = existing.docs[0].data();
    if (current.status === 'VERIFIED') {
      throw new ValidationError('Verified daily execution sheets are locked and cannot be modified');
    }
    const mergeStatus = (current.status === 'SUBMITTED' && body.submit !== true) ? 'SUBMITTED' : payload.status;
    if (mergeStatus === 'SUBMITTED' && !current.submittedBy) {
      payload.submittedBy = userData.uid;
      payload.submittedAt = now;
    } else {
      payload.submittedBy = current.submittedBy || null;
      payload.submittedAt = current.submittedAt || null;
    }
    payload.uid = current.uid || existing.docs[0].id;
    payload.status = mergeStatus;
    await ref.update(payload);
    await auditService.logAudit('EXECUTION_SHEET_DAILY_UPDATED', userData.uid, userData.fullName || 'User', ref.id, 'execution_sheet_daily_logs', `Daily execution sheet updated for ${date}${shift ? ' (' + shift + ')' : ''}`);
    return { message: 'Daily execution sheet saved', uid: ref.id, log: payload };
  }

  async submitDailySheet(uid, userData) {
    const ref = db.collection('execution_sheet_daily_logs').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Daily execution sheet not found');
    if (doc.data().status === 'VERIFIED') {
      throw new ValidationError('A verified daily execution sheet cannot be resubmitted');
    }
    await ref.update({ status: 'SUBMITTED', submittedBy: userData.uid, submittedAt: new Date().toISOString() });
    await auditService.logAudit('EXECUTION_SHEET_DAILY_SUBMITTED', userData.uid, userData.fullName || 'User', uid, 'execution_sheet_daily_logs', `Daily execution sheet submitted for ${doc.data().date}`);
    return { message: 'Daily execution sheet submitted', uid };
  }

  async verifyDailySheet(uid, userData) {
    const ref = db.collection('execution_sheet_daily_logs').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Daily execution sheet not found');
    const current = doc.data();
    if (current.status === 'DRAFT') {
      throw new ValidationError('Daily execution sheet must be submitted before it can be verified');
    }
    const now = new Date().toISOString();
    await ref.update({
      status: 'VERIFIED',
      verifiedBy: userData.uid,
      verifiedByName: userData.fullName || 'User',
      verifiedAt: now,
      updatedAt: now,
    });
    await auditService.logAudit('EXECUTION_SHEET_DAILY_VERIFIED', userData.uid, userData.fullName || 'User', uid, 'execution_sheet_daily_logs', `Daily execution sheet verified for ${current.date}`);
    return { message: 'Daily execution sheet verified', uid, verifiedByName: userData.fullName || 'User', verifiedAt: now };
  }

  async getDailySheet({ contractId, stationId, date, shift } = {}) {
    const itemsResult = await this.getItems({ contractId, stationId });
    const items = itemsResult.items;

    let query = db.collection('execution_sheet_daily_logs');
    if (stationId) query = query.where('stationId', '==', stationId);
    if (date) query = query.where('date', '==', date);
    const snapshot = await query.get();
    let logs = [];
    snapshot.forEach((doc) => logs.push({ id: doc.id, ...doc.data() }));
    if (shift) logs = logs.filter((l) => l.shift === shift);
    logs.sort((a, b) => (a.shift || '').localeCompare(b.shift || ''));

    // Merge entries with item metadata for the UI.
    const entryMap = {};
    for (const log of logs) {
      for (const e of log.entries || []) {
        entryMap[`${log.shift || 'full_day'}_${e.itemNo}`] = { ...e, logUid: log.id, logStatus: log.status, shift: log.shift || 'full_day' };
      }
    }
    const merged = items.map((item) => ({
      ...item,
      entries: entriesForShifts(entryMap, item.itemNo),
    }));

    return { date, shift: shift || null, items: merged, logs };
  }

  async listDailyLogs({ contractId, stationId, month, year, status, limit = 200 } = {}) {
    let query = db.collection('execution_sheet_daily_logs');
    if (stationId) query = query.where('stationId', '==', stationId);
    const snapshot = await query.limit(parseInt(limit) * 2).get();
    let logs = [];
    snapshot.forEach((doc) => {
      const d = doc.data();
      if (month && year) {
        const prefix = `${year}-${String(month).padStart(2, '0')}`;
        if (!(d.date || '').startsWith(prefix)) return;
      }
      if (status && d.status !== status) return;
      if (contractId && d.contractId !== contractId) return;
      logs.push({ id: doc.id, ...d });
    });
    logs.sort((a, b) => ((b.date || '') + (b.shift || '')).localeCompare((a.date || '') + (a.shift || '')));
    return { count: logs.length, logs };
  }

  /* ---------- Monthly score computation (50% billing component) ---------- */

  _expectedTimesForDay(area) {
    const boqTimes = parseInt(area?.boqTimesPerPeriod, 10) || 1;
    const freq = String(area?.cleaningFrequency || '').toLowerCase();
    switch (freq) {
      case 'weekly':
        // BoQ times per week, spread over 7 days.
        return boqTimes / 7;
      case 'monthly':
        // BoQ times per month, spread over the month; per executed day use per-day share.
        return boqTimes / 30;
      case 'daily':
      case 'twice_daily':
      case 'twice_daily_shift':
      case 'two_times_daily':
      case 'three_times_daily':
      case 'four_times_daily':
      case 'six_times_daily':
      case 'once_every_4h':
      default:
        // Times per day.
        return boqTimes;
    }
  }

  // Monthly BOQ requirement for one mapped area, straight from the area master:
  // daily = boqTimesPerPeriod per day, weekly/monthly scaled to the month.
  _expectedPassesForMonth(area, monthDays) {
    const freq = String(area?.cleaningFrequency || area?.frequency || '').toLowerCase();
    const boqTimes = parseInt(area?.boqTimesPerPeriod, 10) || 1;
    if (freq === 'monthly') return boqTimes;
    if (freq === 'weekly') return boqTimes * (monthDays / 7);
    const requiredPassesPerDay = Number(area?.requiredPassesPerDay) || 0;
    if (requiredPassesPerDay > 0) return requiredPassesPerDay * monthDays;
    return boqTimes * monthDays;
  }

  _matchesMappedArea(mapped, mainArea, subArea) {
    if (!mapped || !mapped.mainArea || !mainArea) return false;
    if (String(mapped.mainArea).trim().toLowerCase() !== String(mainArea).trim().toLowerCase()) return false;
    if (!mapped.subAreas || mapped.subAreas.length === 0) return true;
    if (!subArea) return false;
    const sub = String(subArea).trim().toLowerCase();
    return mapped.subAreas.some((s) => String(s).trim().toLowerCase() === sub);
  }

  async _fetchAreaExecution(stationId, month, year) {
    // Real area execution: submitted/approved supervisor shift summaries.
    const prefix = `${year}-${String(month).padStart(2, '0')}`;
    let snapshot;
    try {
      snapshot = await db.collection('stationShiftSummaries')
        .where('stationId', '==', stationId)
        .where('date', '>=', `${prefix}-01`)
        .where('date', '<=', `${prefix}-31`)
        .get();
    } catch {
      snapshot = await db.collection('stationShiftSummaries').where('stationId', '==', stationId).get();
    }
    const records = [];
    snapshot.forEach((doc) => {
      const d = doc.data();
      if (!(d.date || '').startsWith(prefix)) return;
      if (!['submitted', 'approved'].includes(d.status)) return;
      records.push(d);
    });
    return records;
  }

  async getMonthlySummary({ contractId, stationId, month, year } = {}) {
    if (!stationId || !month || !year) {
      throw new ValidationError('stationId, month, and year are required');
    }
    const itemsResult = await this.getItems({ contractId, stationId });
    const items = itemsResult.items;
    const prefix = `${year}-${String(month).padStart(2, '0')}`;

    const snapshot = await db.collection('execution_sheet_daily_logs')
      .where('stationId', '==', stationId)
      .get();
    const logs = [];
    snapshot.forEach((doc) => {
      const d = doc.data();
      if (d.date && d.date.startsWith(prefix) && ['SUBMITTED', 'VERIFIED'].includes(d.status)) logs.push(d);
    });

    const shiftSummaries = await this._fetchAreaExecution(stationId, month, year);
    const monthDays = daysInMonth(month, year);
    const itemScores = [];
    let executionScore = 0;

    // Area master supplies the contractual BOQ frequency for each mapped area.
    const areaMeta = {};
    try {
      const areasSnap = await db.collection('areas').where('stationId', '==', stationId).get();
      areasSnap.forEach((d) => { areaMeta[d.id] = { areaId: d.id, ...d.data() }; });
    } catch (_) { /* fall back to summary-carried frequency */ }

    for (const item of items) {
      const mappedAreas = item.mappedAreas || [];

      // Contractual monthly requirement from the BOQ (area master), not just
      // the days that happened to receive a summary.
      let boqExpected = 0;
      for (const m of mappedAreas) {
        const areaId = this._resolveStationAreaId(m, areaMeta);
        const area = areaId ? areaMeta[areaId] : null;
        if (!area) continue;
        const status = area.status === undefined ? 'active' : String(area.status).toLowerCase();
        if (status !== 'active') continue;
        boqExpected += this._expectedPassesForMonth(area, monthDays);
      }

      let manualActual = 0;
      let naCount = 0;
      for (const log of logs) {
        for (const e of log.entries || []) {
          if (parseInt(e.itemNo) !== item.itemNo) continue;
          if (e.status === 'N/A') { naCount++; continue; }
          if (e.status === 'EXECUTED') manualActual += e.count || 1;
          else if (e.status === 'PARTIAL') manualActual += (e.count || 0) * 0.5;
        }
      }

      // Area-based execution against BOQ frequency.
      // Expected (per mapped area, from cleaningFrequency x boqTimesPerPeriod) and
      // actual (sum of times actually cleaned across submitted shift summaries).
      let areaActual = 0;
      let areaExpected = 0;
      const daysExecuted = new Set();
      if (mappedAreas.length > 0) {
        // Expected frequency is per area per day, not per summary entry: a
        // shift-wise area can appear once per shift without tripling its BOQ
        // requirement. Actual times still accumulate across all shifts.
        const areaStats = new Map();
        for (const summary of shiftSummaries) {
          for (const a of summary.areas || []) {
            if (!mappedAreas.some((m) => this._matchesMappedArea(m, a.mainArea, a.areaName))) continue;
            const key = `${String(a.mainArea || '').trim().toLowerCase()}|${String(a.areaName || '').trim().toLowerCase()}`;
            let stat = areaStats.get(key);
            if (!stat) {
              stat = { actual: 0, dates: new Set(), expectedPerDay: this._expectedTimesForDay(a) };
              areaStats.set(key, stat);
            }
            stat.actual += parseInt(a.times, 10) || 0;
            stat.dates.add(summary.date);
            daysExecuted.add(summary.date);
          }
        }
        for (const stat of areaStats.values()) {
          areaActual += stat.actual;
          areaExpected += stat.expectedPerDay * stat.dates.size;
        }
      }

      const areaBased = mappedAreas.length > 0;
      // Contractual BOQ requirement first; fall back to observed frequency for
      // legacy items with no resolvable area master, then to the configured value.
      const required = boqExpected > 0
        ? boqExpected
        : (areaBased && areaExpected > 0 ? areaExpected : (item.requiredFrequencyPerMonth || 0));
      const actual = areaActual + manualActual;
      const notApplicable = naCount > 0;
      const achievedRatio = notApplicable || required <= 0
        ? 1
        : Math.min(actual / required, 1);
      const achievedWeight = Math.round(item.weightage * achievedRatio * 100) / 100;
      executionScore += achievedWeight;
      itemScores.push({
        itemNo: item.itemNo,
        description: item.description,
        areaDetails: item.areaDetails || [],
        mappedAreas,
        weightage: item.weightage,
        requiredFrequencyPerMonth: item.requiredFrequencyPerMonth || 0,
        expectedFrequency: Math.round(required * 10) / 10,
        actualFrequency: Math.round(actual * 10) / 10,
        areaExecution: areaActual,
        manualExecution: Math.round(manualActual * 10) / 10,
        frequencyShortfall: Math.round(Math.max(required - actual, 0) * 10) / 10,
        daysExecuted: daysExecuted.size,
        notApplicable,
        source: areaBased ? 'areas' : 'manual',
        achievedRatio: Math.round(achievedRatio * 1000) / 10,
        weightageAchieved: achievedWeight,
      });
    }

    executionScore = Math.round(Math.min(executionScore, 100) * 100) / 100;
    let contractValue = 0;
    if (contractId) {
      const contractDoc = await db.collection('contracts').doc(contractId).get();
      if (contractDoc.exists) contractValue = contractDoc.data().contractValue || 0;
    }
    const monthlyBase = Math.round(contractValue / 12);
    // 50% of billing depends on this execution score.
    const executionComponent = Math.round(monthlyBase * 0.50);
    const achievedAmount = Math.round(executionComponent * (executionScore / 100));
    const shortfallDeduction = executionComponent - achievedAmount;

    return {
      contractId, stationId, month: parseInt(month), year: parseInt(year),
      monthDays, daysLogged: new Set(logs.map((l) => l.date)).size,
      daysAreaExecuted: dayCount(shiftSummaries),
      logsCount: logs.length,
      shiftSummaryCount: shiftSummaries.length,
      itemScores,
      executionScore,
      monthlyBase,
      executionComponentNetBase: executionComponent,
      shortfallDeduction,
      achievedAmount,
    };
  }

  /* ---------- Area weightage management (ECR-SC-WEIGHT-2026-002) ---------- */

  /**
   * Resolve a mappedAreas entry to an areaId. Entries with an explicit
   * `areaId` pass through; legacy `{ mainArea, subAreas }` entries are matched
   * against the station's area metadata (read-side bridge, ECR §2.1).
   */
  _resolveStationAreaId(mapped, areaMeta) {
    if (!mapped) return null;
    if (mapped.areaId) return mapped.areaId;
    const mainArea = String(mapped.mainArea || '').trim().toLowerCase();
    if (!mainArea) return null;
    const subs = (mapped.subAreas || []).map((s) => String(s).trim().toLowerCase()).filter(Boolean);
    const matches = Object.values(areaMeta || {}).filter((a) => {
      if (String(a.mainArea || '').trim().toLowerCase() !== mainArea) return false;
      if (subs.length === 0) return true;
      const name = String(a.areaName || '').trim().toLowerCase();
      return subs.includes(name);
    });
    return matches.length ? matches[0].areaId || matches[0].id : null;
  }

  /**
   * GET weightage detail for one execution-sheet item.
   * Returns item meta, per-area rows (auto/manual/effective shares), totals,
   * and skippedAreas for missing/inactive/legacy-unmatched mappings.
   */
  async getItemWeightageDetail(uid) {
    const doc = await db.collection('execution_sheet_items').doc(uid).get();
    if (!doc.exists) throw new NotFoundError('Execution sheet item not found');
    const data = doc.data() || {};
    const item = { id: doc.id, uid: data.uid || doc.id, ...data };

    const skippedAreas = [];
    const rawMapped = Array.isArray(item.mappedAreas) ? item.mappedAreas : [];

    const areaMeta = {};
    if (item.stationId) {
      const areasSnap = await db.collection('areas').where('stationId', '==', item.stationId).get();
      areasSnap.forEach((d) => {
        areaMeta[d.id] = { areaId: d.id, ...d.data() };
      });
    }

    const refs = [];
    const seenIds = new Set();
    for (const m of rawMapped) {
      const areaId = this._resolveStationAreaId(m, areaMeta);
      if (!areaId) {
        skippedAreas.push({
          areaId: m.areaId || null,
          reason: `Legacy mapping "${m.mainArea || m.areaId || ''}" matched no station area`,
        });
        continue;
      }
      if (seenIds.has(areaId)) continue;
      seenIds.add(areaId);
      refs.push({ areaId, manualWeightage: m.manualWeightage ?? null });
    }

    const hydrated = [];
    for (const ref of refs) {
      const areaDoc = await db.collection('areas').doc(ref.areaId).get();
      const ha = hydrateArea(areaDoc);
      if (!ha) {
        skippedAreas.push({
          areaId: ref.areaId,
          reason: !areaDoc.exists ? 'Area not found' : 'Area is not active',
        });
        continue;
      }
      hydrated.push({ ...ha, _manual: ref.manualWeightage });
    }

    const splitBasis = item.splitBasis || 'sqft';
    const weightageMode = hydrated.some((h) => h._manual !== null && h._manual !== undefined && Number(h._manual) > 0)
      ? 'manual'
      : 'auto';

    const rows = [];
    let autoTotal = 0;
    let manualTotal = 0;
    let effectiveTotal = 0;
    for (const h of hydrated) {
      const share = areaShare({ basicAreaSqFt: h.basicAreaSqFt, unitCount: h.unitCount }, { splitBasis }, hydrated);
      const autoSharePct = round2(share * 100);
      const manualWeightage = h._manual !== null && h._manual !== undefined ? round2(Number(h._manual)) : null;
      const effectiveSharePct =
        weightageMode === 'manual' && manualWeightage !== null ? manualWeightage : autoSharePct;
      autoTotal += autoSharePct;
      if (manualWeightage !== null) manualTotal += manualWeightage;
      effectiveTotal += effectiveSharePct;
      rows.push({
        areaId: h.areaId,
        areaName: h.areaName,
        mainArea: h.mainArea,
        sectionName: h.sectionName,
        basicAreaSqFt: round2(h.basicAreaSqFt),
        unitCount: h.unitCount,
        unit: h.unit,
        requiredPassesPerDay: round2(h.requiredPassesPerDay),
        autoSharePct,
        manualWeightage,
        effectiveSharePct,
      });
    }

    const totals = {
      autoTotal: round2(autoTotal),
      manualTotal: round2(manualTotal),
      effectiveTotal: round2(effectiveTotal),
      autoValid: near100(autoTotal),
      manualValid: weightageMode === 'auto' ? true : near100(manualTotal),
    };

    return {
      count: rows.length,
      rows,
      skippedAreas,
      item: {
        id: item.id,
        uid: item.uid,
        itemNo: item.itemNo,
        description: item.description || '',
        weightage: item.weightage,
        splitBasis,
        weightageMode,
        requiredFrequencyPerMonth: item.requiredFrequencyPerMonth || 0,
        contractId: item.contractId || null,
        stationId: item.stationId || null,
      },
      totals,
    };
  }

  /**
   * PUT — save manual/auto area weightages for one item.
   * All-or-nothing validation (I1–I4) runs before any write; hybrid
   * { areaId, manualWeightage, mainArea, subAreas } entries are persisted so
   * getMonthlySummary keeps matching on mainArea/subAreas (C3).
   */
  async updateItemWeightages(uid, userData, body) {
    const ref = db.collection('execution_sheet_items').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Execution sheet item not found');
    const item = doc.data() || {};

    const list = body?.mappedAreas;
    if (!Array.isArray(list)) throw new ValidationError('mappedAreas must be an array');
    if (list.length === 0) throw new ValidationError('Item must map to at least one area');

    const seen = new Set();
    const normalized = list.map((entry) => {
      const areaId = entry?.areaId;
      if (!areaId || typeof areaId !== 'string') throw new ValidationError('Each mapped area requires an areaId');
      if (seen.has(areaId)) throw new ValidationError(`Area ${areaId} is already mapped to this item`);
      seen.add(areaId);
      let manualWeightage = null;
      if (entry.manualWeightage !== null && entry.manualWeightage !== undefined && entry.manualWeightage !== '') {
        manualWeightage = Number(entry.manualWeightage);
        if (!Number.isFinite(manualWeightage)) {
          throw new ValidationError(`manualWeightage for area ${areaId} must be a number`);
        }
        if (manualWeightage < 0 || manualWeightage > 100) {
          throw new ValidationError(`manualWeightage must be between 0 and 100 (got ${manualWeightage})`);
        }
      }
      return { areaId, manualWeightage };
    });

    const withManual = normalized.filter((e) => e.manualWeightage !== null);
    const withoutManual = normalized.filter((e) => e.manualWeightage === null);
    if (withManual.length > 0 && withoutManual.length > 0) {
      throw new ValidationError(
        'Mixed manual/auto not allowed. Either set manualWeightage on EVERY mapped area, or none.'
      );
    }
    if (withManual.length > 0) {
      const total = round2(withManual.reduce((sum, e) => sum + e.manualWeightage, 0));
      if (!near100(total)) {
        throw new ValidationError(`Manual area weightages sum to ${total}%; must equal 100% (tolerance ±0.01)`);
      }
    }

    const areaDocs = {};
    for (const e of normalized) {
      const areaDoc = await db.collection('areas').doc(e.areaId).get();
      if (!areaDoc.exists) throw new NotFoundError(`Area ${e.areaId} not found`);
      const areaData = areaDoc.data() || {};
      const status = areaData.status === undefined ? 'active' : String(areaData.status).toLowerCase();
      if (status !== 'active') throw new ValidationError(`Area ${e.areaId} is not active`);
      areaDocs[e.areaId] = areaData;
    }

    const oldMapped = Array.isArray(item.mappedAreas) ? item.mappedAreas : [];
    const weightageMode = withManual.length > 0 ? 'manual' : 'auto';
    const entries = normalized.map((e) =>
      attachEngineFields(e.areaId, e.manualWeightage, areaDocs[e.areaId], oldMapped)
    );
    const splitBasis =
      body.splitBasis !== undefined && body.splitBasis !== null && body.splitBasis !== ''
        ? String(body.splitBasis)
        : item.splitBasis || 'sqft';

    await ref.update({
      mappedAreas: entries,
      splitBasis,
      weightageMode,
      updatedAt: new Date().toISOString(),
    });
    await auditService.logAudit(
      'EXECUTION_ITEM_WEIGHTAGES_UPDATED',
      userData.uid,
      userData.fullName || 'User',
      uid,
      'execution_sheet_items',
      `Item ${item.itemNo} area weightages updated (${weightageMode})`
    );
    return { message: 'Item area weightages updated', uid, weightageMode, splitBasis, count: entries.length };
  }

  /** POST — clear all manual weights (auto split). Engine fields preserved. */
  async resetItemWeightages(uid, userData) {
    const ref = db.collection('execution_sheet_items').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Execution sheet item not found');
    const item = doc.data() || {};
    const oldMapped = Array.isArray(item.mappedAreas) ? item.mappedAreas : [];
    const entries = oldMapped.map((m) => ({ ...(m || {}), manualWeightage: null }));
    await ref.update({ mappedAreas: entries, weightageMode: 'auto', updatedAt: new Date().toISOString() });
    await auditService.logAudit(
      'EXECUTION_ITEM_WEIGHTAGES_RESET',
      userData.uid,
      userData.fullName || 'User',
      uid,
      'execution_sheet_items',
      `Item ${item.itemNo} area weightages reset to auto`
    );
    return { message: 'Item area weightages reset to auto', uid, weightageMode: 'auto', count: entries.length };
  }

  /** POST — map an area; new area starts on auto (wasManual flags prior manual state). */
  async addMappedArea(uid, userData, body) {
    const areaId = body?.areaId;
    if (!areaId || typeof areaId !== 'string') throw new ValidationError('areaId is required');
    const ref = db.collection('execution_sheet_items').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Execution sheet item not found');
    const item = doc.data() || {};
    const oldMapped = Array.isArray(item.mappedAreas) ? item.mappedAreas : [];
    if (oldMapped.some((m) => m && m.areaId === areaId)) {
      throw new ValidationError(`Area ${areaId} is already mapped to this item`);
    }

    const areaDoc = await db.collection('areas').doc(areaId).get();
    if (!areaDoc.exists) throw new NotFoundError(`Area ${areaId} not found`);
    const areaData = areaDoc.data() || {};
    const status = areaData.status === undefined ? 'active' : String(areaData.status).toLowerCase();
    if (status !== 'active') throw new ValidationError(`Area ${areaId} is not active`);

    const wasManual = oldMapped.some((m) => m && m.manualWeightage !== null && m.manualWeightage !== undefined);
    const entry = attachEngineFields(areaId, null, areaData, oldMapped);
    const weightageMode = wasManual ? 'manual' : 'auto';
    await ref.update({
      mappedAreas: [...oldMapped, entry],
      weightageMode,
      updatedAt: new Date().toISOString(),
    });
    await auditService.logAudit(
      'EXECUTION_ITEM_AREA_ADDED',
      userData.uid,
      userData.fullName || 'User',
      uid,
      'execution_sheet_items',
      `Area ${areaId} mapped to item ${item.itemNo}`
    );
    return { message: 'Area mapped to item', uid, areaId, wasManual, weightageMode };
  }

  /** DELETE — unmap an area; last remaining area is protected (I3). */
  async removeMappedArea(uid, userData, areaId) {
    if (!areaId) throw new ValidationError('areaId is required');
    const ref = db.collection('execution_sheet_items').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Execution sheet item not found');
    const item = doc.data() || {};
    const oldMapped = Array.isArray(item.mappedAreas) ? item.mappedAreas : [];
    const target = oldMapped.find((m) => m && m.areaId === areaId);
    if (!target) throw new ValidationError(`Area ${areaId} is not mapped to this item`);
    if (oldMapped.length <= 1) {
      throw new ValidationError('Cannot remove the last area; item must map to at least one area');
    }
    const wasManual = target.manualWeightage !== null && target.manualWeightage !== undefined;
    const entries = oldMapped.filter((m) => !(m && m.areaId === areaId));
    const weightageMode = entries.some((m) => m && m.manualWeightage !== null && m.manualWeightage !== undefined)
      ? 'manual'
      : 'auto';
    await ref.update({ mappedAreas: entries, weightageMode, updatedAt: new Date().toISOString() });
    await auditService.logAudit(
      'EXECUTION_ITEM_AREA_REMOVED',
      userData.uid,
      userData.fullName || 'User',
      uid,
      'execution_sheet_items',
      `Area ${areaId} unmapped from item ${item.itemNo}`
    );
    return { message: 'Area unmapped from item', uid, areaId, wasManual, weightageMode };
  }

  /**
   * GET — active station areas not yet mapped to this item.
   * Queries where(stationId) only (equality merge, no composite index) and
   * filters status/sectionName/q in memory (ECR §2.3 documented shape).
   */
  async listAvailableAreas(uid, query = {}) {
    const doc = await db.collection('execution_sheet_items').doc(uid).get();
    if (!doc.exists) throw new NotFoundError('Execution sheet item not found');
    const item = doc.data() || {};
    const mappedIds = new Set(
      (Array.isArray(item.mappedAreas) ? item.mappedAreas : [])
        .map((m) => (m && m.areaId) || null)
        .filter(Boolean)
    );

    let q = db.collection('areas');
    if (item.stationId) q = q.where('stationId', '==', item.stationId);
    const snap = await q.limit(500).get();
    const sectionFilter = query.sectionName !== undefined && query.sectionName !== null && query.sectionName !== ''
      ? String(query.sectionName)
      : null;
    const textFilter = query.q ? String(query.q).trim().toLowerCase() : null;

    const areas = [];
    snap.forEach((d) => {
      const a = d.data() || {};
      const status = a.status === undefined ? 'active' : String(a.status).toLowerCase();
      if (status !== 'active') return;
      if (mappedIds.has(d.id)) return;
      const sectionName = a.sectionName ?? a.section ?? '';
      if (sectionFilter !== null && String(sectionName) !== sectionFilter) return;
      if (textFilter) {
        const hay = `${a.areaName || ''} ${a.mainArea || ''} ${sectionName}`.toLowerCase();
        if (!hay.includes(textFilter)) return;
      }
      const basicAreaSqFt = Number(a.basicAreaSqFt) || 0;
      const unitCount = Number(a.unitCount) || 0;
      const tenderedAreaPerDay = Number(a.tenderedAreaPerDay) || 0;
      let requiredPassesPerDay = Number(a.requiredPassesPerDay) || 0;
      if (!(requiredPassesPerDay > 0)) {
        requiredPassesPerDay =
          basicAreaSqFt > 0 && tenderedAreaPerDay > 0
            ? tenderedAreaPerDay / basicAreaSqFt
            : passesPerDay(a);
      }
      areas.push({
        areaId: d.id,
        areaName: a.areaName || '',
        mainArea: a.mainArea || '',
        sectionName,
        basicAreaSqFt: round2(basicAreaSqFt),
        unitCount,
        unit: a.unit || 'sqft',
        requiredPassesPerDay: round2(requiredPassesPerDay),
      });
    });
    areas.sort((a, b) => String(a.areaName).localeCompare(String(b.areaName)));
    return { count: areas.length, areas };
  }

  /**
   * GET — read-only deduction preview (scope A, ECR §4).
   * dailyItemValue = ACV × weightage / 100 / 365
   * areaDailyValue = dailyItemValue × effectiveShare / 100
   * valuePerPass   = areaDailyValue / requiredPasses (required ≥ 1)
   */
  async previewItemWeightage(uid, query = {}) {
    const detail = await this.getItemWeightageDetail(uid);
    let month = parseInt(query.month, 10);
    let year = parseInt(query.year, 10);
    if (!month || !year) {
      const ist = istNow();
      if (!month) month = ist.getUTCMonth() + 1;
      if (!year) year = ist.getUTCFullYear();
    }
    if (month < 1 || month > 12) throw new ValidationError('month must be between 1 and 12');
    const monthDays = daysInMonth(month, year);
    const item = detail.item;

    let annualContractValue = 0;
    if (item.contractId) {
      const contractDoc = await db.collection('contracts').doc(item.contractId).get();
      if (contractDoc.exists) {
        const contract = contractDoc.data() || {};
        annualContractValue = Number(contract.annualContractValue ?? contract.contractValue) || 0;
      }
    }
    const dailyItemValue = round2((annualContractValue * (Number(item.weightage) || 0)) / 100 / 365);

    const rows = detail.rows.map((r) => {
      const effectiveShare = Number(r.effectiveSharePct) || 0;
      const areaDailyValue = round2((dailyItemValue * effectiveShare) / 100);
      const requiredPasses = Math.max(1, Math.round(Number(r.requiredPassesPerDay) || 0));
      const valuePerPass = requiredPasses > 0 ? round2(areaDailyValue / requiredPasses) : 0;
      return {
        ...r,
        areaDailyValue,
        requiredPasses,
        valuePerPass,
        monthlyBaseValue: round2(areaDailyValue * monthDays),
      };
    });

    const totals = {
      ...detail.totals,
      dailyItemValue,
      areaDailyTotal: round2(rows.reduce((sum, r) => sum + r.areaDailyValue, 0)),
      monthlyBaseTotal: round2(rows.reduce((sum, r) => sum + r.monthlyBaseValue, 0)),
    };

    return {
      itemId: uid,
      itemNo: item.itemNo,
      month: parseInt(month, 10),
      year: parseInt(year, 10),
      monthDays,
      weightage: item.weightage,
      splitBasis: item.splitBasis,
      weightageMode: item.weightageMode,
      annualContractValue: round2(annualContractValue),
      rows,
      totals,
      skippedAreas: detail.skippedAreas,
    };
  }
}

function dayCount(summaries) {
  return new Set(summaries.map((s) => s.date)).size;
}

/* Compute the per-day scheduled/actual execution snapshot for a single log entry.
 * This is a normalized information snapshot stored on the execution record; the
 * authoritative monthly deduction is computed centrally per billing period.
 */
function computeEntryExecution(entry, item) {
  const weightage = parseFloat(item.weightage) || 0;
  const monthlyRequired = parseInt(item.requiredFrequencyPerMonth, 10) || 0;
  const scheduled = Math.round((monthlyRequired / 30) * 10) / 10;
  if (entry.status === 'N/A') {
    return {
      scheduled: roundMoney(scheduled),
      actual: 0,
      executionPercentage: 100,
      achievedWeightage: weightage,
      shortfall: 0,
      notApplicable: true,
    };
  }
  const actual = entry.status === 'EXECUTED'
    ? (entry.count || 1)
    : entry.status === 'PARTIAL'
      ? (entry.count || 0) * 0.5
      : 0;
  const ratio = scheduled > 0 ? ratioSafe(actual, scheduled) : 1;
  return {
    scheduled: roundMoney(scheduled),
    actual: Math.round(actual * 10) / 10,
    executionPercentage: clampPct(ratio * 100),
    achievedWeightage: roundMoney(weightage * Math.min(ratio, 1)),
    shortfall: roundMoney(Math.max(scheduled - actual, 0)),
    notApplicable: false,
  };
}

function entriesForShifts(entryMap, itemNo) {
  const result = [];
  for (const key of Object.keys(entryMap)) {
    if (key.endsWith(`_${itemNo}`)) result.push(entryMap[key]);
  }
  return result;
}

export const executionSheetService = new ExecutionSheetService();