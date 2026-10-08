# OBHS Report
## 1. Flutter screens under OBHS / operations


## 2. WATER CHECK screen - data type casts

WaterCheckModel.fromJson uses safe casts (as String? with defaults). No direct s String on int observed in water_check_model.dart. The error 	ype int is not a subtype of type String in type cast typically occurs when code does alue as String but value is int/num. Models in this codebase mostly use .toString()/coercion helpers elsewhere (see analytics_model.dart using _asInt).

Repositories send appropriate types; API response parsing needs to be defensive if any numeric field is cast to String without conversion.


## 3. SAFETY CHECKS screen + backend

Flutter:
- E:/swach railways 1/app/lib/view/obhs_screens/obhs_safety_checks_screen.dart: submits SafetyCheckModel via SafetyRepository.submitSafetyCheck({required SafetyCheckModel check}) which does jsonEncode({...check.toJson(), deviceTimestamp: ...}). toJson serializes dates/arrays/strings.
- Model: E:/swach railways 1/app/lib/model/safety_check_model.dart - fromJson parses scheduledTime/completedAt via DateTime.parse/tryParse on string values; deficiencyReports/photos cast elements as String.

Backend (Node/Express + Firestore):
- Routes: E:/swach railways 1/backend/src/routes/obhs.js - GET /api/obhs/safety-checks, POST /api/obhs/safety-checks/submit, POST /api/obhs/safety-checks/report-deficiency (lines ~40-42)
- Controller: E:/swach railways 1/backend/src/controllers/obhsController.js - listSafetyChecks(req.query.runInstanceId), submitSafetyCheck(req.body), reportSafetyDeficiency(req.user, req.body) (lines ~111-124)
- Service: E:/swach railways 1/backend/src/services/obhsService.js
  - getSafetyChecks(runInstanceId): validates runInstanceId required; queries safety_checks where runInstanceId == runInstanceId; returns checks (lines ~632-641)
  - submitSafetyCheck(body): accepts { checkId, runInstanceId, coachNo, scheduledTime, fireExtinguisherStatus, fsdsStatus, cctvStatus, emergencyEquipmentStatus, photos, deficiencyReports, remarks }. Validation: if no checkId and not (runInstanceId+coachNo) -> throw ValidationError (line ~646). Uses slot-based docId when no checkId: _slotDocId( safety, runInstanceId, coachNo, scheduledTime). Sets fields; merges. (lines ~643-673)
  - reportSafetyDeficiency(userData, body): requires checkId and deficiencyReport (non-empty). Gets doc, updates deficiencyReports via dmin.firestore.FieldValue.arrayUnion(deficiencyReport). (lines ~675-689)

Validation/error text patterns:
- Backend throws ValidationError with messages like Provide checkId or runInstanceId together with coachNo. (obhsService.js:646, 587). No exact message checkid and runinstanceid found. Controller passes through service errors.
- Flutter sends SafetyCheckModel.toJson() + deviceTimestamp; backend expects fields per service. Mismatch risk: Flutter may send id as empty string for new checks - backend handles via slotDocId.

Expected vs sent fields (typical):
- Flutter submitSafetyCheck passes full SafetyCheckModel (has id, runInstanceId, scheduledTime as DateTime in model but toJson converts scheduledTime to Iso8601String; photos/deficiencyReports as Lists). Backend reads checkId/runInstanceId/coachNo/scheduledTime as-is. OK alignment.

Root cause hypotheses for validation errors: if Flutter omits coachNo/runInstanceId when creating new (id empty), backend requires one of them - correct. Also case sensitivity not an issue. The specific text checkid and runinstanceid was not found in codebase; likely from API response in some environment/log.


## 4. PETTY REPAIRS
Escalate flow: shows dialog -> RepairRepository.escalateRepair POST /api/obhs/petty-repairs/escalate with {repairId, escalatedTo, deviceTimestamp}. Backend obhsService.escalatePettyRepair requires repairId, validates exists, updates {isEscalated:true, escalatedTo, status:" ESCALATED\, updatedAt}. No explicit loading dialog in escalate; repo has 30s timeout. No WillPopScope. No blocking loops/awaits that never resolve visible. If hang/back issue occurs, likely undisposed loading dialog from another path or slow network - code here is safe.


## 5. OBHS analytics screen

Flutter: E:/swach railways 1/app/lib/view/obhs_screens/obhs_analytics_screen.dart
- Loads via Future.wait calling AnalyticsRepository methods for janitor-performance, coach-cleanliness, attendance-compliance, task-completion, penalty-risk; passes runInstanceId. Uses ObhsRunScope to select run. Empty handling via _empty() when lists/maps empty.

Repository: E:/swach railways 1/app/lib/repositories/analytics_repository.dart
- getJanitorPerformance(runInstanceId): GET $baseUrl/api/analytics/janitor-performance?runInstanceId=... parses data.performance -> List (model uses _asInt/coercion).
- getCoachCleanliness(runInstanceId): GET pi/analytics/coach-cleanliness?runInstanceId=... parses data.coaches. (model: coachNo as String, numeric fields coerced via _asInt/toDouble).
- getAttendanceCompliance({required runInstanceId}): GET pi/analytics/attendance-compliance?runInstanceId=... returns Map.
- getTaskCompletionPercentage/getPenaltyRiskReport similar patterns.

Endpoints called by app (analytics): janitor-performance, coach-cleanliness, attendance-compliance, task-completion-percentage, penalty-risk-report (all with runInstanceId param).

Broken endpoints/empty handling: app calls multiple endpoints independently (guarded); if any fail returns null and UI shows empty states or partial data - resilient. No obvious broken endpoint strings; endpoints match repo usage. Empty handling is explicit (checks .isEmpty and shows _empty()).


## 6. OBHS runs / instance assignment (summary)
Backend createRunInstance validates required fields, prevents duplicates, checks coach limits (<=2 per worker), enforces AC rules (both attendant+janitor for AC; no attendant for non-AC). Flutter sends coachPosition as int and includes workerId/workerName/workerRole for compatibility. Failure messages come from ValidationError/ConflictError/NotFoundError as above.


## 7. Backend routes/controllers/services for OBHS

Routes:
- E:/swach railways 1/backend/src/routes/obhs.js - main OBHS routes (prefix /api/obhs*), includes water-checks (GET /water-checks, POST /water-checks/submit, GET /water-checks/alerts), safety-checks (GET, POST submit, POST report-deficiency), petty-repairs (GET, POST submit, POST escalate), ratings, complaints, feedback, tasks, supervisor dashboard, worker active-run. Also param routes for /:obhsId. (lines ~1-102)
- E:/swach railways 1/backend/src/routes/runInstances.js - / (POST/GET), /:runInstanceId (PUT/DELETE), /train/:parentTrainId, /obhs/:runId, journey activate/complete, /active-run. (lines ~1-17)
- E:/swach railways 1/backend/src/routes/analytics.js (if relevant) - analytics endpoints separate.

Controllers:
- E:/swach railways 1/backend/src/controllers/obhsController.js - delegates to obhsService for core operations (water/safety/repairs/ratings/complaints etc.). Methods: listWaterChecks, submitWaterCheck, getWaterAlerts, listSafetyChecks, submitSafetyCheck, reportSafetyDeficiency, listPettyRepairs, submitPettyRepair, escalatePettyRepair. (lines ~92-141)
- E:/swach railways 1/backend/src/controllers/obhsAnalyticsController.js - analytics endpoints.
- E:/swach railways 1/backend/src/controllers/runInstanceController.js - create/update/list/remove/getObhsRun/activateJourney/completeJourney/getActiveRunForWorker.

Services:
- E:/swach railways 1/backend/src/services/obhsService.js - core OBHS logic. Water checks: getWaterChecks/submitWaterCheck/getWaterAlerts. Safety: getSafetyChecks/submitSafetyCheck/reportSafetyDeficiency. Petty repairs: getPettyRepairs/submitPettyRepair/escalatePettyRepair. Includes validation, slot-based docId generation (_slotDocId), Firestore operations. (see specific sections above)
- E:/swach railways 1/backend/src/services/obhsAnalyticsService.js - analytics computations.
- E:/swach railways 1/backend/src/services/runInstanceService.js - run instance lifecycle and task generation.

Field name mismatches (camelCase vs snake_case):
- Flutter sends camelCase generally (runInstanceId, coachNo, checkTime, waterStatus, lowWaterAlert, photoUrl). Backend stores/reads same camelCase in Firestore and API. Models in Flutter use camelCase; backend JS objects use camelCase. No obvious snake_case mismatch in the reviewed flows. Compatibility fields added in CoachAssignment.toJson (workerId/workerName/workerRole) to match backend expectations.

Obvious mismatches observed: None critical in core OBHS flows reviewed. The slotDocId logic allows idempotent submits without client-generated IDs.


## Root-cause hypotheses (final)
1. Type cast error: If backend returns numeric values where code does json[x] as String (without toString), throws. Search for such casts. water_check_model uses safe nullable casts.
2. Safety validation text not found as written; backend requires checkId OR (runInstanceId and coachNo).
3. Petty repairs hang: no blocking await loop in escalate; repo has 30s timeout; no WillPopScope. Likely external (network) or undisposed dialog elsewhere.
4. Analytics: guarded and handles empty states; endpoints align with repo.
5. Instance creation failures: validation errors (duplicates, AC rule enforcement, worker limits, missing fields).

--- END ---
