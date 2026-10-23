import { Router } from 'express';
import { verifyToken } from '../middleware/auth.js';
import { requirePermission } from '../middleware/authorization.js';
import { PERMISSIONS } from '../permissions/roles.js';
import userController from '../controllers/userController.js';

const router = Router();

router.post('/api/admin/createUser', verifyToken, requirePermission(PERMISSIONS.CREATE_USER), userController.createUser);
router.put('/api/admin/updateUser/:uid', verifyToken, requirePermission(PERMISSIONS.UPDATE_USER), userController.updateUser);
router.delete('/api/admin/deleteUser/:uid', verifyToken, requirePermission(PERMISSIONS.DELETE_USER), userController.deleteUser);
router.post('/api/master/approveUser/:uid', verifyToken, requirePermission(PERMISSIONS.APPROVE_USER), userController.approveUser);
router.get('/api/master/pending-users', verifyToken, requirePermission(PERMISSIONS.VIEW_USERS), userController.getPendingUsers);
router.post('/api/master/rejectUser/:uid', verifyToken, requirePermission(PERMISSIONS.REJECT_USER), userController.rejectUser);
router.post('/api/admin/suspendUser/:uid', verifyToken, requirePermission(PERMISSIONS.SUSPEND_USER), userController.suspendUser);
router.get('/api/admin/users', verifyToken, requirePermission(PERMISSIONS.VIEW_USERS), userController.getUsers);
router.get('/api/admin/railway-workers', verifyToken, requirePermission(PERMISSIONS.VIEW_USERS), userController.getRailwayWorkers);
router.get('/api/worker/profile', verifyToken, userController.getWorkerProfile);
router.get('/api/worker/statistics', verifyToken, userController.getWorkerStatistics);
router.get('/api/worker/tasks', verifyToken, userController.getWorkerTasks);
router.post('/api/worker/complaints', verifyToken, userController.submitWorkerComplaint);
router.get('/api/users/workers', verifyToken, requirePermission(PERMISSIONS.VIEW_USERS), userController.getWorkers);
router.get('/api/users/railway-supervisors', verifyToken, requirePermission(PERMISSIONS.VIEW_USERS), userController.getRailwaySupervisors);
router.get('/api/users/contractor-supervisors', verifyToken, requirePermission(PERMISSIONS.VIEW_USERS), userController.getContractorSupervisors);
router.get('/api/admin/analytics/workers-performance', verifyToken, requirePermission(PERMISSIONS.VIEW_ANALYTICS), userController.getWorkersPerformance);
router.get('/api/users/:uid', verifyToken, requirePermission(PERMISSIONS.VIEW_USER_DETAILS), userController.getUserById);

export default router;
