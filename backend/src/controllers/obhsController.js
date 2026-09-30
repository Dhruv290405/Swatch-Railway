import { db } from '../database/index.js';
import { obhsService } from '../services/obhsService.js';
import { NotFoundError } from '../errors/index.js';
import { asyncHandler } from '../middleware/errorHandler.js';

export const submit = asyncHandler(async (req, res) => {
  const result = await obhsService.submitComplaint(req.user, req.body);
  res.status(201).json(result);
});

export const update = asyncHandler(async (req, res) => {
  const result = await obhsService.updateComplaintSLA(req.params.obhsId, req.body);
  res.status(200).json(result);
});

export const list = asyncHandler(async (req, res) => {
  const result = await obhsService.getComplaints(req.query);
  res.status(200).json(result);
});

export const getById = asyncHandler(async (req, res) => {
  const { obhsId } = req.params;
  const snapshot = await db.collection('obhs_complaints').doc(obhsId).get();
  if (!snapshot.exists) throw new NotFoundError('Complaint not found');
  res.status(200).json({ success: true, data: { id: snapshot.id, ...snapshot.data() } });
});

export const approve = asyncHandler(async (req, res) => {
  const { obhsId } = req.params;
  const snapshot = await db.collection('obhs_complaints').doc(obhsId).get();
  if (!snapshot.exists) throw new NotFoundError('Complaint not found');
  await db.collection('obhs_complaints').doc(obhsId).update({
    status: 'APPROVED', approvedBy: req.user.uid, approvedAt: new Date().toISOString()
  });
  res.status(200).json({ success: true, message: 'Complaint approved' });
});

export const getStatusCounts = asyncHandler(async (req, res) => {
  const result = await obhsService.getComplaints({ groupByStatus: true });
  res.status(200).json(result);
});

export const markAttendance = asyncHandler(async (req, res) => {
  const result = await obhsService.markAttendance(req.user, req.body);
  res.status(result.isLate ? 200 : 200).json(result);
});

export const getAttendanceStatus = asyncHandler(async (req, res) => {
  const { runInstanceId } = req.query;
  const result = await obhsService.getAttendanceStatus(runInstanceId, req.user.uid);
  res.status(200).json(result);
});

export const listAttendance = asyncHandler(async (req, res) => {
  const filters = { ...req.query, callerId: req.user.uid, role: req.user.role };
  const result = await obhsService.getAttendance(filters);
  res.status(200).json(result);
});

export const reportAttendanceIssue = asyncHandler(async (req, res) => {
  const result = await obhsService.reportAttendanceIssue(req.user, req.body);
  res.status(201).json(result);
});

export const getAttendanceExceptions = asyncHandler(async (req, res) => {
  const result = await obhsService.getAttendanceExceptions(req.query);
  res.status(200).json(result);
});

export const takeAttendanceExceptionAction = asyncHandler(async (req, res) => {
  const result = await obhsService.takeActionOnException(req.body);
  res.status(200).json(result);
});

// ─── GARBAGE TASKS ───────────────────────────────────────────────────────

export const listGarbageTasks = asyncHandler(async (req, res) => {
  const result = await obhsService.getGarbageTasks(req.query);
  res.status(200).json(result);
});

export const completeGarbageTask = asyncHandler(async (req, res) => {
  const result = await obhsService.completeGarbageTask(req.body);
  res.status(200).json(result);
});

export const getPreTerminalGarbageTasks = asyncHandler(async (req, res) => {
  const result = await obhsService.getPreTerminalGarbageTasks(req.query.runInstanceId);
  res.status(200).json(result);
});

// ─── WATER CHECKS ────────────────────────────────────────────────────────

export const listWaterChecks = asyncHandler(async (req, res) => {
  const result = await obhsService.getWaterChecks(req.query);
  res.status(200).json(result);
});

export const submitWaterCheck = asyncHandler(async (req, res) => {
  const result = await obhsService.submitWaterCheck(req.body);
  res.status(200).json(result);
});

export const getWaterAlerts = asyncHandler(async (req, res) => {
  const result = await obhsService.getWaterAlerts(req.query.runInstanceId);
  res.status(200).json(result);
});

// ─── SAFETY CHECKS ───────────────────────────────────────────────────────

export const listSafetyChecks = asyncHandler(async (req, res) => {
  const result = await obhsService.getSafetyChecks(req.query.runInstanceId);
  res.status(200).json(result);
});

export const submitSafetyCheck = asyncHandler(async (req, res) => {
  const result = await obhsService.submitSafetyCheck(req.body);
  res.status(200).json(result);
});

export const reportSafetyDeficiency = asyncHandler(async (req, res) => {
  const result = await obhsService.reportSafetyDeficiency(req.user, req.body);
  res.status(200).json(result);
});

// ─── PETTY REPAIRS ───────────────────────────────────────────────────────

export const listPettyRepairs = asyncHandler(async (req, res) => {
  const result = await obhsService.getPettyRepairs(req.query.runInstanceId);
  res.status(200).json(result);
});

export const submitPettyRepair = asyncHandler(async (req, res) => {
  const result = await obhsService.submitPettyRepair(req.body);
  res.status(200).json(result);
});

export const escalatePettyRepair = asyncHandler(async (req, res) => {
  const result = await obhsService.escalatePettyRepair(req.body);
  res.status(200).json(result);
});

// ─── RATINGS ─────────────────────────────────────────────────────────────

export const submitRating = asyncHandler(async (req, res) => {
  const result = await obhsService.submitRating(req.user, req.body);
  res.status(201).json(result);
});

export const listRatings = asyncHandler(async (req, res) => {
  const result = await obhsService.getRatings(req.query);
  res.status(200).json(result);
});

export const getEmployeePerformance = asyncHandler(async (req, res) => {
  const result = await obhsService.getEmployeePerformance(req.params.employeeId);
  res.status(200).json(result);
});

// ─── COMPLAINTS SLA ──────────────────────────────────────────────────────

export const updateComplaintSLA = asyncHandler(async (req, res) => {
  const result = await obhsService.updateComplaintSLA(req.params.complaintId, req.body);
  res.status(200).json(result);
});

export const getSLAReport = asyncHandler(async (req, res) => {
  const result = await obhsService.getSLAReport(req.query.runInstanceId);
  res.status(200).json(result);
});

export const autoRouteComplaint = asyncHandler(async (req, res) => {
  const result = await obhsService.autoRouteComplaint(req.body);
  res.status(200).json(result);
});

// ─── SUPERVISOR DASHBOARD ────────────────────────────────────────────────

export const getSupervisorDashboard = asyncHandler(async (req, res) => {
  const result = await obhsService.getSupervisorDashboard(req.user);
  res.status(200).json(result);
});

// ─── WORKER ACTIVE RUN ───────────────────────────────────────────────────

export const getWorkerActiveRun = asyncHandler(async (req, res) => {
  const result = await obhsService.getWorkerActiveRun(req.user.uid);
  res.status(200).json(result);
});

// ─── RATINGS: EMPLOYEE LOOKUP ────────────────────────────────────────────

export const getRatingsForEmployee = asyncHandler(async (req, res) => {
  const result = await obhsService.getRatings({ employeeId: req.params.employeeId });
  res.status(200).json(result);
});

// ─── COMPLAINTS ──────────────────────────────────────────────────────────

export const raiseComplaint = asyncHandler(async (req, res) => {
  const result = await obhsService.submitComplaint(req.user, req.body);
  res.status(201).json(result);
});

export const listComplaints = asyncHandler(async (req, res) => {
  const result = await obhsService.getComplaints(req.query);
  res.status(200).json(result);
});

export const resolveComplaint = asyncHandler(async (req, res) => {
  const result = await obhsService.updateComplaintSLA(req.params.complaintId, { ...req.body, status: 'RESOLVED', resolvedBy: req.user.uid, resolvedAt: new Date().toISOString() });
  res.status(200).json(result);
});

export const assignComplaint = asyncHandler(async (req, res) => {
  const result = await obhsService.updateComplaintSLA(req.params.complaintId, { ...req.body, status: 'ASSIGNED', assignedBy: req.user.uid, assignedAt: new Date().toISOString() });
  res.status(200).json(result);
});

export const escalateComplaint = asyncHandler(async (req, res) => {
  const result = await obhsService.updateComplaintSLA(req.params.complaintId, { ...req.body, status: 'ESCALATED', escalatedBy: req.user.uid, escalatedAt: new Date().toISOString() });
  res.status(200).json(result);
});

// ─── FEEDBACK ────────────────────────────────────────────────────────────

export const submitPassengerFeedback = asyncHandler(async (req, res) => {
  const result = await obhsService.submitFeedback(req.user, { ...req.body, feedbackType: 'passenger' });
  res.status(201).json(result);
});

export const submitOfficialFeedback = asyncHandler(async (req, res) => {
  const result = await obhsService.submitFeedback(req.user, { ...req.body, feedbackType: 'official' });
  res.status(201).json(result);
});

export const getFeedbackWorkerSummary = asyncHandler(async (req, res) => {
  const result = await obhsService.getWorkerStats(req.user.uid);
  res.status(200).json(result);
});

// ─── TASKS ───────────────────────────────────────────────────────────────

export const getTaskBoard = asyncHandler(async (req, res) => {
  const { v2Service } = await import('../services/v2Service.js');
  const result = await v2Service.getWorkerMyTasks(req.user.uid, req.query);
  res.status(200).json(result);
});

export const getTaskHeaders = asyncHandler(async (req, res) => {
  const { v2Service } = await import('../services/v2Service.js');
  const result = await v2Service.getTaskMasters();
  res.status(200).json(result);
});

export const getTaskDetails = asyncHandler(async (req, res) => {
  const { v2Service } = await import('../services/v2Service.js');
  const result = await v2Service.getTasks(req.params.headerId, req.query);
  res.status(200).json(result);
});

export const getCoachTasks = asyncHandler(async (req, res) => {
  const { v2Service } = await import('../services/v2Service.js');
  const result = await v2Service.getTasks(null, { ...req.query, coachNo: req.query.coachNo });
  res.status(200).json(result);
});

export const submitTask = asyncHandler(async (req, res) => {
  const { v2Service } = await import('../services/v2Service.js');
  const result = await v2Service.submitTask(req.body, req.user);
  res.status(201).json(result);
});

export const updateTaskDetailStatus = asyncHandler(async (req, res) => {
  const { v2Service } = await import('../services/v2Service.js');
  const result = await v2Service.updateTask(req.params.detailId, req.body, req.user);
  res.status(200).json(result);
});

export const getRunTasks = asyncHandler(async (req, res) => {
  const { v2Service } = await import('../services/v2Service.js');
  const result = await v2Service.getTasks(req.params.runInstanceId, req.query);
  res.status(200).json(result);
});

export const getRunComplaints = asyncHandler(async (req, res) => {
  const result = await obhsService.getComplaints({ runInstanceId: req.params.runInstanceId });
  res.status(200).json(result);
});
