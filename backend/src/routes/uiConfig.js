import { Router } from 'express';
import { verifyToken } from '../middleware/auth.js';
import uiConfigController from '../controllers/uiConfigController.js';

const router = Router();

// Optional auth: if a valid token is present, role-aware config is returned;
// otherwise defaults are returned so legacy/offline clients keep working.
router.get('/api/ui-config', (req, res, next) => {
  const authHeader = req.headers['authorization'];
  if (authHeader && authHeader.startsWith('Bearer ')) {
    return verifyToken(req, res, next);
  }
  next();
}, uiConfigController.getUiConfig);

export default router;
