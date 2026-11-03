import express from 'express';
import { verifyToken } from '../middleware/auth.js';
import { forbidFieldWorkers } from '../middleware/authorization.js';
import * as v2Controller from '../controllers/v2Controller.js';

const router = express.Router();

router.get(['/run-instances', '/runInstances'], verifyToken, v2Controller.listRunInstances);
router.get(['/run-instances/:runInstanceId', '/runInstances/:runInstanceId'], verifyToken, v2Controller.getRunInstance);
router.get('/coach-forms', verifyToken, v2Controller.listCoachForms);
router.get('/coach-forms/:formId', verifyToken, v2Controller.getCoachForm);
router.get('/premises-forms', verifyToken, v2Controller.listPremisesForms);
router.get('/premises-forms/:formId', verifyToken, v2Controller.getPremisesForm);
router.get('/cts-forms', verifyToken, v2Controller.listCtsForms);
router.get('/cts-forms/:formId', verifyToken, v2Controller.getCtsForm);
router.get('/cleaning-forms', verifyToken, v2Controller.listCleaningForms);
router.get('/cleaning-forms/:uid', verifyToken, v2Controller.getCleaningForm);
router.get('/tasks', verifyToken, v2Controller.listTasks);
router.get('/tasks/:taskId', verifyToken, v2Controller.getTask);
router.get('/obhs', verifyToken, v2Controller.listOBHS);
router.get('/obhs/:obhsId', verifyToken, v2Controller.getOBHS);

router.get('/task-masters', verifyToken, v2Controller.listTaskMasters);
router.post('/task-masters', verifyToken, v2Controller.createTaskMaster);
router.put('/task-masters/:taskCode', verifyToken, v2Controller.updateTaskMaster);
router.post('/assignments/create', verifyToken, forbidFieldWorkers, v2Controller.createAssignments);
router.get('/assignments/:runInstanceId', verifyToken, v2Controller.getAssignments);
router.get('/tasks/:runInstanceId', verifyToken, v2Controller.getTasks);
router.post('/tasks/submit', verifyToken, v2Controller.submitTask);
router.post('/tasks/start', verifyToken, v2Controller.startTask);
router.post('/tasks/verify', verifyToken, v2Controller.verifyTask);
router.post('/tasks/close', verifyToken, v2Controller.closeTask);
router.post('/tasks/reopen', verifyToken, v2Controller.reopenTask);
router.post('/tasks/not-applicable', verifyToken, v2Controller.markNotApplicable);
router.put('/tasks/:taskInstanceId', verifyToken, v2Controller.updateTask);
router.post('/escalations/create', verifyToken, forbidFieldWorkers, v2Controller.createEscalation);
router.post('/escalations/resolve/:escalationId', verifyToken, v2Controller.resolveEscalation);
router.get('/escalations', verifyToken, v2Controller.listEscalations);
router.get('/audit-logs', verifyToken, v2Controller.getAuditLogs);
router.get('/closure-tasks/:runInstanceId', verifyToken, v2Controller.getClosureTasks);
router.post('/closure-tasks/complete', verifyToken, v2Controller.completeClosureTask);
router.get('/worker/my-tasks', verifyToken, v2Controller.getWorkerMyTasks);
router.get('/journey/timeline/:runInstanceId', verifyToken, v2Controller.getJourneyTimeline);

export default router;
