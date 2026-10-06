# Station Cleaning – Billing System: Structural Report

> Source of truth: backend `stationBillingService.js`, `performanceBillingService.js`,
> `taskExecutionBillingService.js`, `annexureBillingService.js`, `executionSheetService.js`,
> `contractEstimationService.js`; app `billing_support_pack_screen.dart`,
> `performance_billing_screen.dart`, `daily_task_billing_screen.dart`, `pdf_report_service.dart`.

---

## 1. What "station cleaning billing" is

For a station cleaning contract, the system produces a **monthly Billing Pack** that
consolidates the contractor's operational data for a month into a single auditable
document: **how much work was done, what the quality scores were, what deductions apply,
and the final payable amount (including GST)**.

There are **four billing engines** in the backend. All are role-gated via permission
flags (`GENERATE_BILLING`, `VIEW_BILLING`, `MANAGE_BILLING`, `APPROVE_BILLING`, `RECORD_PAYMENT`).

| Engine | Backend service | Firestore data | Purpose |
|---|---|---|---|
| **Station Billing Pack** (OBHS-aligned monthly) | `stationBillingService.js` | `station_billing_packs` | The main monthly support pack used for payment approval |
| **Performance billing** (weightage / ₹-per-sqft) | `performanceBillingService.js` | `billing_configs`, `billing_bills` | Alternative monthly bill (area-sqft × rate × execution) |
| **Daily task execution billing** | `taskExecutionBillingService.js` | `task_execution_daily_bills` | Per-day act-of-work billing, 50% performance component |
| **Annexure-4B contract rule engine** | `annexureBillingService.js` + `annexureRules.js` | `annexureContractItems`, `annexureAreaComponents`, `annexureExecutions`, `annexureBillingDeductions` | 40-item contractual weightage billing with deductions |

Plus a **legacy** monthly invoice engine (`billingService.js`) producing `billingReports`
via `/api/billing/*` — kept on a separate contract screen but not part of the pack flow.

This report focuses on the **Station Billing Pack**, then summarizes the supporting engines.

---

## 2. Firestore data sources feeding a Billing Pack

When a pack is generated for contract × station × month/year, these collections are
read (filtered to the month window `YYYY-MM-01` … `YYYY-MM-DD`):

| Collection | Used for |
|---|---|
| `station_attendance`, `station_cleaning_attendance` | Attendance summary (`date`-filtered) |
| `cleaningTasks` | Activity / task completion summary (`scheduledDate`/`date`) |
| `daily_scorecards` | Scorecard average + grade distribution (`date`) |
| `complaints` | Complaints + petty issues (createdAt in window) |
| `station_feedback`, `passenger_feedback` | Feedback summary + passenger rating (30% component) |
| `inspections` | Inspection score → 20% billing component |
| `machines`, `machine_downtime` | Machine status + downtime penalty |
| `stationShiftSummaries` | Approved shift summaries → 50% task-execution component |
| `stationRuns` | Unapproved-run 20% conditional billing penalty |
| `stationCleaningForms` | Photo-evidence compliance |
| `billingRules` | Deduction rates + attendance/score penalty rates (for this contract) |
| `execution_sheet_daily_logs` + `execution_sheet_items` | Annexure-AB execution score (reference, via `executionSheetService`) |
| `contracts` | Contract value, GST %, names; `stations` for station name |

---

## 3. Full lifecycle of a Billing Support Pack

```
GENERATE (DRAFT) ──► SUBMIT ──► APPROVE ──► RECORD PAYMENT (paid/partial)
                    │
                    └──► REJECT ──► return-to-draft (DRAFT)
```

### State transitions (enforced in `stationBillingService.js`)

| From | Action | To | Guard | Permission |
|---|---|---|---|---|
| (none) | `POST /api/station-billing/generate` | `DRAFT` | month window; returns existing non-DELETED pack if present | `GENERATE_BILLING` |
| `DRAFT` | `POST .../submit` | `SUBMITTED` | must be DRAFT; sets `autoVerified` = all compliance ticks true | `MANAGE_BILLING` |
| `SUBMITTED` | `POST .../approve` | `APPROVED` | – | `APPROVE_BILLING` |
| `SUBMITTED` | `POST .../reject` | `REJECTED` | reason required | `APPROVE_BILLING` |
| `REJECTED` | `POST .../return-to-draft` | `DRAFT` | must be REJECTED | `MANAGE_BILLING` |
| `APPROVED` | `POST .../payment` | stays APPROVED; `paymentStatus = paid\|partial` | must be APPROVED; amount + reference required | `RECORD_PAYMENT` |
| `DRAFT`/`REJECTED` | `PUT .../:uid` | same | only DRAFT/REJECTED editable | `MANAGE_BILLING` |
| any | `DELETE .../:uid` | `DELETED` (soft) | – | `MANAGE_BILLING` |

Other endpoints:
- `GET /api/station-billing` – list (filters: contract, station, month, year, status, paymentStatus)
- `GET /api/station-billing/:uid` – one pack
- `PATCH /api/station-billing/:uid/compliance` – save compliance checklist
- `POST /api/station-billing/auto-generate-monthly` – batch generate for all active contracts
- Daily cron (`cron.js` line ~321, 1st of month 7 AM IST): auto-generates packs for the
  previous month and emails the Billing Support Report to station recipients.

---

## 4. The calculations (the important part)

All formulas below come from `stationBillingService.generateBillingSupportPack`
(`backend/src/services/stationBillingService.js`).

### 4.1 Base values

```
monthlyBase    = contract.contractValue / 12          (rounded)
monthlyContractValue = round(contractValue / 12)       (stored on pack)
gstRate        = contract.gstRate                       (default 18%)
```

### 4.2 Operational summaries (displayed in pack sections)

```
attendancePercentage  = round( present / totalEntries × 100 )
averageDailyManpower  = round( present / uniqueDays )
activityCompletionRate= round( (APPROVED + COMPLETED) / TOTAL × 100 )
avgScorecardScore     = round( Σ overallStationScore / daysWithScorecard, 1dp )
gradeDistribution     = count of scorecard grades A/B/C/...
complaintSummary      = total / closed / open / rejected
feedbackSummary       = total, averageRating, negativeFeedbacks
inspectionSummary     = totalInspections, deficiencies (open/closed), averageScore
pettyIssueSummary     = petty_issue complaints: total/resolved/open
evidenceSummary       = forms, formsWithPhotos, totalPhotos, evidenceComplianceRate
machineSummary        = total, inMaintenance, deployed, downtime {incidents,hours,penalty}
```

### 4.3 Machine downtime penalty

```
totalMachinePenalty = Σ penaltyAmount over machine_downtime records in window
```
This is added as a direct deduction line.

### 4.4 Attendance & score bonus-penalties (from `billingRules` config)

Only if rules exist for the contract:

```
if attendancePercentage < 90 and rules.attendancePenaltyRate:
    Amt = round( (90 − attendance%) /100 × monthlyBase × attendancePenaltyRate )
if avgScore < 70 and rules.scorePenaltyRate:
    Amt = round( (70 − avgScore) /100 × monthlyBase × scorePenaltyRate )
```

### 4.5 Unapproved station runs (20% conditional billing)

```
if stationRuns exist and any not approved:
    unapprovedRatio = unapprovedRuns / totalRuns
    approvalSubjectAmount = monthlyBase × 0.20
    approvalPenalty = round( approvalSubjectAmount × unapprovedRatio )
```

### 4.6 Task Execution component (50% of monthly base)

Built from **approved** `stationShiftSummaries` (submitted ones are ignored):

```
executionRate       = round( min(totalWorkDone / totalTenderedArea, 1) × 100 )   # %
photoCompliance     = round( areasWithPhoto / totalAreas × 100 )                 # %
flatRatio           = min( flatExecutedSqFt / flatExpectedSqFt, 1) × 100         # area-wise
taskExecutionScore  = round( avg(executionRate, photoCompliance, flatRatio) , 2) # average of present parts

taskExecutionNetBase       = round( monthlyBase × 0.50 )
achievedAmount             = round( taskExecutionNetBase × taskExecutionScore/100 )
shortfallDeduction         = round( taskExecutionNetBase × (1 − taskExecutionScore/100) )
```

### 4.7 Inspection component (20% of monthly base)

Only scored inspections with status `COMPLETED`/`APPROVED` and numeric `overallScore`:

```
inspectionComponent     = round( monthlyBase × 0.20 )
achievedAmount          = round( inspectionComponent × inspectionScore/100 )
shortfallDeduction      = inspectionComponent − achievedAmount
```

### 4.8 Passenger feedback component (30% of overall score — informational weighting)

```
feedbackScore = round( (averageRating / 5) × 100 , 2 )   # null when no feedback
```

### 4.9 Overall score & grade (OBHS-aligned)

```
scoreBreakdown = [
  Task Execution (50%)   ← taskExecutionScore
  Inspection (20%)       ← inspectionScore
  Passenger Feedback(30%)← feedbackScore
]

weightedAmount = Σ weights of present components        # e.g. 70 if only exec+insp
weightedScore  = Σ (componentScore × weight)

# Missing components are treated as FULLY achieved (neutral):
overallScore = round( ( weightedScore + (100 − weightedAmount) × 100 ) / 100 , 2 )

grade = A (≥90) | B (≥80) | C (≥70) | D (else)   
```

### 4.10 Score-based billable amount (the money)

```
deductionRate  = billingRules.deductionRate ?? 100        # percent

scoreBasedBill      = max( 0, monthlyBase × (1 − (deductionRate/100) × (100 − overallScore)/100) )
scoreDeductionAmount= max( 0, monthlyBase − scoreBasedBill )
billableAmount      = max( 0, scoreBasedBill − extraPenaltyAmount )   # extra = all operational penalties
```

`deductions` list = extra penalties (attendance, score, machine downtime, unapproved
runs) + `scoreDeductionAmount` line, sorted by amount descending.

Note: task-execution and inspection shortfalls are already reflected inside
`overallScore` (and therefore in `scoreBasedBill`) — they are NOT added again to
`extraPenaltyAmount`.

### 4.11 GST & final payable

```
gstAmount           = round( billableAmount × gstRate / 100 )
totalPayableWithGst = round( billableAmount × (1 + gstRate/100) )
```

### 4.12 Traceability layers (no effect on money)

```
estimateContribution = contractEstimationService.getPeriodContribution(...)  # variation/estimation ₹/period
amendedValue         = contractEstimationService.getAmendedContractValue(...) # ACV + revisions + SWOs
```

---

## 5. How to check / verify a pack (app screens)

All station-cleaning billing is entered from the **Station Cleaning Hub**
(`station_cleaning_hub_screen.dart`) which resolves the contract for the selected
station and opens the relevant screen:

- **Billing Support Pack** — `BillingSupportPackScreen`
  (`app/lib/view/station_cleaning/billing/billing_support_pack_screen.dart`)
  - Month/Year picker + **Go** (generates or loads the existing pack)
  - Shows every summary section from Section 4
  - **Previous Billing Packs** drawer (history; opens a past pack)
  - **Compliance Document Checklist** (7 documents) — editable by `MANAGE` roles
  - Action buttons visible by role + status:
    - DRAFT + manage → **Submit Pack for Review**
    - SUBMITTED + approve → **Approve / Reject** (reject needs reason)
    - APPROVED + pay → **Record Payment** (amount, mode, reference)
  - **Download PDF** (AppBar icon) → `PDFReportService.generateStationBillingPdf`
    prints the whole pack + FINANCIAL SUMMARY; shares via `printing`.

- **Daily task execution billing** — `DailyTaskBillingScreen`
  (single date or date range; preview / generate stored daily bills)
- **Performance billing** — `PerformanceBillingScreen`
  (scorecard + `billing_bills`; config via `PerformanceBillingConfigScreen`)
- **Annexure-4B** — `AnnexureBillingConfigScreen`
- **Contract estimation / variations / SWO** — `ContractEstimationScreen`
- **Reports** — `ReportListScreen` → section **"Billing Reports"** includes Billing
  Support Report (`monthly_billing`) and Daily Billing Reports with PDF download.

### Role-based actions in the pack screen (`_can`)

| Role | VIEW | GENERATE | MANAGE | APPROVE | PAY |
|---|---|---|---|---|---|
| SUPER_ADMIN, COMPANY_MASTER, ADMIN, RAILWAY_ADMIN | ✓ | ✓ | ✓ | ✓ | ✓ |
| RAILWAY_MASTER, CONTRACTOR_MASTER, CONTRACTOR_SUPERVISOR | ✓ | – | – | – | – |
| CONTRACTOR_ADMIN | ✓ | ✓ | ✓ | ✓ | – |

---

## 6. Supporting engines (summary)

### 6.1 Performance billing (`performanceBillingService.js`)
- Config `billing_configs` per contract: `ratePerSqft`, `areaRateOverrides`,
  `areaWeightages` (must total 100%), categories (50/20/30), `penaltyRules`, `gstRate`.
- Scorecard:
  ```
  scheduledWorkValue = Σ (areaSqft × rate × requiredTasks)
  grossWorkValue = Σ (areaSqft × rate × verified)   # verified = min(required, Σtimes in APPROVED shift summaries)
  executionAchievement = gross / scheduled × 100
  overallScore = marks summed over categories, then grade A–E
  lessExecutionAmount  = scheduled × (100 − overallScore)/100
  eligibleAmount = min(grossWorkValue, scheduledWorkValue − lessExecutionAmount)
  penalty = slab rule (NONE / PERCENT_OF_ELIGIBLE / PERCENT_OF_MONTHLY_BASE / FIXED_AMOUNT)
  netAmount = max(0, eligibleAmount − penalty − otherRecoveries)
  GST → totalPayable
  ```
- Bill lifecycle: `DRAFT → CALCULATED → SUBMITTED → VERIFIED → APPROVED → LOCKED`
  (plus `reopenBill`, `recordPayment` with `paid/partial`).

### 6.2 Daily task-execution billing (`taskExecutionBillingService.js`)
- Per day: `expectedWorkValue`, `actualExecutionValue`, `taskExecutionScore` (50%),
  inspection (20%), feedback (30%); missing categories default **neutral (100%)**.
- `grossEligibleWorkValue = actualExecutionValue`; score **never scales the work
  value** — it only picks the penalty slab. Plus flat ₹200/day incomplete-execution
  penalty (configurable) + otherDeductions → net → GST.
- Range preview/generate; stored per contract/station/date.

### 6.3 Annexure-4B engine (`annexureBillingService.js` + `annexureRules.js`)
- 40 master contractual items (each with `contractualWeightage`, frequency, unit).
- Deduction model (pure functions, decimal-safe):
  ```
  dailyMoneyValue        = ACV × weightage / 100 / 365
  missedDeduction        = dailyMoneyValue × missedCount
  areaAllocationCheck    = per-item area weightages may not exceed item weightage
  transferUnavailableWeightage → Item 1 transfer; addNewItemWeightage → taken from Item 1
  ```
- Lifecycle per item: seed → validate weightage → execution records
  (`COMPLETED / PARTIALLY_COMPLETED / NOT_COMPLETED / WAIVED / NOT_APPLICABLE`) →
  calculate deductions → finalize immutable `annexureBillingDeductions`.

### 6.4 Execution sheet (Annexure-AB, reference 50%)
`executionSheetService.getMonthlySummary` computes an item-execution score from
`execution_sheet_daily_logs` (status `SUBMITTED`) and approved shift summaries, and is
stored on the pack as `executionSheetSummary` (shown as a reference section; the money
uses the shift-summary Task Execution component in §4.6).

---

## 7. Money helpers (decimal-safe)

All money math goes through `backend/src/utils/money.js`:
`roundMoney` (2dp), `mulMoney` (integer-paise multiply), `pctOf`, `ratioSafe`,
`clampPct`. `areaWeightageModel.js` derives rates/values per area (daily contract
value = ACV / contract days; default 365).

---

## 8. Known issues / things to verify

1. **`performanceBillingService.js` legacy paths** — `getOrCreateConfig` previously
   referenced `contract` for `computeContractDays` (`contract.startDate`). The current
   code is fixed, but confirm any older `billing_configs` documents migrated correctly
   (see `getOrCreateConfig`). 
2. **Firestore composite indexes** — the pack query needs
   `contractId + stationId + month + year` (listed in the file header of
   `stationBillingService.js`) and `machine_downtime stationId+startTime`,
   `inspections stationId+createdAt`. If not created, generation is skipped.
3. **Execution sheet catch** — if `executionSheetService.getMonthlySummary` throws, the
   summary is skipped (logger.warn) but the pack still generates; `executionSheetSummary`
   will be empty/`configured:false`.
4. **PDF generation is CPU-heavy** — `generateStationBillingPdf` builds a large
   `pw.MultiPage`; on low-end devices it can trigger an ANR dialog. Currently mitigated
   with a loading overlay; the PDF itself stays on the main isolate.
5. **Compliance auto-verification** — `submitPack` sets `autoVerified = true` only when
   EVERY compliance checkbox is true; it does not block submission.
6. **Stale data in live Firestore** — an old manual annexure-4B test dataset exists and
   may appear in config screens; it is not part of the pack flow.

---
