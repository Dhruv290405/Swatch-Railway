import express from 'express';
import { verifyToken } from '../middleware/auth.js';
import { forbidFieldWorkers } from '../middleware/authorization.js';
import * as coachFormController from '../controllers/coachFormController.js';

const router = express.Router();

router.post('/', verifyToken, coachFormController.create);
router.get('/', verifyToken, coachFormController.list);
router.get('/submitted', verifyToken, coachFormController.getSubmitted);
router.get('/pending/scoring', verifyToken, coachFormController.getPendingScoring);
router.get('/:formId', verifyToken, coachFormController.getById);
router.post('/:formId/approve-manpower', verifyToken, coachFormController.approveManpower);
router.put('/:formId/approve-manpower', verifyToken, coachFormController.approveManpower);

router.put('/:formId/save-scoring-draft', verifyToken, forbidFieldWorkers, coachFormController.saveScoringDraft);
router.put('/:formId/scoring/draft', verifyToken, forbidFieldWorkers, coachFormController.saveScoringDraft);

router.post('/:formId/submit-scoring', verifyToken, forbidFieldWorkers, coachFormController.submitScoring);
router.post('/:formId/scoring', verifyToken, forbidFieldWorkers, coachFormController.submitScoring);
router.put('/:formId/scoring', verifyToken, forbidFieldWorkers, coachFormController.submitScoring);

router.post('/:formId/accept-rating', verifyToken, coachFormController.acceptRating);
router.put('/:formId/accept-rating', verifyToken, coachFormController.acceptRating);

router.put('/:formId/resubmit', verifyToken, coachFormController.resubmit);

router.post('/:formId/reject', verifyToken, forbidFieldWorkers, coachFormController.reject);
router.put('/:formId/reject', verifyToken, forbidFieldWorkers, coachFormController.reject);

export default router;
