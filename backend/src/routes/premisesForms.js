import express from 'express';
import { verifyToken } from '../middleware/auth.js';
import { forbidFieldWorkers } from '../middleware/authorization.js';
import * as premisesFormController from '../controllers/premisesFormController.js';

const router = express.Router();

router.post('/', verifyToken, premisesFormController.create);
router.get('/', verifyToken, premisesFormController.list);
router.get('/submitted', verifyToken, premisesFormController.submitted);
router.get('/:formId', verifyToken, premisesFormController.getById);
router.post('/:formId/approve-manpower', verifyToken, premisesFormController.approveManpower);
router.put('/:formId/approve-manpower', verifyToken, premisesFormController.approveManpower);

router.put('/:formId/save-scoring-draft', verifyToken, forbidFieldWorkers, premisesFormController.saveScoringDraft);
router.put('/:formId/scoring/draft', verifyToken, forbidFieldWorkers, premisesFormController.saveScoringDraft);

router.post('/:formId/submit-scoring', verifyToken, forbidFieldWorkers, premisesFormController.submitScoring);
router.post('/:formId/scoring', verifyToken, forbidFieldWorkers, premisesFormController.submitScoring);
router.put('/:formId/scoring', verifyToken, forbidFieldWorkers, premisesFormController.submitScoring);

router.post('/:formId/accept-rating', verifyToken, premisesFormController.acceptRating);
router.put('/:formId/accept-rating', verifyToken, premisesFormController.acceptRating);

router.put('/:formId/resubmit', verifyToken, premisesFormController.resubmit);

router.post('/:formId/reject', verifyToken, forbidFieldWorkers, premisesFormController.reject);
router.put('/:formId/reject', verifyToken, forbidFieldWorkers, premisesFormController.reject);
router.get('/pending/scoring', verifyToken, premisesFormController.pendingScoring);

export default router;
