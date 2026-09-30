import { obhsAnalyticsService } from '../services/obhsAnalyticsService.js';
import { asyncHandler } from '../middleware/errorHandler.js';

const readFilters = (req) => {
  const { runInstanceId, division, zone, startDate, endDate } = req.query;
  return { runInstanceId: runInstanceId || null, division, zone, startDate, endDate };
};

export const getJanitorPerformance = asyncHandler(async (req, res) => {
  const result = await obhsAnalyticsService.getJanitorPerformance(readFilters(req));
  res.status(200).json(result);
});

export const getCoachCleanliness = asyncHandler(async (req, res) => {
  const result = await obhsAnalyticsService.getCoachCleanliness(readFilters(req));
  res.status(200).json(result);
});

export const getAttendanceCompliance = asyncHandler(async (req, res) => {
  const result = await obhsAnalyticsService.getAttendanceCompliance(readFilters(req));
  res.status(200).json(result);
});

export const getTaskCompletion = asyncHandler(async (req, res) => {
  const result = await obhsAnalyticsService.getTaskCompletion(readFilters(req));
  res.status(200).json(result);
});

export const getPassengerRatingTrend = asyncHandler(async (req, res) => {
  const result = await obhsAnalyticsService.getPassengerRatingTrend(readFilters(req));
  res.status(200).json(result);
});

export const getPenaltyRisk = asyncHandler(async (req, res) => {
  const result = await obhsAnalyticsService.getPenaltyRisk(readFilters(req));
  res.status(200).json(result);
});

export const getComprehensiveReport = asyncHandler(async (req, res) => {
  const runInstanceId = req.params.runInstanceId || req.query.runInstanceId || '';
  const result = await obhsAnalyticsService.getComprehensiveReport(runInstanceId);
  res.status(200).json(result);
});
