import { Router } from 'express';
import { verifyToken } from '../middleware/auth.js';
import auditController from '../controllers/auditController.js';
import { auditService } from '../services/auditService.js';
import { asyncHandler } from '../middleware/errorHandler.js';

const router = Router();

router.get('/api/audit/logs', verifyToken, auditController.getAuditLogs);
router.get('/api/audit/logs/station/:stationId', verifyToken, auditController.getStationAuditLogs);
router.get('/api/audit-logs', verifyToken, asyncHandler(async (req, res) => {
  const isWorker = ['WORKER', 'RAILWAY_WORKER', 'JANITOR', 'ATTENDANT'].includes(req.user.role);
  if (isWorker) {
    req.query.userId = req.user.uid; // Wait, some services log userId instead of actorId
    req.query.actorId = req.user.uid;
  }
  const result = await auditService.getAuditLogs(req.query);
  
  // App expects type, so let's try to map it heuristically
  let logs = result.logs || [];
  logs = logs.map(log => {
    let type = log.type || 'Activity';
    if (!log.type) {
      if (log.action?.includes('ATTENDANCE')) type = 'Attendance';
      else if (log.action?.includes('TASK')) type = 'Task';
      else if (log.action?.includes('GARBAGE')) type = 'Garbage';
      else if (log.action?.includes('PEST')) type = 'Pest Control';
      else if (log.action?.includes('MACHINE')) type = 'Machine';
      else if (log.action?.includes('COMPLAINT')) type = 'Complaint';
      else if (log.action?.includes('EVIDENCE')) type = 'Task';
      else if (log.action?.includes('ESCALATION')) type = 'Escalation';
    }
    return { ...log, type };
  });

  if (req.query.type) {
    logs = logs.filter(l => l.type === req.query.type);
  }

  res.json({ data: logs });
}));
router.get('/api/audit/logs/stats', verifyToken, auditController.getAuditStats);
router.get('/api/audit/evidence', verifyToken, auditController.getEvidenceAudit);

export default router;
