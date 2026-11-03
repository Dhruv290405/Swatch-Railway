import { taskService } from '../services/taskService.js';
import { asyncHandler } from '../middleware/errorHandler.js';
import { db } from '../database/index.js';
import { ForbiddenError, ValidationError } from '../errors/index.js';
import { runAccessError, isFieldWorker } from '../utils/runAccess.js';

export const list = asyncHandler(async (req, res) => {
  const result = await taskService.getTasksForRun(req.user, req.query.runInstanceId, req.query);
  res.status(200).json(result);
});

export const getById = asyncHandler(async (req, res) => {
  const result = await taskService.getTaskById(req.params.taskId);
  res.status(200).json(result);
});

export const create = asyncHandler(async (req, res) => {
  const result = await taskService.createEmergencyTask(req.user, req.body);
  res.status(201).json(result);
});

export const update = asyncHandler(async (req, res) => {
  const result = await taskService.updateTaskStatus(req.params.taskId, req.body);
  res.status(200).json(result);
});

export const remove = asyncHandler(async (req, res) => {
  await taskService.deleteTask(req.params.taskId);
  res.status(200).json({ message: 'Task deleted successfully' });
});

export const myTasks = asyncHandler(async (req, res) => {
  const result = await taskService.getMyTasks(req.user.uid, req.query);
  res.status(200).json(result);
});

export const history = asyncHandler(async (req, res) => {
  const result = await taskService.getTaskHistory({ user: req.user, query: req.query });
  res.status(200).json(result);
});

export const pendingReview = asyncHandler(async (req, res) => {
  const runInstanceId = req.query.runInstanceId;
  if (!runInstanceId) throw new ValidationError('runInstanceId is required');

  // Only callers who may access this run can read its submitted tasks (photos, GPS, remarks).
  // Unknown runs keep the old behaviour (empty result) because there is nothing to protect.
  const runDoc = await db.collection('RunInstance').doc(String(runInstanceId)).get();
  if (runDoc.exists) {
    const denied = runAccessError(req.user, runDoc.data());
    if (denied) throw new ForbiddenError(denied);
  }

  const { v2Service } = await import('../services/v2Service.js');
  const result = await v2Service.getTasks(runInstanceId, { status: 'COMPLETED' });
  let tasks = result.tasks;
  // Field workers only ever see tasks assigned to them.
  if (isFieldWorker(req.user)) {
    tasks = tasks.filter((t) => (t.workerId || t.assignedTo) === req.user.uid);
  }
  // Map result.tasks to result.data for backward compatibility for Flutter app
  res.status(200).json({ success: true, count: tasks.length, data: tasks });
});

export const approveTask = asyncHandler(async (req, res) => {
  const result = await taskService.updateTaskStatus(req.user.uid, { ...req.body, action: 'APPROVE' });
  res.status(200).json(result);
});

export const rejectTask = asyncHandler(async (req, res) => {
  const result = await taskService.updateTaskStatus(req.user.uid, { ...req.body, action: 'REJECT' });
  res.status(200).json(result);
});

import { passengerService } from '../services/passengerService.js';
export const submitPassengerFeedback = asyncHandler(async (req, res) => {
  const result = await passengerService.submitTaskFeedback(req.user, { ...req.body, taskId: req.params.taskId });
  res.status(201).json(result);
});
