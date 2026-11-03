import express from 'express';
import { verifyToken } from '../middleware/auth.js';
import * as runInstanceController from '../controllers/runInstanceController.js';
import { forbidFieldWorkers } from '../middleware/authorization.js';

const router = express.Router();

router.post('/', verifyToken, forbidFieldWorkers, runInstanceController.create);
router.put('/:runInstanceId', verifyToken, forbidFieldWorkers, runInstanceController.update);
router.get('/', verifyToken, runInstanceController.list);
router.get('/train/:parentTrainId', verifyToken, runInstanceController.getByParentTrain);
router.delete('/:runInstanceId', verifyToken, forbidFieldWorkers, runInstanceController.remove);
router.get('/obhs/:runId', verifyToken, runInstanceController.getObhsRun);
router.post('/:runInstanceId/activate', verifyToken, runInstanceController.activateJourney);
router.post('/:runInstanceId/complete', verifyToken, runInstanceController.completeJourney);
router.get('/active-run', verifyToken, runInstanceController.getActiveRunForWorker);

export default router;
