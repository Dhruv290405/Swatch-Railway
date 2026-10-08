# Swachh Railways – Tester's Guide (No Technical Knowledge Needed)

This guide explains **what the app is**, **who uses it**, and **exactly how to test every screen** —
written for someone who has never seen this project before. Read Sections 1–4 first, then follow the
step-by-step flows. When you see a **step**, do it in the app and note what happened.

---

## 1. What is this app (in one paragraph)

Indian Railway stations are cleaned by private companies (called **Contractors**). A contractor signs a
**Contract** with the railway to clean a station for money. The railway checks the cleaning quality and
pays the contractor based on **what was cleaned and how well**.

This app is the single system where:
- The **Railway** creates entities & contracts, inspects cleaning, and approves payment.
- The **Contractor** manages its team, does daily cleaning, records photo proof, and bills the work.

The whole money cycle: **Contract → Areas & Team → Daily Tasks → Work Proof (Shift Summary) →
Inspection & Feedback → Daily Billing → Monthly Performance Bill → Approval → Payment**.

---

## 2. What you need to test

1. An **Android phone** (or emulator) with internet.
2. The **APK** (`app-release.apk`) — shared by the team.
3. **Login accounts for each role** — the team will give you these. Built-in master account:

   - Email: `admin@gmail.com`
   - Password: `123456`  →  this is **Super Admin** (sees/does everything).

> Use **dummy data only** (fake station "TEST STATION", fake workers). The app talks to a staging server.

---

## 3. The people (roles) in the app

| Role | Who is this? | Main job |
|---|---|---|
| **Super Admin** | System owner | Everything |
| **Railway Master / Admin / Railway Admin** | Railway officers | Create entities/contracts/users, approve, view all |
| **Railway Inspector / Supervisor** | Field officers | Inspect & score cleaning quality |
| **Company Master (CM)** | Owner of contractor company | Manage team & contracts, **configure rates & billing rules** |
| **Contractor Admin (CA)** | Contractor's office manager | **Operate billing** (daily + performance), manage operations |
| **Contractor Supervisor (CS)** | Field supervisor | Generate/complete tasks, attendance, shift summaries with photo proof |
| **Worker / Janitor / Attendant** | Cleaning staff | Check-in, do assigned tasks, upload photos |

**The single most important rule to test:**
- **CM configures, CA operates.** CM sets rates/weightage/rules; CA runs daily billing and performance bills.
- **CA must NOT be able to open rate/rule configuration.** If CA can change rates → **BUG, report it.**
- **CM must NOT see "Daily Billing".** If he does → **BUG.**

---

## 4. Getting to the Station Cleaning Module Hub

1. Log in. You land on your role's dashboard.
2. Open **Station Cleaning** in the menu → tap **Module Hub** (or open a station, then the hub).
3. The hub has a **station dropdown at the top** — but only these roles can switch stations:
   `Super Admin, Admin, Railway Admin, Company Master, Railway Master, Contractor Master`.
   Everyone else sees their assigned station's name only (cannot change) — **that is correct, not a bug.**
4. If the hub shows **"No contract linked to this station"** when you open a billing tile, the station
   has no contract yet — create one first (Section 6, Flow 1).

**Module Hub layout (3 sections of tiles):**

| Section | Tiles |
|---|---|
| **Operations** | Generate Task · Supervisor Attendance · Supervisor Shift · Inspection · Reports |
| **Billing & Rates** | Billing · Daily Billing¹ · Performance Billing · Area Rates & Weightage² |
| **Records & Support** | Audit Log · Area Management · Passenger Feedback |

¹ **Daily Billing tile is hidden for CONTRACTOR_MASTER**
² **Area Rates & Weightage tile is hidden for CONTRACTOR_ADMIN**
→ Verify these two rules with the respective logins.

---

# 5. OPERATIONS — deep dive (what each tile does & how to test it)

## 5.1 Area Management  (start here — everything depends on areas)

**What it is:** The station is broken into **cleaning areas** (Platform-1 corridor, waiting hall,
toilets, parking…). Each area has a **size (sq.ft.)** and a **cleaning frequency** (how often it must
be cleaned). Areas are the unit of ALL work, tasks and billing.

**Hierarchy you'll see in the app:** Station → Platform → Area (with size + frequency). ("Zone" exists
in data but is barely shown — don't worry if you don't see zones.)

**Steps:**
1. Hub → **Area Management** → title `Area List`.
2. Check the header counts: `Total Areas / Active / Inactive`.
3. Search for an area (`Search areas...`), open a card — you'll see `Main:`, `Sub:`, `Basic:` (sq.ft.).
4. Tap the **+** button → fill: *Area name, Type, Area size (sq.ft.), Frequency, Times per period, Main Area* → save.
   - ✅ Success message: **`Area updated`**
   - ❌ If you miss fields: `Select or enter a main area` / `Select at least one sub-area`.
5. Delete an area → confirm dialog `Delete "X"? This cannot be undone.` → ✅ `Area deleted`.

**Who sees it:** Super Admin, Company Master, Contractor Admin, Railway Master, Railway Admin (Railway Inspector does **not** see this tile).

---

## 5.2 Generate Task  (the daily work engine)

**What it is:** Turns areas into **today's tasks** for a supervisor. You pick the station, the
supervisor, the areas, **how many times each area needs cleaning today (occurrences)** and time slots,
then press generate — tasks appear on the supervisor's phone.

**Steps:**
1. Hub → **Generate Task** (title `Generate Tasks`).
2. Pick a **supervisor** (required). If you skip it → ❌ `Select a supervisor. Generated tasks are assigned to the contractor supervisor who completes them.`
3. Search & select areas; set **`Occurrences today`** per area with the +/- counter.
   Optional: `Add Task Time` to add custom times.
4. Watch the summary bar: `date · shift · supervisor · N area(s) · ~N tasks`.
5. Tap **`+ Generate Tasks (N areas)`**.
   - ✅ `Tasks generated successfully! N created`
   - ✅ or `Frequency adjusted: N extra task(s) cancelled`
   - ✅ or `Already up to date`
   - ❌ `Select at least one activity for: X` (area without activities)
   - ❌ `Set the occurrences for at least one selected area.`

**Chain check:** after generating, the assigned **Contractor Supervisor** must see these tasks in his
task list, complete them, and be forced into a **Shift Summary** (dialog `Shift Summary Required`).

**Note:** the screen has a "By Frequency" concept in code but only the **occurrences** mode works — if
you expected frequency-based auto generation, that's a known gap (log it, don't retest repeatedly).

---

## 5.3 Supervisor Shift

**What it is:** Assigns a shift window to each supervisor. Windows are fixed:
`Morning 04:00–11:59` · `Evening 12:00–19:59` · `Night 20:00–03:59`.

**Steps:**
1. Hub → **Supervisor Shift**.
2. Find a supervisor (search box), change shift → save.
3. Leave and return → value must persist (reload the screen).
4. Log in as **Railway Supervisor/Inspector** → this menu should be **absent** for them.

---

## 5.4 Supervisor Attendance

**What it is:** Daily attendance of supervisors with **start / mid / end marks** plus photo + GPS
identity audit (proof the right person was there).

**Steps:**
1. Hub → **Supervisor Attendance**.
2. Pick today → see each supervisor's status rows. Search by name/status.
3. Pick an **older date** (up to 365 days back) → history loads. **Future dates should not be selectable.**
4. Tap a row → detail dialog shows which marks are `Not marked` for absentees.

---

## 5.5 Inspection  (railway checking the cleaning)

**What it is:** Railway officer schedules/starts an inspection, scores areas, notes **deficiencies**,
and approves or rejects. Scores feed billing (20% of the performance score).

**Steps:**
1. Hub → **Inspection** → title `Inspections - {station}`.
2. Filter by status (`Scheduled / In Progress / Completed / Approved / Rejected`) and type
   (`Schedule / Surprise`).
3. As **Railway Admin / Inspector** → tap **+** to create → open it →
   `Start` → `submit ratings` → `Approve`.
   - ✅ messages: `Inspection created`, `Inspection started`, `Ratings submitted`, `Inspection approved`
   - **Reject** requires a reason: dialog `Reject Inspection`, field `Rejection Reason *` → `Inspection rejected`
   - ❌ Reject with empty reason must be blocked.
4. As **Railway Master** → you can view but should have **no approve buttons** (view-only).

---

## 5.6 Reports

**What it is:** Generate, download and email reports. Three tabs: **`Overview | Generate | History`**
(Contractor roles see `Generate | History`).

**Steps:**
1. Hub → **Reports**.
2. **Overview** → Today / This Week / This Month stat cards must load (no spinner forever).
3. **Generate** → sections `Billing Reports / Daily Reports / Monthly Reports / On-Demand Reports` →
   pick a report → choose `Single Day` or `Date Range` → **Generate Report** (`Generating...`).
   - Billing reports need a billing contract: if missing you'll see
     `No billing contract linked to this station — generate bills from the Daily Billing screen first.`
4. **History** → open a row's menu → **Download PDF** / **Download Excel** / **Send Email**.
   - ✅ file saves; ❌ `Download failed: ...` etc. is a bug.
5. Log in as a **Contractor** role → only 9 report types should be visible (railway sees 19).

---

## 5.7 Shift Summary  (the daily proof-of-work chain)

**What it is:** At end of shift, the supervisor submits **per-area photos + GPS + remarks** for
completed/missed areas. It is then **approved/rejected by the railway**. **Only APPROVED shift
summaries count as "executed work" for billing** — this is the link between field work and money.

**Steps:**
1. Log in as **Contractor Supervisor** → My Tasks → complete tasks → `Shift Summary Required` dialog → **Shift Summary**.
2. Try to submit with a missing remark or missing photo → ❌ submit button must be blocked.
3. Fill everything → **`Submit Summary (N areas)`** → ✅ `Shift summary submitted for approval!`
   - GPS failure message: `Live location could not be captured. Please enable location and retake the photo.`
4. Log in as **Railway Admin** → **Shift Summary Approval** → open the item →
   `Approve Summary` → ✅ approved. Or **Reject with reason** →
   supervisor now sees `Shift Summary Resubmit` and can resend.
5. **After approval**, check Daily Billing — that day's executed counts should now include it.

---

# 6. BILLING & RATES — deep dive (the money section)

> Remember: **CM configures rates, CA operates billing.** Also remember daily bills are **immutable**
> (generated bills can't be silently changed — that's by design).

## 6.1 Billing  (monthly Billing Support Pack with approval workflow)

**What it is:** A monthly invoice **with evidence**: attendance, tasks, inspections, feedback,
machines, penalties → net payable → routed through **Submit → Approve/Reject → Record Payment**.

**Steps:**
1. Hub → **Billing** tile → title `Billing Support Pack`.
2. Pick **Month / Year** → tap **`Go`** (view-only roles see `View` instead).
3. Scroll all sections: Attendance, Task Completion, Scorecards, Inspection, Feedback, Petty Issues,
   Photo Evidence, Machines, Task Execution (50%), Inspection Score (20%), Passenger Feedback (30%),
   Penalties, and **Financial Summary** (Net Billable → GST → Total Payable).
4. Tick/untick the **Compliance Document Checklist** → values must persist after leaving.
5. **`Submit Pack for Review`** (status DRAFT→SUBMITTED).
6. Switch to an **approver** role → **`Approve`** or **`Reject`** (reason dialog). Rejected pack shows
   `Rejection: <reason>` in red in the header.
7. Switch to a **payment** role (Super Admin / Admin / Railway Admin / Company Master) →
   **`Record Payment`** (fields `Amount*`, `Mode*`, `Reference*`) → ✅ `Payment recorded`.
   - ⚠ **CA must NOT see Record Payment** (no PAY permission) — verify.
8. App-bar download icon → PDF `BillingPack_{contract}_{m}_{y}.pdf` opens the share sheet.
9. **Previous Billing Packs** chips must list older months; tapping one loads that pack.

---

## 6.2 Daily Billing  (freeze one day's bill)

**What it is:** Preview and **generate (freeze)** the bill for a single day or a date range. Money is
calculated from areas × rates × executions — **you never type money in**.

**The math shown on screen:** `Value = Area × Rate × Executions`
- Each area owns a slice of the day's money (via weightage %) or is billed sq.ft × rate × executions.
- Executions counted **only from approved shift summaries**.
- Daily score = **Task Execution 50 · Railway Inspection 20 · Passenger Feedback 30** → grade A–E.
- Deductions = score-based penalty slab + flat `incomplete day` penalty if execution <100% + other
  deductions; then GST; then **Net payable / Total payable**.

**Steps:**
1. Hub → **Daily Billing** (hidden for **Contractor Master** — verify).
2. Mode chips: `Single Day` | `Date Range`.
3. **Single day:** pick a date (use `‹` `›` arrows) → **`Preview / View`** →
   ✅ `Preview loaded for YYYY-MM-DD`.
4. Read the four cards:
   - **Amount Breakdown** — Expected work value, Actual executed value, penalty, Net payable, GST.
   - **Performance Summary** — 50/20/30 weights, final score + grade.
   - **Area-wise Execution** — table `Area | SQFT | Rate | Wt% | Req | Done | Expected₹ | Actual₹`.
     ⚠ If its subtitle says **`No active rate or weightage configured — values are zero`** →
     that's a config problem (bills will be ₹0) → **report it**.
5. Tap **`Generate`** (needs GENERATE permission) → ✅ `Daily bill generated (immutable).`
   The day now appears in the **Daily Billing Reports (Cart)** and **Monthly Bills**.
6. **Key test — no duplicates:** tap `Generate` again on the same date → ✅ `Existing bill reused.`
7. **Date Range:** FROM/TO → `Preview Range` → ✅ `Range report ready: n day(s) previewed.` →
   `Generate All` → ✅ `Range: X generated, Y reused, Z failed — no duplicates.`
8. Download PDFs (day / range / month icons) → ✅ `PDF saved: {path}` + share sheet.
9. **View-only roles** (Railway Master, Contractor Supervisor) → no `Generate` button, and the
   banner reads: `View-only access. You can check all billed dates — bill generation is done by
   contractor admin / railway.`

---

## 6.3 Area Rates & Weightage  (how the contract's money is split)

**What it is:** Instead of typing ₹ rates for every area, you give each area a **weightage %** of the
daily contract money. The app derives `₹/sq.ft.` and `₹/day` automatically. **Total must equal exactly
100%.** This is a **CM/top-role configuration screen** (tile hidden for CONTRACTOR_ADMIN).

**Steps:**
1. Hub → **Area Rates & Weightage** → title `Area Weightage Allocation`.
2. Check **Contract Value** card shows `Annual (ACV)` and `Daily value`. If it shows `Not set` → nothing
   can be calculated → **report it**.
3. Type `%` into 2–3 areas → watch the live chips `₹x.xxxx /sq.ft.` and `₹x.xx /day` appear.
4. Try to exceed 100% → the field must clamp with inline **`Max X%`**.
5. The total banner walks through states:
   - grey `Allocated: 0.00%`
   - red `... must total EXACTLY 100%` / `EXCEEDS 100%`
   - green `Allocated: 100.00% — Fully allocated`
6. Save while ≠100% → ❌ blocked (`Weightage must total EXACTLY 100%...`).
   Save at exactly 100% → ✅ `Weightage saved — daily money & ₹/sq.ft. auto-derived`. Leave & return → persisted.

**How this ties to money (for checking the maths):**
`area daily money = Annual contract value × area weightage% ÷ contract days`; and
`per-execution value = area daily money ÷ required executions that day`.

---

## 6.4 Performance Billing  (the monthly bill + approval workflow)

**What it is:** The main **monthly bill**. Dashboard lists bills; you draft a new one and walk it
through statuses: **DRAFT → CALCULATED → SUBMITTED → VERIFIED → APPROVED → LOCKED**, then payment.

**Steps:**
1. Hub → **Performance Billing**.
2. Check dashboard strip: `Bills / Billed ₹ / To Pay ₹ / Paid ₹`, and bill cards with status pills.
3. Select **Month / Year** → **`New Bill`** (GENERATE roles; others see `View`).
   - ⚠ If a dialog **`Cleaning rate not configured`** appears — this is a **known suspect bug**:
     it blocks generation when billing was configured purely by **weightage** (which by design stores
     no default rate). Try both: with a default rate set (works) and weightage-only (likely blocks).
     **Log it with a screenshot.**
4. Open a bill → see **Amount Calculation** (Scheduled → Less Execution → Eligible → Penalty →
   Other Recoveries → Net → GST → Total Payable) and **Audit Trail**.
5. Drive the workflow buttons (each needs the right permission):
   `Calculate Bill` → `Submit for Verification` → `Verify Against Records` → `Approve` →
   `Lock Bill (Final)` → `Record Payment` (needs PAY). Non-creator roles should see fewer/no buttons.
   - Other actions: `Edit Other Recoveries`, `Reopen Bill` (reason required), `Delete Bill` (confirm).
6. **Scorecard** button → `Monthly Performance Scorecard` — big score circle, grade, 50/20/30 category
   bars, area-wise `Scheduled ₹ / Actual ₹`, and the Eligible-amount explanation. Everyone (even
   view-only roles) should be able to open this.
7. ⚙ **Billing Configuration** icon (app bar) — **only for CONFIGURE roles** (CM, Super Admin, Admin,
   Railway Admin, Company Master). Railway Master / Contractor Supervisor must NOT see it.

---

## 6.5 Billing Configuration (⚙ inside Performance Billing)

**What it is:** The rules engine every bill uses: score categories, per-area rates/weightages,
penalty slabs, GST, other deductions. 4 tabs + **`Save Configuration`**.

**Steps:**
1. Open ⚙ → **Categories** tab: banner must read total **100** (green).
2. **Area Rates** tab: enter weightages summing to 100 → `Rate ₹` fields become **read-only** with
   derived values. Save at 97% → ❌ `Area weightages must total exactly 100% (currently 97%)`.
3. **Penalty** tab:
   - `Penalty amount per incomplete day (₹)` — flat fine for any day execution <100%.
   - Slab cards e.g. `Score >= 85% — no penalty`, `Score 70–84% — 5% of eligible`, `below 60 — ₹500`.
   - **Add Penalty Slab** → try invalid data: `Score <` ≤ `Score >=`, 450% → must be blocked with
     clear messages; `Penalty slabs overlap` must be rejected.
4. **General** tab: set `Rate per sqft (₹)`, `GST Rate (%)`, `Other Contractual Deductions (₹)` →
   **Save Configuration** → ✅ `Configuration saved`.
5. Return to Performance Billing → generate/open a bill → penalty, GST and other-deduction rows must
   **match what you configured** (this proves config actually drives the bill).

---

## 6.6 Annexure-4B config (advanced rules — currently unreachable)

There is an `Annexure-4B` configuration screen (seed 40 contract items, area weightage per item,
`Calculate deductions` / `Finalize (immutable)`, weightage **Transfers**), but **no navigation in the
app opens it** — investigate and report as a bug: *"Annexure-4B config screen exists but has no entry
point."* If the team gives you a way to open it, test: seed items → add area → exceed item weightage
(should block) → mark item unavailable (weightage transfers to Item 1) → calculate → finalize.

---

# 7. RECORDS & SUPPORT

## 7.1 Audit Log
Hub → **Audit Log** → shows who did what (action, user, timestamp). Every billing/approval action you
performed anywhere should appear here. Filter by station. An empty audit log after lots of actions = bug.

## 7.2 Passenger Feedback
Hub → **Passenger Feedback** → bottom sheet with 4 options:
- **Submit Passenger Feedback** — record PNR + ratings (this feeds the 30% billing component).
- **View Feedback** (×2 lists) — browse recorded feedback.
- **Generate QR Code** — print/display QR for passengers to scan and give feedback.
**Chain check:** submit feedback → it must appear in the list AND improve/alter the feedback score used
in Daily Billing's Performance Summary.

---

# 8. The happy-path chains to run at least once

**Chain A — Setup (Railway / CM):**
Create contract for station → Area Management (create 3–5 areas with sizes/frequency) →
Area Rates & Weightage (allocate exactly 100%) → Billing Configuration (GST + penalty slabs) → save.

**Chain B — Daily field work (CS + Railway):**
Supervisor Shift (assign shift) → Generate Task (pick supervisor + areas + occurrences) →
Supervisor sees tasks on his phone → completes work → Shift Summary (photos + remarks) submitted →
Railway Admin **approves** it → Supervisor Attendance for the day is marked.

**Chain C — Daily money (CA):**
Daily Billing → Preview yesterday → check Area-wise Execution counts include the approved summary →
Generate (immutable) → re-Generate (must say `Existing bill reused.`) → download PDF.

**Chain D — Monthly money (CA → Railway):**
Performance Billing → New Bill → Calculate → Submit for Verification → (Railway) Verify → Approve →
Lock → Record Payment → verify Audit Log entries → Scorecard shows the same numbers.

**Chain E — Support pack approval (CA → approver → payer):**
Billing tile → Go → Submit Pack for Review → Approve/Reject with reason → Record Payment → PDF.

**Chain F — Quality (Railway Inspector):**
Create Inspection → start → ratings + deficiencies → approve; check scores appear in Daily/Performance
billing; register Passenger Feedback → verify 30% component changes.

---

# 9. Role visibility cheat-sheet (verify these!)

| Screen / Action | Must NOT be visible to |
|---|---|
| **Daily Billing** tile | `CONTRACTOR_MASTER` |
| **Area Rates & Weightage** tile | `CONTRACTOR_ADMIN` |
| **Billing Configuration ⚙** | `RAILWAY_MASTER`, `CONTRACTOR_SUPERVISOR` |
| **Daily Billing → Generate** button | `RAILWAY_MASTER`, `CONTRACTOR_SUPERVISOR` (view-only) |
| **Support Pack → Record Payment** | `CONTRACTOR_ADMIN` (no PAY permission) |
| **Inspection → create/approve** | `RAILWAY_MASTER` (view-only) |
| **Station dropdown in hub** | everyone except `SUPER_ADMIN, ADMIN, RAILWAY_ADMIN, COMPANY_MASTER, RAILWAY_MASTER, CONTRACTOR_MASTER` |
| **Area Management / Generate Tasks tiles** | `RAILWAY_INSPECTOR` |

---

# 10. Known issues to log immediately (already flagged by the team's code review)

1. **Annexure-4B config screen has no entry point** — cannot be opened from the app.
2. **Performance bill `New Bill` may always show `Cleaning rate not configured`** when billing is set
   up via weightage (which stores no default rate).
3. **Dead/unreachable screens** (don't waste time writing test cases for them): both `AreaConfigScreen`
   BOQ screens, `ExecutionPlanListScreen`, station-cleaning `cs_field_execution_screen`.
4. **"By Frequency" task-generation mode is non-functional** (only "occurrences" mode works).
5. If Daily Billing's area table says **`No active rate or weightage configured — values are zero`**
   while you *did* configure weightage → that's a bug.

---

# 11. How to report a problem

Record for every result:

1. **Role you logged in as** (e.g., Contractor Admin)
2. **Exact steps** — "1. Hub → 2. Daily Billing → 3. picked date → 4. tapped Generate → …"
3. **Expected vs actual** behaviour
4. **Screenshot / screen recording** + exact error text
5. **Phone model & Android version**, and the time it happened

> Format: `BUG | Role=CA | Screen=Daily Billing | Step=Generate | Expected=bill created | Actual="Cleaning rate not configured" | Photo attached`

---

# 12. Final checklist

- [ ] Every role logs in; each sees only its own menus.
- [ ] Hub tiles hide correctly (Daily Billing for CM, Area Rates for CA).
- [ ] Area create/edit/delete works; counts update.
- [ ] Generate Task → supervisor actually receives tasks.
- [ ] Shift Summary submit → railway approve → counts appear in Daily Billing.
- [ ] Weightage must total exactly 100% (both block messages tested).
- [ ] Daily bill generate → re-generate says `Existing bill reused.` (no duplicates).
- [ ] Performance bill walks DRAFT → LOCKED → payment; audit log records each step.
- [ ] Config changes (GST, penalty) actually change the next bill.
- [ ] PDFs download; reports export; feedback feeds the 30% component.
- [ ] No crash, white screen, or "Server error" during normal use.

If anything in this guide doesn't match what's on your screen, **note it — that itself is a bug.**