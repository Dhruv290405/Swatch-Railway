import express from 'express';
import multer from 'multer';
import { verifyToken } from '../middleware/auth.js';
import * as evidenceController from '../controllers/evidenceController.js';
import config from '../config/index.js';
import { forbidFieldWorkers } from '../middleware/authorization.js';

const router = express.Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: config.upload.maxFileSize || 5 * 1024 * 1024 } });
const multiUpload = multer({ storage: multer.memoryStorage(), limits: { fileSize: config.upload.maxFileSize || 5 * 1024 * 1024, files: 10 } });

router.get('/api/evidence/types', evidenceController.getEvidenceTypes);
router.post('/api/evidence/upload', verifyToken, upload.single('file'), evidenceController.uploadEvidence);
router.post('/api/evidence/upload/multiple', verifyToken, multiUpload.array('files', 10), evidenceController.uploadMultipleEvidence);
router.post('/api/evidence/upload/base64', verifyToken, evidenceController.uploadEvidenceBase64);
router.post('/api/evidence/verify-face', verifyToken, multiUpload.array('images', 2), evidenceController.verifyFace);
router.post('/api/evidence/archival-check', verifyToken, forbidFieldWorkers, evidenceController.performArchivalCheck);
router.get('/api/evidence/search', verifyToken, evidenceController.searchEvidence);
router.get('/api/evidence/:id', verifyToken, evidenceController.getEvidenceById);
router.put('/api/evidence/:id', verifyToken, forbidFieldWorkers, evidenceController.updateEvidence);
router.delete('/api/evidence/:id', verifyToken, forbidFieldWorkers, evidenceController.deleteEvidence);
router.post('/api/evidence/:id/archive', verifyToken, forbidFieldWorkers, evidenceController.archiveEvidence);
router.post('/api/evidence/:id/restore', verifyToken, forbidFieldWorkers, evidenceController.restoreEvidence);
router.get('/api/storage/analytics', verifyToken, evidenceController.getStorageAnalytics);
router.get('/api/storage/per-train', verifyToken, evidenceController.getPerTrainStorage);
router.get('/api/storage/per-contractor', verifyToken, evidenceController.getPerContractorStorage);
router.get('/api/storage/daily-upload-count', verifyToken, evidenceController.getDailyUploadCount);
router.post('/api/backup/evidence', verifyToken, forbidFieldWorkers, evidenceController.performBackup);
router.get('/api/backup/logs', verifyToken, evidenceController.getBackupLogs);

export default router;
