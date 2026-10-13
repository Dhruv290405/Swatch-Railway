import { trainService } from '../services/trainService.js';
import { asyncHandler } from '../middleware/errorHandler.js';

export const createTrain = asyncHandler(async (req, res) => {
  const result = await trainService.createTrain(req.user, req.body);
  res.status(201).json(result);
});

export const updateTrain = asyncHandler(async (req, res) => {
  const result = await trainService.updateTrain(req.user, req.params.uid, req.body);
  res.status(200).json(result);
});

export const getTrains = asyncHandler(async (req, res) => {
  const result = await trainService.getTrains(req.user, req.query);
  res.status(200).json(result);
});

export const getTrainByUid = asyncHandler(async (req, res) => {
  const result = await trainService.getTrainByUid(req.params.uid);
  res.status(200).json(result);
});

export const getTrainByNumber = asyncHandler(async (req, res) => {
  const result = await trainService.getTrainByNumber(req.params.trainNo);
  res.status(200).json(result);
});

export const getTrainPairs = asyncHandler(async (req, res) => {
  const result = await trainService.getTrainPairs(req.params.trainId);
  res.status(200).json(result);
});

export const generateSchedule = asyncHandler(async (req, res) => {
  const result = await trainService.generateSchedule(req.user, req.params.trainId, req.body);
  res.status(200).json(result);
});

export const deleteTrain = asyncHandler(async (req, res) => {
  const result = await trainService.deleteTrain(req.params.uid);
  res.status(200).json(result);
});

export default { createTrain, updateTrain, getTrains, getTrainByUid, getTrainByNumber, getTrainPairs, generateSchedule, deleteTrain };
