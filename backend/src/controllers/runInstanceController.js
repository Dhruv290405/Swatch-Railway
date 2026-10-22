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
  const userRole = (req.user?.role || '').toLowerCase();

  // Elevated roles that see all data (or can filter by division via query param)
  const isSuperAdmin =
    userRole.includes('super admin') ||
    userRole.includes('company master') ||
    userRole.includes('admin') ||
    userRole.includes('railway master') ||
    userRole.includes('railway_master') ||
    userRole.includes('railway supervisor') ||
    userRole.includes('railway_supervisor') ||
    userRole.includes('contractor master') ||
    userRole.includes('contractor_master');

  // Super admins see ALL instances; regular users are scoped to their division
  let division = isSuperAdmin ? (queryDivision || null) : (queryDivision || req.user?.division);

  // Derive division from assigned station if user has no direct division
  if (!division && !isSuperAdmin && req.user?.stationId) {
    const stationDoc = await db.collection('stations').doc(req.user.stationId).get();
    if (stationDoc.exists) {
      division = stationDoc.data().division || null;
    }
  }

  // If still no division, try to use zone as a fallback for zone-level scoped roles
  if (!division && !isSuperAdmin && req.user?.zone) {
    const result = await runInstanceService.getRunInstancesByZone(req.user.zone, status);
    return res.status(200).json(result);
  }

  if (!division && !isSuperAdmin) {
    return res.status(400).json({ error: 'Division is required' });
  }
  const result = await runInstanceService.getRunInstancesByDivision(division, status, isSuperAdmin);
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
