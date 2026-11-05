import express from 'express';
import { verifyToken } from '../middleware/auth.js';
import { requirePermission, requireAnyPermission } from '../middleware/authorization.js';
import { PERMISSIONS } from '../permissions/roles.js';
import { validate } from '../middleware/validate.js';
import { createStationSchema } from '../validations/schemas.js';
import * as stationController from '../controllers/stationController.js';

const router = express.Router();

router.get('/', verifyToken, requirePermission(PERMISSIONS.VIEW_STATIONS), stationController.list);
router.get('/search', verifyToken, requirePermission(PERMISSIONS.VIEW_STATIONS), stationController.search);
router.post('/', verifyToken, requireAnyPermission(PERMISSIONS.MANAGE_STATIONS, PERMISSIONS.CREATE_STATION), validate(createStationSchema), stationController.create);
router.get('/division/:division', verifyToken, requirePermission(PERMISSIONS.VIEW_STATIONS), stationController.getByDivision);
router.get('/:stationId', verifyToken, requirePermission(PERMISSIONS.VIEW_STATIONS), stationController.getById);
router.put('/:stationId', verifyToken, requireAnyPermission(PERMISSIONS.MANAGE_STATIONS, PERMISSIONS.CREATE_STATION), stationController.update);
router.delete('/:stationId', verifyToken, requirePermission(PERMISSIONS.MANAGE_STATIONS), stationController.remove);

export default router;
