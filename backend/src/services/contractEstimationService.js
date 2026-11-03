/*
 * Contract Estimation, Variation & Supplementary Work Order engine.
 *
 * Estimation (Reqs 1-9):
 *  - Area-quantity × applicable frequency → quantity per day
 *  - quantity-per-day × rate → cost per day
 *  - cost-per-day × applicable days → estimated cost (contract/value derived
 *    from actual start/end dates, never a hardcoded period)
 *  - Supports pest/rodent (different unit/frequency model), non-area system
 *    items (e.g. computerized feedback, "System/Year"), NS-1/NS-2 style
 *    additional items, and multiple stations/areas on one contract.
 *  - Frequencies are configurable per item/area (`frequency.type` + times).
 *
 * Variation (Reqs 10-12):
 *  - Versioned variation statements that preserve the original contract value;
 *    reductions are recorded against an effective date, the old period stays
 *    historically intact, and amended value = original - savings + additional
 *    work - recoveries.
 *
 * SWO (Req 13):
 *  - Multiple supplementary work orders referencing the parent contract; each
 *    carries its own items (qty × rate = amount) and period.
 *
 * Period billing (Req 14-15): applicable days inside any billing period are
 * computed with `overlappingDays`, so mid-period start/end items only bill
 * their active days.
 */

import { db } from '../database/index.js';
import { NotFoundError, ValidationError } from '../errors/index.js';
import { auditService } from './auditService.js';
import { roundMoney, mulMoney, ratioSafe } from '../utils/money.js';
import { computeContractDays, overlappingDays, monthRange, parseDate } from '../utils/period.js';

const FREQ_TYPES = new Set(['daily', 'weekly', 'monthly', 'periodic', 'once', 'as_required']);

/* ─────────────────────────── Pure calculation helpers ─────────────────────── */

/* Times-per-day from a configurable frequency descriptor. */
export function frequencyTimesPerDay(frequency) {
  if (!frequency || typeof frequency !== 'object') return 1;
  const type = String(frequency.type || 'daily').toLowerCase();
  switch (type) {
    case 'once': return 0; // one-time execution; quantity used directly
    case 'as_required': return 0;
    case 'weekly':
      return ratioSafe(parseInt(frequency.timesPerWeek, 10) || 0, 7);
    case 'monthly':
      return ratioSafe(parseInt(frequency.timesPerMonth, 10) || 0, 30);
    case 'periodic':
      return ratioSafe(parseInt(frequency.timesPerPeriod, 10) || 0, parseInt(frequency.periodDays, 10) || 30);
    case 'daily':
    default:
      return Math.max(parseInt(frequency.timesPerDay, 10) || 1, 1);
  }
}

/*
 * Estimation for one item.
 * - Area-based: quantityPerDay = area(quantity) × applicable frequency.
 * - One-time/as-required/pest treatment: quantity applied once (or quantity ×
 *   number of treatments) regardless of the period; estimated from
 *   quantity × rate over its applicable days only when daysPresent > 0.
 */
export function computeItemEstimate({
  quantity = 0,
  frequency = { type: 'daily', timesPerDay: 1 },
  rate = 0,
  contractDays = 1,
  applicableDays = contractDays,
  isPestControl = false,
  treatments = 0,
}) {
  const qty = typeof quantity === 'number' ? quantity : parseFloat(quantity) || 0;
  const r = typeof rate === 'number' ? rate : parseFloat(rate) || 0;
  if (qty < 0 || r < 0) throw new ValidationError('quantity and rate cannot be negative');
  const type = String(frequency?.type || 'daily').toLowerCase();
  const once = type === 'once' || type === 'as_required';
  const timesPerDay = once ? 0 : frequencyTimesPerDay(frequency);
  const quantityPerDay = once
    ? 0
    : roundMoney(qty * timesPerDay);
  const costPerDay = once ? 0 : roundMoney(quantityPerDay * r);
  const days = Math.max(parseInt(applicableDays, 10) || 0, 0);
  let estimatedCost;
  if (isPestControl || once) {
    const occurrences = isPestControl ? Math.max(parseInt(treatments, 10) || 0, 0) : 1;
    estimatedCost = roundMoney(qty * occurrences * r);
  } else {
    estimatedCost = roundMoney(costPerDay * days);
  }
  return {
    quantity: qty,
    frequency: { type, timesPerDay, ...frequency },
    rate: r,
    once,
    quantityPerDay,
    costPerDay,
    applicableDays: days,
    estimatedCost,
  };
}

/*
 * Variation statement (Req 10-12).
 * amended = original − savings(reduced scope) + additionalWork + excess − recovery.
 */
export function computeVariationStatement({
  originalContractValue = 0,
  executedOriginalValue = originalContractValue,
  reductionValue = 0,
  additionalWorkValue = 0,
  excessExecutionValue = 0,
  recoveryDeductions = 0,
}) {
  const original = roundMoney(originalContractValue);
  const executed = roundMoney(Math.min(executedOriginalValue, original));
  const saving = roundMoney(Math.min(reductionValue >= 0 ? reductionValue : 0, original - executed));
  const additional = roundMoney(additionalWorkValue >= 0 ? additionalWorkValue : 0);
  const excess = roundMoney(excessExecutionValue >= 0 ? excessExecutionValue : 0);
  const recovery = roundMoney(recoveryDeductions >= 0 ? recoveryDeductions : 0);
  const revisedScopeValue = roundMoney(original - saving);
  const amended = roundMoney(Math.max(original - saving + additional + excess - recovery, 0));
  return { originalContractValue: original, executedOriginalValue: executed, reductionValue: saving, savings: saving, additionalWorkValue: additional, excessExecutionValue: excess, recoveryDeductions: recovery, revisedScopeValue, netVariation: roundMoney(amended - original), amendedContractValue: amended };
}

/* SWO total (Req 13): Σ item.amount or qty × rate. */
export function computeSwoValue(items = []) {
  let total = 0;
  const lines = items.map((it) => {
    const qty = parseFloat(it.quantity) || 0;
    const rate = parseFloat(it.rate) || 0;
    const amount = it.amount !== undefined && it.amount !== null && it.amount !== ''
      ? parseFloat(it.amount)
      : roundMoney(qty * rate);
    total += amount;
    return {
      description: it.description || '',
      quantity: qty,
      unit: it.unit || '',
      rate,
      amount: roundMoney(amount),
    };
  });
  return { lines, totalValue: roundMoney(total) };
}

/* ─────────────────────────── Service ──────────────────────────────────────── */

class ContractEstimationService {
  /* ---------- Estimate items ---------- */

  async getEstimateItems({ contractId, stationId, status = 'active' } = {}) {
    const snap = await db.collection('contract_estimate_items').get();
    const items = [];
    snap.forEach((doc) => {
      const d = doc.data();
      if (status && d.status !== status) return;
      if (contractId && d.contractId !== contractId) return;
      if (stationId && d.stationId !== stationId) return;
      items.push({ id: doc.id, ...d });
    });
    items.sort((a, b) => (a.itemNo || 0) - (b.itemNo || 0) || (a.description || '').localeCompare(b.description || ''));
    const stationTotals = {};
    const categoryTotals = {};
    let totalEstimatedCost = 0;
    for (const it of items) {
      const cost = parseFloat(it.estimatedCost) || 0;
      totalEstimatedCost += cost;
      const key = it.stationName || it.stationId || '—';
      stationTotals[key] = roundMoney((stationTotals[key] || 0) + cost);
      const cat = it.category || 'other';
      categoryTotals[cat] = roundMoney((categoryTotals[cat] || 0) + cost);
    }
    return {
      count: items.length,
      items,
      totalEstimatedCost: roundMoney(totalEstimatedCost),
      stationTotals,
      categoryTotals,
    };
  }

  async createEstimateItem(userData, body) {
    const { contractId, description } = body;
    if (!contractId || !description) throw new ValidationError('contractId and description are required');
    const contractDoc = await db.collection('contracts').doc(contractId).get();
    if (!contractDoc.exists) throw new NotFoundError('Contract not found');
    const contract = contractDoc.data();
    const contractDays = computeContractDays(contract.startDate, contract.endDate);
    if (contractDays <= 0) throw new ValidationError('Contract start/end dates are invalid; cannot estimate');

    const itemStart = body.startDate || contract.startDate;
    const itemEnd = body.endDate || contract.endDate;
    const nsDays = body.additionalDays !== undefined && body.additionalDays !== null && body.additionalDays !== ''
      ? parseInt(body.additionalDays, 10)
      : computeContractDays(itemStart, itemEnd);
    const applicableDays = body.applicableDays !== undefined && body.applicableDays !== ''
      ? parseInt(body.applicableDays, 10)
      : nsDays;

    const calc = computeItemEstimate({
      quantity: body.quantity ?? body.area,
      frequency: body.frequency || { type: 'daily', timesPerDay: 1 },
      rate: body.rate,
      contractDays,
      applicableDays,
      isPestControl: String(body.category || '').toLowerCase() === 'pest_control' || body.isPestControl === true,
      treatments: body.treatments,
    });

    const ref = db.collection('contract_estimate_items').doc();
    const now = new Date().toISOString();
    const data = {
      uid: ref.id,
      contractId,
      contractNumber: contract.contractNumber || '',
      stationId: body.stationId || body.stationIds?.[0] || contract.stationIds?.[0] || '',
      stationName: body.stationName || '',
      category: body.category || 'cleaning',
      itemNo: body.itemNo || 0,
      description,
      area: body.area || '',
      quantity: body.quantity ?? body.area ?? 0,
      unit: body.unit || 'sq.ft.',
      unitBasis: body.unitBasis || 'sq.ft.',
      frequency: body.frequency || { type: 'daily', timesPerDay: 1 },
      rate: calc.rate,
      quantityPerDay: calc.quantityPerDay,
      costPerDay: calc.costPerDay,
      startDate: itemStart || '',
      endDate: itemEnd || '',
      applicableDays: calc.applicableDays,
      estimatedCost: calc.estimatedCost,
      isPestControl: calc.once && String(body.category || '').toLowerCase() === 'pest_control',
      isAdditional: body.isAdditional === true,
      nsRef: body.nsRef || '',
      additionalDays: calc.applicableDays,
      approvalStatus: body.approvalStatus || body.status || 'PENDING',
      approvedRef: body.approvedRef || '',
      status: 'active',
      createdBy: userData.uid,
      createdAt: now,
      updatedAt: now,
    };
    await ref.set(data);
    await auditService.logAudit('CONTRACT_ESTIMATE_ITEM_CREATED', userData.uid, userData.fullName || 'User', ref.id, 'contract_estimate_items', `Estimate item "${description}" created (₹${calc.estimatedCost})`);
    return { message: 'Estimate item created', uid: ref.id, item: data };
  }

  async updateEstimateItem(uid, userData, body) {
    const ref = db.collection('contract_estimate_items').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Estimate item not found');
    const current = { id: doc.id, ...doc.data() };
    const merged = { ...current, ...body };
    const contract = (await db.collection('contracts').doc(current.contractId).get()).data();
    const contractDays = computeContractDays(contract.startDate, contract.endDate);
    const calc = computeItemEstimate({
      quantity: merged.quantity ?? merged.area ?? 0,
      frequency: merged.frequency || { type: 'daily', timesPerDay: 1 },
      rate: merged.rate || 0,
      contractDays: contractDays || 1,
      applicableDays: merged.applicableDays ?? merged.additionalDays ?? (computeContractDays(merged.startDate, merged.endDate) || contractDays || 1),
    });
    const updates = {
      description: merged.description,
      stationName: merged.stationName || '',
      category: merged.category || 'cleaning',
      area: merged.area || '',
      quantity: merged.quantity ?? merged.area ?? 0,
      unit: merged.unit || '',
      unitBasis: merged.unitBasis || '',
      frequency: merged.frequency || { type: 'daily', timesPerDay: 1 },
      rate: calc.rate,
      quantityPerDay: calc.quantityPerDay,
      costPerDay: calc.costPerDay,
      startDate: merged.startDate || '',
      endDate: merged.endDate || '',
      applicableDays: calc.applicableDays,
      estimatedCost: calc.estimatedCost,
      isAdditional: merged.isAdditional === true,
      nsRef: merged.nsRef || '',
      approvalStatus: merged.approvalStatus || 'PENDING',
      approvedRef: merged.approvedRef || '',
      updatedBy: userData.uid,
      updatedAt: new Date().toISOString(),
    };
    await ref.update(updates);
    await auditService.logAudit('CONTRACT_ESTIMATE_ITEM_UPDATED', userData.uid, userData.fullName || 'User', uid, 'contract_estimate_items', `Estimate item "${updatedEstimateLabel(current, updates)}" updated (₹${calc.estimatedCost})`);
    return { message: 'Estimate item updated', uid };
  }

  async deleteEstimateItem(uid, userData) {
    const ref = db.collection('contract_estimate_items').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('Estimate item not found');
    await ref.update({ status: 'deleted', deletedBy: userData.uid, updatedAt: new Date().toISOString() });
    await auditService.logAudit('CONTRACT_ESTIMATE_ITEM_DELETED', userData.uid, userData.fullName || 'User', uid, 'contract_estimate_items', `Estimate item "${doc.data().description}" deleted`);
    return { message: 'Estimate item deleted', uid };
  }

  /* ---------- Variation / recovery statements ---------- */

  async getVariations({ contractId } = {}) {
    const snap = await db.collection('contract_variations').get();
    const plans = [];
    snap.forEach((doc) => {
      const d = doc.data();
      if (contractId && d.contractId !== contractId) return;
      plans.push({ id: doc.id, ...d });
    });
    plans.sort((a, b) => (a.revisionNo || 1) - (b.revisionNo || 1));
    const latest = plans[plans.length - 1] || null;
    return { count: plans.length, revisions: plans, latest };
  }

  async createVariation(userData, body) {
    const { contractId } = body;
    if (!contractId) throw new ValidationError('contractId is required');
    const contractDoc = await db.collection('contracts').doc(contractId).get();
    if (!contractDoc.exists) throw new NotFoundError('Contract not found');
    const contract = contractDoc.data();
    const existing = await this.getVariations({ contractId });
    const baseOriginal = body.originalContractValue ?? contract.contractValue ?? 0;
    // Reduce off the previous revised scope value, never the original contract.
    const prev = existing.latest;
    const previousScope = prev ? prev.revisedScopeValue : baseOriginal;
    const calc = computeVariationStatement({
      originalContractValue: baseOriginal,
      executedOriginalValue: body.executedOriginalValue ?? previousScope,
      reductionValue: body.reductionValue ?? body.savings ?? 0,
      additionalWorkValue: body.additionalWorkValue ?? 0,
      excessExecutionValue: body.excessExecutionValue ?? 0,
      recoveryDeductions: body.recoveryDeductions ?? 0,
    });
    const requestedReduction = Math.max(0, parseFloat(body.reductionValue ?? body.savings ?? 0) || 0);
    if (requestedReduction > calc.executedOriginalValue) {
      throw new ValidationError('Reduction exceeds the executed scope value');
    }
    const ref = db.collection('contract_variations').doc();
    const now = new Date().toISOString();
    const data = {
      uid: ref.id,
      contractId,
      contractNumber: contract.contractNumber || '',
      revisionNo: (existing.latest?.revisionNo || 0) + 1,
      effectiveDate: body.effectiveDate || now.slice(0, 10),
      description: body.description || `Variation revision ${(existing.latest?.revisionNo || 0) + 1}`,
      originalContractValue: roundMoney(baseOriginal),
      executedOriginalValue: calc.executedOriginalValue,
      reductionValue: calc.reductionValue,
      savings: calc.savings,
      additionalWorkValue: calc.additionalWorkValue,
      excessExecutionValue: calc.excessExecutionValue,
      recoveryDeductions: calc.recoveryDeductions,
      revisedScopeValue: calc.revisedScopeValue,
      netVariation: calc.netVariation,
      amendedContractValue: calc.amendedContractValue,
      reducedAreaEffectiveDate: body.reducedAreaEffectiveDate || '',
      originalAreaTotal: parseFloat(body.originalAreaTotal) || 0,
      reducedAreaTotal: parseFloat(body.reducedAreaTotal) || 0,
      status: body.status || 'APPROVED',
      createdBy: userData.uid,
      createdAt: now,
      updatedAt: now,
    };
    await ref.set(data);
    await auditService.logAudit('CONTRACT_VARIATION_CREATED', userData.uid, userData.fullName || 'User', ref.id, 'contract_variations', `Variation revision ${data.revisionNo} created for ${contractId} (amended ₹${calc.amendedContractValue})`);
    return { message: 'Variation statement created', uid: ref.id, variation: data };
  }

  /* ---------- Supplementary work orders ---------- */

  async getSWOs({ contractId, status } = {}) {
    const snap = await db.collection('contract_swos').get();
    const list = [];
    snap.forEach((doc) => {
      const d = doc.data();
      if (contractId && d.contractId !== contractId) return;
      if (status && d.status !== status) return;
      list.push({ id: doc.id, ...d });
    });
    list.sort((a, b) => (a.swoNumber || '').localeCompare(b.swoNumber || ''));
    const totalSwoValue = list.reduce((s, w) => s + (parseFloat(w.totalValue) || 0), 0);
    return { count: list.length, totalSwoValue: roundMoney(totalSwoValue), swos: list };
  }

  async createSWO(userData, body) {
    const { contractId, swoNumber } = body;
    if (!contractId || !swoNumber) throw new ValidationError('contractId and swoNumber are required');
    const contractDoc = await db.collection('contracts').doc(contractId).get();
    if (!contractDoc.exists) throw new NotFoundError('Contract not found');
    const contract = contractDoc.data();

    const existingSnap = await db.collection('contract_swos')
      .where('contractId', '==', contractId).where('swoNumber', '==', swoNumber).limit(1).get();
    if (!existingSnap.empty) throw new ValidationError(`SWO ${swoNumber} already exists for this contract`);

    const startDate = body.startDate || contract.startDate;
    const endDate = body.endDate || contract.endDate;
    const contractDays = computeContractDays(startDate, endDate);
    if (contractDays <= 0) throw new ValidationError('SWO period is invalid');
    const value = computeSwoValue(Array.isArray(body.items) ? body.items : []);

    const ref = db.collection('contract_swos').doc();
    const now = new Date().toISOString();
    const data = {
      uid: ref.id,
      contractId,
      contractNumber: contract.contractNumber || '',
      swoNumber,
      description: body.description || '',
      startDate,
      endDate,
      contractDays,
      items: value.lines,
      totalValue: value.totalValue,
      status: body.status || 'APPROVED',
      createdBy: userData.uid,
      createdAt: now,
      updatedAt: now,
    };
    await ref.set(data);
    await auditService.logAudit('CONTRACT_SWO_CREATED', userData.uid, userData.fullName || 'User', ref.id, 'contract_swos', `SWO ${swoNumber} created (₹${value.totalValue})`);
    return { message: 'SWO created', uid: ref.id, swo: data };
  }

  async deleteSWO(uid, userData) {
    const ref = db.collection('contract_swos').doc(uid);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('SWO not found');
    await ref.update({ status: 'deleted', deletedBy: userData.uid, updatedAt: new Date().toISOString() });
    await auditService.logAudit('CONTRACT_SWO_DELETED', userData.uid, userData.fullName || 'User', uid, 'contract_swos', `SWO ${doc.data().swoNumber} deleted`);
    return { message: 'SWO deleted', uid };
  }

  /* ---------- Amended / final contract value ---------- */

  async getAmendedContractValue({ contractId }) {
    const contractDoc = await db.collection('contracts').doc(contractId).get();
    if (!contractDoc.exists) throw new NotFoundError('Contract not found');
    const contract = contractDoc.data();
    const originalValue = contract.contractValue || 0;
    const { totalSwoValue } = await this.getSWOs({ contractId });
    const maxRevision = await this.getVariations({ contractId });
    const latest = maxRevision.latest;
    let amended = originalValue;
    if (latest) {
      amended = latest.amendedContractValue;
      if (latest.originalContractValue === 0 || latest.revisedScopeValue === 0) {
        amended = latest.amendedContractValue;
      }
    }
    const amendedWithSwo = roundMoney(amended + totalSwoValue);
    const estimate = await this.getEstimateItems({ contractId });
    return {
      contractId,
      contractNumber: contract.contractNumber || '',
      contractValue: roundMoney(originalValue),
      latestRevision: latest ? { revisionNo: latest.revisionNo, effectiveDate: latest.effectiveDate, amendedContractValue: latest.amendedContractValue } : null,
      totalSwoValue,
      amendedContractValue: amendedWithSwo,
      estimateValue: estimate.totalEstimatedCost,
      trace: {
        original: roundMoney(originalValue),
        variations: latest ? latest.amendedContractValue : roundMoney(originalValue),
        swos: totalSwoValue,
        amended: amendedWithSwo,
      },
    };
  }

  /* ---------- Billing-period contribution (mid-period proration) ---------- */

  async getPeriodContribution({ contractId, stationId, month, year }) {
    const { start: periodStart, end: periodEnd } = monthRange(month, year);
    const items = await this.getEstimateItems({ contractId, stationId: stationId || undefined });
    const rows = [];
    let total = 0;
    for (const it of items.items) {
      const days = overlappingDays({ periodStart, periodEnd, itemStart: it.startDate, itemEnd: it.endDate });
      if (days <= 0) continue;
      const rate = parseFloat(it.rate) || 0;
      const qpd = parseFloat(it.quantityPerDay) || 0;
      const costPerDay = parseFloat(it.costPerDay) || 0;
      const amountPerDay = costPerDay > 0 ? costPerDay : roundMoney(qpd * rate);
      const isOnce = String(it.frequency?.type || '').toLowerCase() === 'once' || String(it.frequency?.type || '').toLowerCase() === 'as_required';
      const amount = isOnce ? (parseFloat(it.estimatedCost) || 0) : roundMoney(amountPerDay * days);
      total += amount;
      rows.push({
        uid: it.id || it.uid,
        itemNo: it.itemNo || 0,
        description: it.description,
        category: it.category,
        stationName: it.stationName,
        periodDays: days,
        costPerDay: roundMoney(amountPerDay),
        amount: roundMoney(amount),
        nsRef: it.nsRef || '',
        isAdditional: it.isAdditional === true,
      });
    }
    rows.sort((a, b) => (a.category || '').localeCompare(b.category || ''));
    return { contractId, stationId, month: parseInt(month), year: parseInt(year), periodStart, periodEnd, total: roundMoney(total), rows };
  }
}

function updatedEstimateLabel(current, updates) {
  return updates.description || current.description || '';
}

export const contractEstimationService = new ContractEstimationService();