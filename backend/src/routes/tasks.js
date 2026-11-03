import express from 'express';
import { verifyToken } from '../middleware/auth.js';
import { forbidFieldWorkers } from '../middleware/authorization.js';
import * as taskController from '../controllers/taskController.js';

const router = express.Router();

router.get('/', verifyToken, taskController.list);
router.get('/my', verifyToken, taskController.myTasks);
router.get('/history', verifyToken, taskController.history);
router.get('/pending-review', verifyToken, taskController.pendingReview);
router.post('/', verifyToken, taskController.create);
router.get('/:taskId', verifyToken, taskController.getById);
router.put('/:taskId', verifyToken, forbidFieldWorkers, taskController.update);
router.put('/:taskId/approve', verifyToken, forbidFieldWorkers, taskController.approveTask);
router.put('/:taskId/reject', verifyToken, forbidFieldWorkers, taskController.rejectTask);
router.delete('/:taskId', verifyToken, forbidFieldWorkers, taskController.remove);
router.post('/:taskId/passenger-feedback', taskController.submitPassengerFeedback);

export default router;
