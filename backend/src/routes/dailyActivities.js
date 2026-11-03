import { Router } from 'express';
import { verifyToken } from '../middleware/auth.js';
import { forbidFieldWorkers } from '../middleware/authorization.js';
import * as dailyActivityController from '../controllers/dailyActivityController.js';

const router = Router();

router.post('/api/station-activities', verifyToken, dailyActivityController.createRecord);
router.get('/api/station-activities', verifyToken, dailyActivityController.listActivities);
router.get('/api/station-activities/missed', verifyToken, dailyActivityController.getMissedActivities);
router.get('/api/station-activities/pending', verifyToken, dailyActivityController.getPendingActivities);
router.get('/api/station-activities/shift-summary', verifyToken, dailyActivityController.getShiftSummary);
router.post('/api/station-activities/bulk-verify', verifyToken, forbidFieldWorkers, dailyActivityController.bulkVerify);
router.post('/api/station-activities/auto-generate', verifyToken, forbidFieldWorkers, dailyActivityController.autoGenerate);
router.get('/api/station-activities/worker', verifyToken, dailyActivityController.getWorkerActivities);
router.get('/api/station-activities/:uid', verifyToken, dailyActivityController.getById);
router.patch('/api/station-activities/:uid/status', verifyToken, dailyActivityController.updateStatus);
router.post('/api/station-activities/:uid/start', verifyToken, dailyActivityController.startActivity);
router.post('/api/station-activities/:uid/complete', verifyToken, dailyActivityController.completeActivity);
router.delete('/api/station-activities/:uid', verifyToken, forbidFieldWorkers, dailyActivityController.deleteRecord);

export default router;
