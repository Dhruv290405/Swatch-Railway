import { Router } from 'express';
import { verifyToken } from '../middleware/auth.js';
import { requirePermission, requireStationAccess } from '../middleware/authorization.js';
import { PERMISSIONS } from '../permissions/roles.js';
import * as performanceBilling from '../controllers/performanceBillingController.js';

const router = Router();

// ─── Configuration ────────────────────────────────────────────────────────────
router.get('/api/performance-billing/config/:contractId', verifyToken, requirePermission(PERMISSIONS.VIEW_BILLING), performanceBilling.getConfig);
router.put('/api/performance-billing/config/:contractId', verifyToken, requirePermission(PERMISSIONS.CONFIGURE_BILLING), performanceBilling.saveConfig);

// ─── Scorecard (live computation, read-only) ─────────────────────────────────
router.get('/api/performance-billing/scorecard', verifyToken, requirePermission(PERMISSIONS.VIEW_BILLING), requireStationAccess, performanceBilling.scorecard);

// ─── Bills ────────────────────────────────────────────────────────────────────
router.get('/api/performance-billing/bills', verifyToken, requirePermission(PERMISSIONS.VIEW_BILLING), performanceBilling.listBills);
router.post('/api/performance-billing/bills', verifyToken, requirePermission(PERMISSIONS.GENERATE_BILLING), performanceBilling.generateBill);
router.get('/api/performance-billing/bills/:uid', verifyToken, requirePermission(PERMISSIONS.VIEW_BILLING), performanceBilling.getBill);
router.post('/api/performance-billing/bills/:uid/calculate', verifyToken, requirePermission(PERMISSIONS.GENERATE_BILLING), performanceBilling.recalculateBill);
router.post('/api/performance-billing/bills/:uid/submit', verifyToken, requirePermission(PERMISSIONS.GENERATE_BILLING), performanceBilling.submitBill);
router.post('/api/performance-billing/bills/:uid/recoveries', verifyToken, requirePermission(PERMISSIONS.MANAGE_BILLING), performanceBilling.updateRecoveries);
router.post('/api/performance-billing/bills/:uid/verify', verifyToken, requirePermission(PERMISSIONS.APPROVE_BILLING), performanceBilling.verifyBill);
router.post('/api/performance-billing/bills/:uid/approve', verifyToken, requirePermission(PERMISSIONS.APPROVE_BILLING), performanceBilling.approveBill);
router.post('/api/performance-billing/bills/:uid/lock', verifyToken, requirePermission(PERMISSIONS.APPROVE_BILLING), performanceBilling.lockBill);
router.post('/api/performance-billing/bills/:uid/reopen', verifyToken, requirePermission(PERMISSIONS.MANAGE_BILLING), performanceBilling.reopenBill);
router.post('/api/performance-billing/bills/:uid/payment', verifyToken, requirePermission(PERMISSIONS.RECORD_PAYMENT), performanceBilling.recordPayment);
router.delete('/api/performance-billing/bills/:uid', verifyToken, requirePermission(PERMISSIONS.MANAGE_BILLING), performanceBilling.deleteBill);

// ─── Dashboard ─────────────────────────────────────────────────────────────────
router.get('/api/performance-billing/dashboard', verifyToken, requirePermission(PERMISSIONS.VIEW_BILLING), performanceBilling.dashboard);

export default router;