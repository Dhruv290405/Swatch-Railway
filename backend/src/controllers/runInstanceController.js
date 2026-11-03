import { db } from '../database/index.js';
import { runInstanceService } from '../services/runInstanceService.js';
import { asyncHandler } from '../middleware/errorHandler.js';
import { ForbiddenError } from '../errors/index.js';

export const create = asyncHandler(async (req, res) => {
  const result = await runInstanceService.createRunInstance(req.user, req.body);
  res.status(201).json(result);
});

export const update = asyncHandler(async (req, res) => {
  const result = await runInstanceService.updateRunInstance(req.user, req.params.runInstanceId, req.body);
  res.status(200).json(result);
});

export const list = asyncHandler(async (req, res) => {
  const { division: queryDivision, status } = req.query;
  const roleKey = (req.user?.role || '').toUpperCase().replace(/\s+/g, '_');

  // Field workers only ever see the runs they are assigned to (filtered server-side).
  if (['JANITOR', 'ATTENDANT', 'WORKER', 'RAILWAY_WORKER'].includes(roleKey)) {
    const uid = req.user?.uid;
    const all = await runInstanceService.getRunInstancesByDivision(null, status, true);
    const mine = (all.data || []).filter((r) => (r.coaches || []).some(
      (c) => c.workerId === uid || c.janitorId === uid || c.attendantId === uid,
    ));
    return res.status(200).json({ success: true, count: mine.length, data: mine });
  }

  // Platform-wide roles may see everything or filter by any division.
  const isSuperAdmin = ['SUPER_ADMIN', 'ADMIN', 'COMPANY_MASTER', 'RAILWAY_MASTER'].includes(roleKey);
  // Other management roles (railway/contractor admin, supervisor, master) were previously
  // treated as global; they are now limited to their own division when one is on record
  // (legacy users without a division keep the old behaviour).
  const legacyGlobal =
    !isSuperAdmin && !req.user?.division && !req.user?.zone && !req.user?.stationId &&
    ['RAILWAY_ADMIN', 'RAILWAY_SUPERVISOR', 'CONTRACTOR_MASTER', 'CONTRACTOR_ADMIN', 'RAILWAY_INSPECTOR'].includes(roleKey);
  const globalView = isSuperAdmin || legacyGlobal;

  let division = globalView ? (queryDivision || null) : (req.user?.division || queryDivision);

  // Derive division from assigned station if user has no direct division
  if (!division && !globalView && req.user?.stationId) {
    const stationDoc = await db.collection('stations').doc(req.user.stationId).get();
    if (stationDoc.exists) {
      division = stationDoc.data().division || null;
    }
  }

  // If still no division, try to use zone as a fallback for zone-level scoped roles
  if (!division && !globalView && req.user?.zone) {
    const result = await runInstanceService.getRunInstancesByZone(req.user.zone, status);
    return res.status(200).json(result);
  }

  if (!division && !globalView) {
    return res.status(400).json({ error: 'Division is required' });
  }
  const result = await runInstanceService.getRunInstancesByDivision(division, status, globalView);
  res.status(200).json(result);
});

export const getByParentTrain = asyncHandler(async (req, res) => {
  const { parentTrainId } = req.params;
  const { status } = req.query;
  const result = await runInstanceService.getRunInstanceByTrainNo(parentTrainId);
  if (!result) return res.status(200).json({ message: 'No Run Instances found matching the criteria.', count: 0, data: [] });
  res.status(200).send({ message: 'Run Instances fetched successfully', count: 1, data: [result] });
});

export const remove = asyncHandler(async (req, res) => {
  const result = await runInstanceService.deleteRunInstance(req.params.runInstanceId);
  res.status(200).json(result);
});

export const getObhsRun = asyncHandler(async (req, res) => {
  const result = await runInstanceService.getRunInstanceById(req.params.runId);
  const roleKey = String(req.user?.role || '').toUpperCase().replace(/\s+/g, '_');
  const uid = req.user?.uid;
  if (['JANITOR', 'ATTENDANT', 'WORKER', 'RAILWAY_WORKER'].includes(roleKey)) {
    const assigned = (result.coaches || []).some(
      (c) => c.workerId === uid || c.janitorId === uid || c.attendantId === uid,
    );
    if (!assigned) throw new ForbiddenError('You are not assigned to this run.');
  } else if (!['SUPER_ADMIN', 'ADMIN', 'COMPANY_MASTER', 'RAILWAY_MASTER'].includes(roleKey)
    && req.user?.division && result.division && req.user.division !== result.division) {
    throw new ForbiddenError('This run belongs to another division.');
  }
  res.status(200).json({ success: true, data: result });
});

export const activateJourney = asyncHandler(async (req, res) => {
  const result = await runInstanceService.activateJourney(req.params.runInstanceId, req.body);
  res.status(200).json(result);
});

export const completeJourney = asyncHandler(async (req, res) => {
  const result = await runInstanceService.completeJourney(req.params.runInstanceId, req.body);
  res.status(200).json(result);
});

export const getActiveRunForWorker = asyncHandler(async (req, res) => {
  const workerId = req.query.workerId || req.user.uid;
  const role = String(req.user.role || '').toUpperCase().replace(/\s+/g, '_');
  const canViewOtherWorkers = new Set([
    'SUPER_ADMIN', 'COMPANY_MASTER', 'RAILWAY_MASTER', 'ADMIN',
    'RAILWAY_ADMIN', 'RAILWAY_INSPECTOR', 'RAILWAY_SUPERVISOR',
    'CONTRACTOR_MASTER', 'CONTRACTOR_ADMIN', 'CONTRACTOR_SUPERVISOR', 'CTS',
  ]);
  if (workerId !== req.user.uid && !canViewOtherWorkers.has(role)) {
    throw new ForbiddenError('You can only view your own run assignments.');
  }
  const result = await runInstanceService.getActiveRunForWorker(workerId, req.query.trainNo);
  if (!result) return res.status(404).json({ error: 'No active run found' });
  res.status(200).json(result);
});
