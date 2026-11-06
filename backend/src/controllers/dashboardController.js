import { dashboardService } from '../services/dashboardService.js';
import { asyncHandler } from '../middleware/errorHandler.js';

export const userCounts = asyncHandler(async (req, res) => res.json(await dashboardService.getUserCounts(req.query, req.user)));
export const stats =asyncHandler(async (req, res) => res.json(await dashboardService.getDashboardStats(req.user, req.query)));
export const railwayDashboardStats = asyncHandler(async (req, res) => res.json(await dashboardService.getRailwayDashboardStats(req.user)));
export const stationDashboard = asyncHandler(async (req, res) => res.json(await dashboardService.getStationDashboard(req.params.stationId, req.query)));
export const userStats = asyncHandler(async (req, res) => res.json(await dashboardService.getUserStats(req.user, req.query)));
export const trainStats = asyncHandler(async (req, res) => res.json(await dashboardService.getTrainStats(req.user, req.query)));
export const supervisorStats = asyncHandler(async (req, res) => res.json(await dashboardService.getSupervisorStats(req.user)));
export const activeTrains = asyncHandler(async (req, res) => res.json(await dashboardService.getActiveTrains()));
export const activeWorkers = asyncHandler(async (req, res) => res.json(await dashboardService.getActiveWorkers(req.user)));
export const allFormsStats = asyncHandler(async (req, res) => res.json(await dashboardService.getAllFormsStats(req.query, req.user)));

export const adminDashboard = asyncHandler(async (req, res) => res.json(await dashboardService.getAdminDashboard()));
export const zoneDashboard = asyncHandler(async (req, res) => res.json(await dashboardService.getZoneDashboard(req.params.zoneId)));
export const platformDashboard = asyncHandler(async (req, res) => res.json(await dashboardService.getPlatformDashboard(req.params.platformId, req.query)));
export const areaDashboard = asyncHandler(async (req, res) => res.json(await dashboardService.getAreaDashboard(req.params.areaId, req.query)));
