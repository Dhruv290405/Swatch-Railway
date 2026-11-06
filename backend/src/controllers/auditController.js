import { auditService } from '../services/auditService.js';
import { asyncHandler } from '../middleware/errorHandler.js';

export const getAuditLogs = asyncHandler(async (req, res) => {
  const result = await auditService.getAuditLogsForUser(req.user, req.query);
  res.status(200).json(result);
});

export const getAuditStats = asyncHandler(async (req, res) => {
  const result = await auditService.getAuditStats(req.query);
  res.status(200).json(result);
});

export const getStationAuditLogs = asyncHandler(async (req, res) => {
  const result = await auditService.getStationAuditLogs(req.params.stationId, req.query, req.user);
  res.status(200).json(result);
});

export const getEvidenceAudit = asyncHandler(async (req, res) => {
  const result = await auditService.getEvidenceAudit(req.query);
  res.status(200).json(result);
});

export default { getAuditLogs, getAuditStats, getStationAuditLogs, getEvidenceAudit };
