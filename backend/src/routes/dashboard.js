import express from 'express';
import { verifyToken } from '../middleware/auth.js';
import * as dashboardController from '../controllers/dashboardController.js';
import { forbidFieldWorkers } from '../middleware/authorization.js';

const router = express.Router();

router.get('/api/dashboard/user-counts', verifyToken, forbidFieldWorkers, dashboardController.userCounts);
router.get('/api/dashboard/stats', verifyToken, dashboardController.stats);
router.get('/api/dashboard/admin', verifyToken, dashboardController.adminDashboard);
router.get('/api/dashboard/zone/:zoneId', verifyToken, dashboardController.zoneDashboard);
router.get('/api/dashboard/station/:stationId', verifyToken, dashboardController.stationDashboard);
router.get('/api/dashboard/platform/:platformId', verifyToken, dashboardController.platformDashboard);
router.get('/api/dashboard/area/:areaId', verifyToken, dashboardController.areaDashboard);
router.get('/api/dashboard/user-stats', verifyToken, dashboardController.userStats);
router.get('/api/dashboard/train-stats', verifyToken, dashboardController.trainStats);
router.get('/api/dashboard/supervisor', verifyToken, dashboardController.supervisorStats);
router.get('/api/dashboard/active-trains', verifyToken, dashboardController.activeTrains);
router.get('/api/dashboard/active-workers', verifyToken, dashboardController.activeWorkers);
router.get('/api/all-forms/stats', verifyToken, dashboardController.allFormsStats);
router.get('/api/railway-dashboard-stats', verifyToken, dashboardController.railwayDashboardStats);

export default router;
