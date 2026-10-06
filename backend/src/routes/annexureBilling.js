/**
 * Annexure-4B Billing Routes
 *
 * Prefix: /api/annexure-billing  (mounted in app.js)
 */
import { Router } from 'express';
import { verifyToken } from '../middleware/auth.js';
import { requirePermission } from '../middleware/authorization.js';
import { PERMISSIONS } from '../permissions/roles.js';
import * as ctrl from '../controllers/annexureBillingController.js';

const router = Router();

// ─── Master Reference ────────────────────────────────────────────────────────
router.get('/master-items', verifyToken, ctrl.getMasterItems);

// ─── Contract Items (Level 1) ────────────────────────────────────────────────
router.post('/contracts/:contractId/seed',     verifyToken, requirePermission(PERMISSIONS.CONFIGURE_BILLING), ctrl.seedContractItems);
router.get('/contracts/:contractId/items',     verifyToken, requirePermission(PERMISSIONS.VIEW_BILLING),   ctrl.getContractItems);
router.get('/contracts/:contractId/validate',  verifyToken, requirePermission(PERMISSIONS.VIEW_BILLING),   ctrl.validateContractWeightage);
router.get('/contracts/:contractId/transfers', verifyToken, requirePermission(PERMISSIONS.VIEW_BILLING),   ctrl.getWeightageTransfers);
router.post('/contracts/:contractId/items',    verifyToken, requirePermission(PERMISSIONS.CONFIGURE_BILLING), ctrl.addNewContractItem);

router.get('/items/:itemId',                   verifyToken, requirePermission(PERMISSIONS.VIEW_BILLING),   ctrl.getContractItemById);
router.put('/items/:itemId',                   verifyToken, requirePermission(PERMISSIONS.CONFIGURE_BILLING), ctrl.updateContractItem);
router.post('/items/:itemId/unavailable',      verifyToken, requirePermission(PERMISSIONS.CONFIGURE_BILLING), ctrl.markItemUnavailable);

// ─── Area Components (Level 2) ───────────────────────────────────────────────
router.get('/items/:itemId/areas',             verifyToken, requirePermission(PERMISSIONS.VIEW_BILLING),   ctrl.getAreasForItem);
router.post('/items/:itemId/areas',            verifyToken, requirePermission(PERMISSIONS.CONFIGURE_BILLING), ctrl.addAreaComponent);
router.put('/areas/:areaId',                   verifyToken, requirePermission(PERMISSIONS.CONFIGURE_BILLING), ctrl.updateAreaComponent);
router.delete('/areas/:areaId',                verifyToken, requirePermission(PERMISSIONS.CONFIGURE_BILLING), ctrl.deleteAreaComponent);

// ─── Execution Tracking ──────────────────────────────────────────────────────
router.post('/executions',                     verifyToken, requirePermission(PERMISSIONS.MANAGE_EXECUTION), ctrl.recordExecution);
router.put('/executions/:executionId',         verifyToken, requirePermission(PERMISSIONS.MANAGE_EXECUTION), ctrl.updateExecution);
router.get('/executions',                      verifyToken, requirePermission(PERMISSIONS.VIEW_EXECUTION),   ctrl.getExecutions);

// ─── Billing / Deductions ────────────────────────────────────────────────────
router.post('/deductions/calculate',           verifyToken, requirePermission(PERMISSIONS.GENERATE_BILLING), ctrl.calculateBillingDeductions);
router.post('/deductions/finalize',            verifyToken, requirePermission(PERMISSIONS.APPROVE_BILLING),  ctrl.finalizeBillingDeductions);
router.get('/deductions',                      verifyToken, requirePermission(PERMISSIONS.VIEW_BILLING),     ctrl.getBillingDeductions);
router.get('/contracts/:contractId/summary',   verifyToken, requirePermission(PERMISSIONS.VIEW_BILLING),     ctrl.getBillingSummary);

export default router;
