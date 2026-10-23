import { userService } from '../services/userService.js';
import { asyncHandler } from '../middleware/errorHandler.js';

export const createUser = asyncHandler(async (req, res) => {
  const result = await userService.createUser(req.user, req.body);
  res.status(201).json(result);
});

export const updateUser = asyncHandler(async (req, res) => {
  const result = await userService.updateUser(req.user, req.params.uid, req.body);
  res.status(200).json(result);
});

export const deleteUser = asyncHandler(async (req, res) => {
  const result = await userService.deleteUser(req.user, req.params.uid);
  res.status(200).json(result);
});

export const approveUser = asyncHandler(async (req, res) => {
  const result = await userService.approveUser(req.user, req.params.uid);
  res.status(200).json(result);
});

export const getPendingUsers = asyncHandler(async (req, res) => {
  const result = await userService.getPendingUsers(req.user);
  res.status(200).json(result);
});

export const rejectUser = asyncHandler(async (req, res) => {
  const result = await userService.rejectUser(req.user, req.params.uid);
  res.status(200).json(result);
});

export const suspendUser = asyncHandler(async (req, res) => {
  const result = await userService.suspendUser(req.user, req.params.uid, req.body.suspensionReason);
  res.status(200).json(result);
});

export const getUsers = asyncHandler(async (req, res) => {
  const result = await userService.getUsers(req.user, req.query);
  res.status(200).json(result);
});

export const getRailwayWorkers = asyncHandler(async (req, res) => {
  const result = await userService.getRailwayWorkers(req.user, req.query);
  res.status(200).json(result);
});

export const getWorkerProfile = asyncHandler(async (req, res) => {
  const result = await userService.getWorkerProfile(req.user.uid);
  res.status(200).json(result);
});

export const getWorkerStatistics = asyncHandler(async (req, res) => {
  const result = await userService.getWorkerStatistics(req.user.uid);
  res.status(200).json(result);
});

export const getWorkers = asyncHandler(async (req, res) => {
  const result = await userService.getWorkers(req.user, req.query);
  res.status(200).json(result);
});

export const getContractorSupervisors = asyncHandler(async (req, res) => {
  const result = await userService.getContractorSupervisors(req.user, req.query);
  res.status(200).json(result);
});

export const getRailwaySupervisors = asyncHandler(async (req, res) => {
  let { zone, division, role } = req.user;
  
  if (role === 'SUPER_ADMIN') {
    zone = req.query.zone || zone;
    division = req.query.division || division;
  }
  
  const module = req.query.module || null;
  const result = await userService.getRailwaySupervisors(zone, division, role, module, req.user);
  res.status(200).json(result);
});

export const getWorkersPerformance = asyncHandler(async (req, res) => {
  const result = await userService.getWorkersPerformance(req.user);
  res.status(200).json(result);
});

export const getUserById = asyncHandler(async (req, res) => {
  const result = await userService.getUserById(req.user, req.params.uid);
  res.status(200).json(result);
});

export const getWorkerTasks = asyncHandler(async (req, res) => {
  const result = await userService.getWorkerTasks(req.user.uid, req.query);
  res.status(200).json(result);
});

export const submitWorkerComplaint = asyncHandler(async (req, res) => {
  const result = await userService.submitWorkerComplaint(req.user, req.body);
  res.status(201).json(result);
});

export default { createUser, updateUser, deleteUser, approveUser, getPendingUsers, rejectUser, suspendUser, getUsers, getRailwayWorkers, getWorkerProfile, getWorkerStatistics, getWorkers, getRailwaySupervisors, getContractorSupervisors, getWorkersPerformance, getUserById, getWorkerTasks, submitWorkerComplaint };
