import { Router } from 'express';
import { verifyToken } from '../middleware/auth.js';
import { forbidFieldWorkers } from '../middleware/authorization.js';
import * as stationAttendanceController from '../controllers/stationAttendanceController.js';

const router = Router();

router.post('/api/station-attendance/mark', verifyToken, stationAttendanceController.markAttendance);
router.post('/api/station-attendance/bulk', verifyToken, forbidFieldWorkers, stationAttendanceController.markBulkAttendance);
router.get('/api/station-attendance/shift', verifyToken, stationAttendanceController.getShiftAttendance);
router.get('/api/station-attendance/planned-vs-actual', verifyToken, stationAttendanceController.getPlannedVsActual);
router.get('/api/station-attendance/monthly-summary', verifyToken, stationAttendanceController.getMonthlySummary);
router.post('/api/station-attendance/flag-absences', verifyToken, forbidFieldWorkers, stationAttendanceController.flagAbsences);
router.patch('/api/station-attendance/:attendanceId', verifyToken, stationAttendanceController.updateAttendance);
router.get('/api/station-attendance/worker/:workerId', verifyToken, stationAttendanceController.getWorkerHistory);
router.post('/api/station-attendance/leave', verifyToken, stationAttendanceController.applyLeave);
router.post('/api/station-attendance/leave/:uid/review', verifyToken, stationAttendanceController.approveLeave);
router.get('/api/station-attendance/leaves', verifyToken, stationAttendanceController.listLeaves);
router.get('/api/station-attendance/overtime', verifyToken, stationAttendanceController.calculateOvertime);
router.get('/api/station-attendance/export', verifyToken, stationAttendanceController.exportAttendance);

export default router;
