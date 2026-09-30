import express from 'express';
import { verifyToken } from '../middleware/auth.js';
import { forbidContractType } from '../middleware/authorization.js';
import * as obhsController from '../controllers/obhsController.js';
import { compareFaces } from '../services/rekognitionService.js';

const router = express.Router();

router.all('/api/obhs*', verifyToken, forbidContractType('station_cleaning'));

// POST/GET at collection root (no param collision)
router.post('/api/obhs', verifyToken, obhsController.submit);
router.get('/api/obhs', verifyToken, obhsController.list);
router.get('/api/obhs/counts', verifyToken, obhsController.getStatusCounts);

// ─── SPECIFIC ROUTES (MUST come before :obhsId param) ──────────────────────

router.post('/api/obhs/attendance', verifyToken, obhsController.markAttendance);
router.get('/api/obhs/attendance/status', verifyToken, obhsController.getAttendanceStatus);
router.get('/api/obhs/attendance/list', verifyToken, obhsController.listAttendance);
router.post('/api/obhs/attendance/report-issue', verifyToken, obhsController.reportAttendanceIssue);
router.get('/api/obhs/attendance/exceptions', verifyToken, obhsController.getAttendanceExceptions);
router.post('/api/obhs/attendance/exceptions/action', verifyToken, obhsController.takeAttendanceExceptionAction);
router.post('/api/obhs/attendance/verify-face', verifyToken, async (req, res) => {
  const { image1Url, image2Url } = req.body;
  if (!image1Url || !image2Url) return res.status(400).json({ error: 'Both image1Url and image2Url are required.' });
  const result = await compareFaces(image1Url, image2Url);
  if (!result.matched) return res.status(400).json({ success: false, error: 'Identity Verification Failed', details: result.reason });
  res.json({ success: true, message: 'Face verified successfully', similarity: result.similarity });
});

router.get('/api/obhs/garbage-tasks', verifyToken, obhsController.listGarbageTasks);
router.post('/api/obhs/garbage-tasks/complete', verifyToken, obhsController.completeGarbageTask);
router.get('/api/obhs/garbage-tasks/pre-terminal', verifyToken, obhsController.getPreTerminalGarbageTasks);

router.get('/api/obhs/water-checks', verifyToken, obhsController.listWaterChecks);
router.post('/api/obhs/water-checks/submit', verifyToken, obhsController.submitWaterCheck);
router.get('/api/obhs/water-checks/alerts', verifyToken, obhsController.getWaterAlerts);

router.get('/api/obhs/safety-checks', verifyToken, obhsController.listSafetyChecks);
router.post('/api/obhs/safety-checks/submit', verifyToken, obhsController.submitSafetyCheck);
router.post('/api/obhs/safety-checks/report-deficiency', verifyToken, obhsController.reportSafetyDeficiency);

router.get('/api/obhs/petty-repairs', verifyToken, obhsController.listPettyRepairs);
router.post('/api/obhs/petty-repairs', verifyToken, obhsController.submitPettyRepair);
router.post('/api/obhs/petty-repairs/submit', verifyToken, obhsController.submitPettyRepair);
router.post('/api/obhs/petty-repairs/escalate', verifyToken, obhsController.escalatePettyRepair);

router.post('/api/obhs/ratings/submit', verifyToken, obhsController.submitRating);
router.get('/api/obhs/ratings', verifyToken, obhsController.listRatings);
router.get('/api/obhs/ratings/employee/:employeeId', verifyToken, obhsController.getRatingsForEmployee);
router.get('/api/obhs/ratings/performance/:employeeId', verifyToken, obhsController.getEmployeePerformance);

router.post('/api/obhs/complaints/raise', verifyToken, obhsController.raiseComplaint);
router.get('/api/obhs/complaints', verifyToken, obhsController.listComplaints);
router.patch('/api/obhs/complaints/resolve/:complaintId', verifyToken, obhsController.resolveComplaint);
router.patch('/api/obhs/complaints/assign/:complaintId', verifyToken, obhsController.assignComplaint);
router.patch('/api/obhs/complaints/escalate/:complaintId', verifyToken, obhsController.escalateComplaint);
router.patch('/api/obhs/complaints/sla-update/:complaintId', verifyToken, obhsController.updateComplaintSLA);
router.get('/api/obhs/complaints/sla-report', verifyToken, obhsController.getSLAReport);
router.post('/api/obhs/complaints/auto-route', verifyToken, obhsController.autoRouteComplaint);

router.post('/api/obhs/feedback/passenger', verifyToken, obhsController.submitPassengerFeedback);
router.post('/api/obhs/feedback/official', verifyToken, obhsController.submitOfficialFeedback);
router.get('/api/obhs/feedback/worker-summary', verifyToken, obhsController.getFeedbackWorkerSummary);

router.get('/api/obhs/tasks/board', verifyToken, obhsController.getTaskBoard);
router.get('/api/obhs/tasks/headers', verifyToken, obhsController.getTaskHeaders);
router.get('/api/obhs/tasks/details/:headerId', verifyToken, obhsController.getTaskDetails);
router.get('/api/obhs/tasks/coach', verifyToken, obhsController.getCoachTasks);
router.post('/api/obhs/tasks/submit', verifyToken, obhsController.submitTask);
router.patch('/api/obhs/tasks/detail/:detailId/status', verifyToken, obhsController.updateTaskDetailStatus);
router.get('/api/obhs/tasks/run/:runInstanceId', verifyToken, obhsController.getRunTasks);
router.get('/api/obhs/complaints/run/:runInstanceId', verifyToken, obhsController.getRunComplaints);

router.get('/api/obhs/supervisor/dashboard', verifyToken, obhsController.getSupervisorDashboard);
router.get('/api/obhs/worker/active-run', verifyToken, obhsController.getWorkerActiveRun);

// ─── PARAM ROUTES (after specific routes) ──────────────────────────────────

router.get('/api/obhs/:obhsId', verifyToken, obhsController.getById);
router.put('/api/obhs/:obhsId', verifyToken, obhsController.update);
router.put('/api/obhs/:obhsId/approve', verifyToken, obhsController.approve);

// ─── STANDALONE FACE VERIFICATION ──────────────────────────────────────────

router.post('/api/verifyFace', verifyToken, async (req, res) => {
  const { image1Url, image2Url } = req.body;
  if (!image1Url || !image2Url) return res.status(400).json({ success: false, error: 'Both image1Url and image2Url are required.' });
  const result = await compareFaces(image1Url, image2Url);
  if (!result.matched) return res.status(400).json({ success: false, error: 'Identity Verification Failed', details: result.reason });
  res.json({ success: true, message: 'Face verified successfully', similarity: result.similarity });
});

router.post('/api/compareFace', verifyToken, async (req, res) => {
  const { image1Url, image2Url } = req.body;
  if (!image1Url || !image2Url) return res.status(400).json({ success: false, error: 'Both image1Url and image2Url are required.' });
  const result = await compareFaces(image1Url, image2Url);
  res.json({ success: result.matched, matched: result.matched, similarity: result.similarity, reason: result.reason });
});

export default router;
