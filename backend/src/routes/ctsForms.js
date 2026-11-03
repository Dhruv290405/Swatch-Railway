import express from 'express';
import { verifyToken } from '../middleware/auth.js';
import { forbidFieldWorkers } from '../middleware/authorization.js';
import * as ctsFormController from '../controllers/ctsFormController.js';

const router = express.Router();

router.post('/', verifyToken, ctsFormController.create);
router.get('/', verifyToken, ctsFormController.list);
router.get('/:formId', verifyToken, ctsFormController.getById);
router.post('/:formId/approve-manpower', verifyToken, ctsFormController.approveManpower);
router.put('/:formId/approve-manpower', verifyToken, ctsFormController.approveManpower);

router.post('/:formId/submit-scoring', verifyToken, forbidFieldWorkers, ctsFormController.submitScoring);
router.post('/:formId/scoring', verifyToken, forbidFieldWorkers, ctsFormController.submitScoring);
router.put('/:formId/scoring', verifyToken, forbidFieldWorkers, ctsFormController.submitScoring);

router.post('/:formId/accept-rating', verifyToken, ctsFormController.acceptRating);
router.put('/:formId/accept-rating', verifyToken, ctsFormController.acceptRating);

router.put('/:formId/resubmit', verifyToken, ctsFormController.resubmit);

router.post('/:formId/reject', verifyToken, forbidFieldWorkers, ctsFormController.reject);
router.put('/:formId/reject', verifyToken, forbidFieldWorkers, ctsFormController.reject);
router.post('/emergency-task', verifyToken, ctsFormController.createEmergencyTask);
router.post('/create-emergency-task', verifyToken, ctsFormController.createEmergencyTask);

export default router;
