import express from 'express';
import { verifyToken } from '../middleware/auth.js';
import { requireContractType } from '../middleware/authorization.js';
import * as mccController from '../controllers/mccController.js';

const router = express.Router();

router.all('/api/mcc*', verifyToken, requireContractType('mcc'));

// ─── SPECIFIC ROUTES (MUST come before :param routes) ──────────────────────

router.post('/api/mcc/depots', verifyToken, mccController.createDepot);
router.get('/api/mcc/depots', verifyToken, mccController.listDepots);
router.get('/api/mcc/depots/:depotId', verifyToken, mccController.getDepot);

router.post('/api/mcc/washing-runs', verifyToken, mccController.createWashingRun);
router.get('/api/mcc/washing-runs', verifyToken, mccController.listWashingRuns);
router.post('/api/mcc/washing-runs/:runId/start', verifyToken, mccController.startWashingRun);
router.post('/api/mcc/washing-runs/:runId/complete', verifyToken, mccController.completeWashingRun);
router.get('/api/mcc/washing-runs/:runId', verifyToken, mccController.getWashingRun);

router.get('/api/mcc/worker/tasks', verifyToken, mccController.getWorkerTasks);
router.post('/api/mcc/washing-tasks/submit', verifyToken, mccController.submitTask);
router.post('/api/mcc/washing-tasks/:taskId/approve', verifyToken, mccController.approveTask);
router.post('/api/mcc/washing-tasks/:taskId/reject', verifyToken, mccController.rejectTask);

router.post('/api/mcc/attendance', verifyToken, mccController.markAttendance);
router.get('/api/mcc/attendance/status', verifyToken, mccController.getAttendanceStatus);
router.get('/api/mcc/attendance/list', verifyToken, mccController.listAttendance);

router.get('/api/mcc/dashboard', verifyToken, mccController.getDashboard);

export default router;