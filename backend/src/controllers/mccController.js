import { mccService } from '../services/mccService.js';
import { asyncHandler } from '../middleware/errorHandler.js';

export const createDepot = asyncHandler(async (req, res) => {
  const result = await mccService.createDepot(req.user, req.body);
  res.status(201).json(result);
});

export const listDepots = asyncHandler(async (req, res) => {
  const result = await mccService.listDepots(req.query);
  res.status(200).json(result);
});

export const getDepot = asyncHandler(async (req, res) => {
  const result = await mccService.getDepot(req.params.depotId);
  res.status(200).json(result);
});

export const createWashingRun = asyncHandler(async (req, res) => {
  const result = await mccService.createWashingRun(req.user, req.body);
  res.status(201).json(result);
});

export const listWashingRuns = asyncHandler(async (req, res) => {
  const result = await mccService.listWashingRuns(req.query);
  res.status(200).json(result);
});

export const getWashingRun = asyncHandler(async (req, res) => {
  const result = await mccService.getWashingRun(req.params.runId);
  res.status(200).json(result);
});

export const startWashingRun = asyncHandler(async (req, res) => {
  const result = await mccService.startWashingRun(req.user, req.params.runId);
  res.status(200).json(result);
});

export const completeWashingRun = asyncHandler(async (req, res) => {
  const result = await mccService.completeWashingRun(req.params.runId);
  res.status(200).json(result);
});

export const getWorkerTasks = asyncHandler(async (req, res) => {
  const result = await mccService.getWorkerTasks(req.user, req.query);
  res.status(200).json(result);
});

export const submitTask = asyncHandler(async (req, res) => {
  const result = await mccService.submitTask(req.user, req.body);
  res.status(200).json(result);
});

export const approveTask = asyncHandler(async (req, res) => {
  const result = await mccService.approveTask(req.user, req.params.taskId, req.body || {});
  res.status(200).json(result);
});

export const rejectTask = asyncHandler(async (req, res) => {
  const result = await mccService.rejectTask(req.user, req.params.taskId, req.body || {});
  res.status(200).json(result);
});

export const markAttendance = asyncHandler(async (req, res) => {
  const result = await mccService.markAttendance(req.user, req.body);
  res.status(200).json(result);
});

export const getAttendanceStatus = asyncHandler(async (req, res) => {
  const result = await mccService.getAttendanceStatus(req.user, req.query);
  res.status(200).json(result);
});

export const listAttendance = asyncHandler(async (req, res) => {
  const result = await mccService.listAttendance(req.query);
  res.status(200).json(result);
});

export const getDashboard = asyncHandler(async (req, res) => {
  const result = await mccService.getDashboard(req.user);
  res.status(200).json(result);
});