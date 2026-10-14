import cron from 'node-cron';
import { Resend } from 'resend';
import ExcelJS from 'exceljs';
import { db, admin } from './database/index.js';
import * as evidence from '../evidence_manager.js';
import logger from './logger/index.js';
import { taskManagementService } from './services/taskManagementService.js';
import { stationCleaningService } from './services/stationCleaningService.js';
import { stationBillingService } from './services/stationBillingService.js';
import { autoEmailService } from './services/autoEmailService.js';

const CRON_TZ = 'Asia/Kolkata';
const schedule = (...args) => {
  if (process.env.DISABLE_CRON === 'true') return null;
  return cron.schedule(...args);
};

// Business date (YYYY-MM-DD) in IST, independent of the host server timezone.
// Offsets of -1/0/+1 days can be supplied for backdating or look-ahead.
function getISTDate(offset = 0) {
  const shifted = new Date(Date.now() + offset * 86400000);
  return shifted.toLocaleDateString('en-CA', { timeZone: CRON_TZ });
}

// Weekday name (Mon..Sun) matching the IST business date for a given ISO date.
function getISTDayName(dateStr) {
  return ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][new Date(`${dateStr}T12:00:00Z`).getUTCDay()];
}

let resend = null;
try {
  if (process.env.RESEND_API_KEY) resend = new Resend(process.env.RESEND_API_KEY);
} catch (e) {
  logger.warn('Resend not configured — email features disabled');
}

async function generateCoachExcelBuffer(data) {
  const workbook = new ExcelJS.Workbook();
  const sheet = workbook.addWorksheet('Coach Cleaning Report');
  const headerStyle = {
    font: { bold: true, color: { argb: 'FFFFFF' } },
    fill: { type: 'pattern', pattern: 'solid', fgColor: { argb: '1F4E78' } },
    alignment: { vertical: 'middle', horizontal: 'center', wrapText: true },
    border: { outline: { style: 'thin' } }
  };
  sheet.columns = [
    { header: 'Date', key: 'date', width: 15 },
    { header: 'Train Details', key: 'train', width: 30 },
    { header: 'Work Type', key: 'workType', width: 20 },
    { header: 'ACWP Status', key: 'acwp', width: 15 },
    { header: 'Total Penalty', key: 'penalty', width: 15 },
    { header: 'Internal (A)', key: 'intA', width: 12 },
    { header: 'Intensive (NA)', key: 'intNA', width: 12 },
    { header: 'Status', key: 'status', width: 15 }
  ];
  sheet.getRow(1).eachCell((cell) => { cell.style = headerStyle; });
  data.forEach(item => {
    sheet.addRow({
      date: item.formDateTime ? item.formDateTime.split('T')[0] : 'N/A',
      train: `${item.submittedTo?.trainNumber || ''} - ${item.submittedTo?.trainName || ''}`,
      workType: item.ratingDetails?.workType || 'N/A',
      acwp: item.ratingDetails?.acwpStatus || 'N/A',
      penalty: item.summary?.totalPenalty || 0,
      intA: item.summary?.internal?.A || 0,
      intNA: item.summary?.intensive?.NA || 0,
      status: item.status || 'LOCKED'
    });
  });
  return await workbook.xlsx.writeBuffer();
}

async function generatePremisesExcelBuffer(data) {
  const workbook = new ExcelJS.Workbook();
  const sheet = workbook.addWorksheet('Premises Report');
  const headerStyle = {
    font: { bold: true, color: { argb: 'FFFFFF' } },
    fill: { type: 'pattern', pattern: 'solid', fgColor: { argb: '4472C4' } },
    alignment: { vertical: 'middle', horizontal: 'center' }
  };
  sheet.columns = [
    { header: 'Date', key: 'date', width: 15 },
    { header: 'Location', key: 'location', width: 20 },
    { header: 'Area (Sq Mtrs)', key: 'area', width: 15 },
    { header: 'Housekeeping Score', key: 'hkScore', width: 20 },
    { header: 'Pit-Line Score', key: 'pitScore', width: 15 },
    { header: 'Garbage Score', key: 'gbScore', width: 15 },
    { header: 'Overall Score', key: 'overall', width: 15 },
    { header: 'Status', key: 'status', width: 15 }
  ];
  sheet.getRow(1).eachCell((cell) => { cell.style = headerStyle; });
  data.forEach(item => {
    sheet.addRow({
      date: item.formDateTime ? item.formDateTime.split('T')[0] : 'N/A',
      location: item.location || 'N/A',
      area: item.area || 0,
      hkScore: item.summary?.housekeepingScore || '0',
      pitScore: item.summary?.pitLineScore || '0',
      gbScore: item.summary?.garbageDisposalScore || '0',
      overall: item.summary?.overallScore || '0',
      status: item.status || 'N/A'
    });
  });
  return await workbook.xlsx.writeBuffer();
}

async function sendEmailWithAttachments(email, division, coachBuffer, premisesBuffer, stats = { coachCount: 0, premisesCount: 0 }) {
  const todayDate = new Date().toISOString().split('T')[0];
  try {
    const hasData = stats.coachCount > 0 || stats.premisesCount > 0;
    if (!resend) { logger.warn('Resend not configured, skipping email'); return; }
    await resend.emails.send({
      from: 'Swachh Railways <reports@swachhrailways.com>',
      to: [email],
      subject: `Daily Cleaning Report | ${division} | ${todayDate}`,
      html: `
        <div style="font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; border: 1px solid #eee; padding: 20px; border-radius: 8px;">
          <h2 style="color: #1F4E78; border-bottom: 2px solid #1F4E78; padding-bottom: 10px;">Daily Summary Report</h2>
          <p>Dear Admin,</p>
          <p>Please find the automated cleaning performance reports for the <b>${division}</b> division.</p>
          <div style="background-color: #f9f9f9; padding: 15px; border-left: 4px solid #1F4E78; margin: 20px 0;">
            <p style="margin: 0; font-weight: bold;">Summary for ${todayDate}:</p>
            <ul style="margin: 10px 0 0 0;">
              <li>Coach Forms: ${stats.coachCount}</li>
              <li>Premises Forms: ${stats.premisesCount}</li>
            </ul>
          </div>
          ${hasData ? `
            <div style="background-color: #f9f9f9; padding: 15px; border-left: 4px solid #1F4E78; margin: 20px 0;">
              <p style="margin: 0; font-weight: bold;">Attached Files:</p>
              <ul style="margin: 10px 0 0 0;">
                ${stats.coachCount > 0 ? '<li>Coach Cleaning Detailed Report (.xlsx)</li>' : ''}
                ${stats.premisesCount > 0 ? '<li>Premises Cleaning Detailed Report (.xlsx)</li>' : ''}
              </ul>
            </div>
          ` : `
            <div style="background-color: #fff3cd; padding: 15px; border-left: 4px solid #ffc107; margin: 20px 0;">
              <p style="margin: 0; color: #856404;">
                ⚠️ No forms were submitted today. Please check if forms are being created properly.
              </p>
            </div>
          `}
          <p style="margin-top: 30px; font-size: 0.85em; color: #888; border-top: 1px solid #eee; padding-top: 15px;">
            <i>This is an automated message generated by the Swachh Railways System. Please do not reply to this email.</i>
          </p>
          <p style="font-weight: bold; color: #1F4E78; margin-bottom: 0;">Swachh Railways Management System</p>
          <p style="font-size: 0.8em; color: #666; margin-top: 4px;">Powered by Backend Automation</p>
        </div>
      `,
      attachments: [
        ...(coachBuffer ? [{ filename: `Coach_Report_${division}_${todayDate}.xlsx`, content: coachBuffer.toString('base64') }] : []),
        ...(premisesBuffer ? [{ filename: `Premises_Report_${division}_${todayDate}.xlsx`, content: premisesBuffer.toString('base64') }] : [])
      ],
    });
    logger.info('Cron', `Report successfully emailed to Admin: ${email} (${division})`);
  } catch (error) {
    logger.error('Cron', `Error sending email to ${email}:`, error);
  }
}

async function getDailyReportData() {
  const today = new Date();
  const startOfDay = new Date(today.setHours(0, 0, 0, 0));
  const endOfDay = new Date(today.setHours(23, 59, 59, 999));
  try {
    const adminSnapshot = await admin.firestore().collection('users').where('role', '==', 'admin').get();
    if (adminSnapshot.empty) { logger.info('Cron', "No admins found in the database."); return; }
    for (const doc of adminSnapshot.docs) {
      const adminInfo = doc.data();
      const adminDivision = adminInfo.division;
      const adminEmail = adminInfo.email;
      if (!adminDivision) { logger.info('Cron', `Skipping admin ${adminEmail} because division is not set.`); continue; }
      const coachSnapshot = await admin.firestore().collection('coachForms').where('submittedByDivision', '==', adminDivision).where('createdAt', '>=', startOfDay).where('createdAt', '<=', endOfDay).get();
      const coachData = coachSnapshot.docs.map(d => d.data());
      const premisesSnapshot = await admin.firestore().collection('premisesForms').where('submittedByDivision', '==', adminDivision).where('createdAt', '>=', startOfDay).where('createdAt', '<=', endOfDay).get();
      const premisesData = premisesSnapshot.docs.map(d => d.data());
      const coachBuffer = coachData.length > 0 ? await generateCoachExcelBuffer(coachData) : null;
      const premisesBuffer = premisesData.length > 0 ? await generatePremisesExcelBuffer(premisesData) : null;
      await sendEmailWithAttachments(adminEmail, adminDivision, coachBuffer, premisesBuffer, { coachCount: coachData.length, premisesCount: premisesData.length });
    }
  } catch (error) { logger.error('Cron', "Error in Automated Reporting Loop:", error); }
}

const checkAndApprove = async (collectionName) => {
  try {
    const thirtyMinAgo = new Date(Date.now() - 30 * 60 * 1000);
    const snapshot = await db.collection(collectionName).where('status', '==', 'SCORED').get();
    if (snapshot.empty) return;
    const batch = db.batch();
    let approvedCount = 0;
    snapshot.forEach(doc => {
      const data = doc.data();
      let shouldApprove = false;
      if (data.ratedAt) {
        let ratedDate;
        if (typeof data.ratedAt.toDate === 'function') { ratedDate = data.ratedAt.toDate(); }
        else { ratedDate = new Date(data.ratedAt); }
        if (!isNaN(ratedDate.getTime()) && ratedDate < thirtyMinAgo) { shouldApprove = true; }
      }
      if (shouldApprove) {
        batch.update(doc.ref, { status: 'AUTO-APPROVED', completedAt: admin.firestore.FieldValue.serverTimestamp(), autoApprovedAt: admin.firestore.FieldValue.serverTimestamp() });
        approvedCount++;
      }
    });
    if (approvedCount > 0) { await batch.commit(); logger.info('Cron', `[Cron] Auto-approved ${approvedCount} forms in ${collectionName}`); }
  } catch (e) {
    if (e.code !== 'FAILED_PRECONDITION') logger.error('Cron', `[Cron Error] Form Approval:`, e.message);
  }
};

const checkContractExpiry = async () => {
  try {
    logger.info('Cron', ' Checking for expired contracts...');
    const now = new Date();
    const snapshot = await db.collection('contracts').where('status', '==', 'Active').get();
    if (snapshot.empty) { logger.info('Cron', ' No active contracts found to check.'); return; }
    const batch = db.batch();
    let expiredCount = 0;
    snapshot.forEach(doc => {
      const data = doc.data();
      if (data.endDate) {
        const endDate = new Date(data.endDate);
        endDate.setHours(23, 59, 59, 999);
        if (now > endDate) {
          batch.update(db.collection('contracts').doc(doc.id), { status: 'Expired', updatedAt: new Date().toISOString() });
          expiredCount++;
        }
      }
    });
    if (expiredCount > 0) { await batch.commit(); logger.info('Cron', ` Successfully Expired ${expiredCount} contracts.`); }
    else { logger.info('Cron', 'All active contracts are still valid.'); }
  } catch (e) { logger.error('Cron', ' [Cron Error] Contract Expiry:', e.message); }
};

// Shared pipeline: reconcile shift schedules, then generate station-cleaning
// tasks from every active schedule for the given IST business date. Idempotent,
// so extra runs only fill in missing tasks (see generateTasksFromSchedule).
async function runStationCleaningGeneration(generateForDays = 3) {
  try {
    await stationCleaningService.ensureShiftSchedulesForAllStations();
  } catch (reconcileErr) {
    logger.error('Cron', ` [ShiftSchedule] Reconcile failed: ${reconcileErr.message}`);
  }

  const today = getISTDate();
  const dayName = getISTDayName(today);
  const scheduleSnap = await db.collection('stationSchedules')
    .where('status', '==', 'active').get();
  let totalSchedules = 0;
  let totalTasks = 0;

  for (const doc of scheduleSnap.docs) {
    const s = doc.data();
    if (s.daysOfWeek && Array.isArray(s.daysOfWeek) && s.daysOfWeek.length > 0) {
      if (!s.daysOfWeek.includes(dayName)) continue;
    }
    if (s.effectiveFrom && s.effectiveTo) {
      const from = new Date(s.effectiveFrom);
      const to = new Date(s.effectiveTo);
      const now = new Date();
      if (now < from || now > to) continue;
    }

    try {
      const result = await stationCleaningService.generateTasksFromSchedule({
        scheduleId: doc.id,
        date: today,
        generateForDays,
      });
      totalSchedules++;
      totalTasks += result.count || 0;
    } catch (err) {
      logger.error('Cron', ` [StationSchedule] Error processing ${doc.id}: ${err.message}`);
    }
  }

  if (totalSchedules > 0) {
    logger.info('Cron', ` [StationSchedule] Generated ${totalTasks} tasks across ${totalSchedules} schedule(s)`);
  }
  return { totalSchedules, totalTasks };
}

// ─── Daily midnight: Check contract expiry & generate daily cleaning tasks ───
schedule('0 0 * * *', async () => {
  logger.info('Cron', ' Running Midnight Cron Job...');
  try {
    await checkContractExpiry();
    const today = getISTDate();

    try {
      const legacyResult = await taskManagementService.generateFrequencyBasedTasks(today);
      logger.info('Cron', ` [TaskGen-Legacy] ${legacyResult.message}`);
    } catch (legacyErr) {
      logger.error('Cron', ` [TaskGen-Legacy] FAILED: ${legacyErr.message}`);
    }

    await runStationCleaningGeneration(3);
  } catch (e) { logger.error('Cron', ' [Cron Error] Midnight tasks:', e.message); }
}, { timezone: CRON_TZ });

// ─── Daily 6 AM & 6 PM: Regenerate tasks for current day if needed ───
schedule('0 6,18 * * *', async () => {
  try {
    const today = getISTDate();

    try {
      const result = await taskManagementService.generateFrequencyBasedTasks(today);
      logger.info('Cron', ` [TaskGen-Refresh] ${result.message}`);
    } catch (e) {
      logger.error('Cron', ` [TaskGen-Refresh] Legacy generation failed: ${e.message}`);
    }

    await runStationCleaningGeneration(1);
  } catch (e) { logger.error('Cron', ' [Cron Error] Task refresh:', e.message); }
}, { timezone: CRON_TZ });

// ─── Daily 23:55: Automated daily reports ───
schedule('55 23 * * *', async () => {
  logger.info('Cron', '--- Starting Automated Daily Reports ---');
  try {
    await getDailyReportData();
    logger.info('Cron', '--- Finished Automated Daily Reports Successfully ---');
  } catch (error) { logger.error('Cron', '--- Automated Daily Reports Failed ---', error); }
}); 

// ─── Monthly (1st at 7 AM IST): Generate previous month's billing packs & dispatch Billing Support Report ───
schedule('0 7 1 * *', async () => {
  logger.info('Cron', '--- Starting Monthly Billing Report Cron ---');
  const now = new Date();
  const prev = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1));
  const year = prev.getUTCFullYear();
  const month = prev.getUTCMonth() + 1;
  const sysUser = { uid: 'system', fullName: 'System', role: 'SUPER_ADMIN' };

  try {
    const gen = await stationBillingService.generateMonthlyBillingPacks(month, year, sysUser);
    logger.info('Cron', ` [MonthlyBilling-Generate] Generated ${gen.generated} billing pack(s) for ${month}/${year}`);
  } catch (e) {
    logger.error('Cron', ` [MonthlyBilling-Generate] FAILED: ${e.message}`);
  }

  try {
    const stationsSnap = await db.collection('stations').where('active', '==', true).limit(200).get();
    let dispatched = 0;
    for (const doc of stationsSnap.docs) {
      try {
        const res = await autoEmailService.dispatchMonthlyReport('monthly_billing', doc.id, month, year);
        if (res.sent > 0) dispatched += res.sent;
      } catch (e) {
        logger.error('Cron', ` [MonthlyBilling-Email] Station ${doc.id} FAILED: ${e.message}`);
      }
    }
    logger.info('Cron', ` [MonthlyBilling-Email] Dispatched Billing Support Report to ${dispatched} recipient(s)`);
  } catch (e) {
    logger.error('Cron', ` [MonthlyBilling-Email] Fetching stations FAILED: ${e.message}`);
  }
  logger.info('Cron', '--- Finished Monthly Billing Report Cron ---');
}, { timezone: CRON_TZ });

// ─── Daily 2 AM: Evidence archive ───
schedule('0 2 * * *', async () => {
  logger.info('Cron', '--- Running Evidence Archive Cron ---');
  try {
    const result = await evidence.archiveOldRecords(db, db.getBucket(), 7);
    logger.info('Cron', `Archived ${result.archived} records older than ${result.daysOld} days`);
    const longResult = await evidence.moveToLongTerm(db, 30);
    logger.info('Cron', `Moved ${longResult.moved} records to long-term storage`);
  } catch (error) { logger.error('Cron', 'Evidence archive cron failed:', error); }
});

// ─── Every 10 minutes: Check forms and contracts as fallback ───
// node-cron v4 SKIPS (never re-runs) any execution whose tick was delayed while
// the event loop was busy ("missed execution at ..."). On busy hosts this has
// been observed to skip the midnight/6AM/6PM jobs entirely, so also run the
// same station-cleaning generation here. It is idempotent (generateTasksFromSchedule
// reconciles to the existing task set), so extra runs are safe and cheap.
const stationCleaningFallbackTimer = setInterval(() => {
  checkAndApprove('coachForms');
  checkAndApprove('premisesForms');
  checkAndApprove('ctsForms');
  checkContractExpiry();
  runStationCleaningGeneration(1).catch(e => {
    logger.error('Cron', ` [StationSchedule-Fallback] FAILED: ${e.message}`);
  });
}, 600000);
if (process.env.DISABLE_CRON === 'true') {
  clearInterval(stationCleaningFallbackTimer);
} else {
  stationCleaningFallbackTimer.unref?.();
}

// ─── Every 15 minutes: Update task statuses based on time ───
schedule('*/15 * * * *', async () => {
  try {
    const now = new Date();
    const today = now.toISOString().split('T')[0];
    const activeRunsSnap = await db.collection('RunInstance').where('status', '==', 'Active').select('runInstanceId').get();
    const activeRunIds = new Set();
    activeRunsSnap.forEach(doc => activeRunIds.add(doc.id));
    const headerSnapshot = await db.collection('task_headers').where('status', 'in', ['PLANNED']).where('scheduledDate', '==', today).get();
    const headerBatch = db.batch();
    let updateCount = 0;
    headerSnapshot.forEach(doc => {
      const data = doc.data();
      if (!activeRunIds.has(data.runInstanceId)) return;
      const [h, m] = (data.scheduledTime || '00:00').split(':').map(Number);
      const scheduledDate = new Date(`${today}T${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:00`);
      if (now > scheduledDate) {
        headerBatch.update(doc.ref, { status: 'OVERDUE', updatedAt: now.toISOString() });
        updateCount++;
      }
    });
    if (updateCount > 0) { await headerBatch.commit(); logger.info('Cron', `[Cron] Updated ${updateCount} task headers to OVERDUE`); }
    const complaintSnapshot = await db.collection('obhs_complaints').where('status', '==', 'OPEN').get();
    const complaintBatch = db.batch();
    let escalatedCount = 0;
    complaintSnapshot.forEach(doc => {
      const data = doc.data();
      const createdAt = new Date(data.createdAt);
      const elapsedMinutes = (now - createdAt) / (1000 * 60);
      const slaMap = { 'Cleaning': 30, 'Garbage': 20, 'Water': 30, 'Petty Repair': 60, 'Toilet': 30, 'Electrical': 60 };
      const slaMinutes = slaMap[data.category] || 60;
      if (elapsedMinutes > slaMinutes && !data.slaEscalated) {
        complaintBatch.update(doc.ref, { slaEscalated: true, slaEscalatedAt: now.toISOString(), slaBreach: true, escalationLevel: 1, status: 'ESCALATED', updatedAt: now.toISOString() });
        escalatedCount++;
      }
    });
    if (escalatedCount > 0) { await complaintBatch.commit(); logger.info('Cron', `[Cron] Auto-escalated ${escalatedCount} SLA-breached complaints`); }
  } catch (error) { logger.error('Cron', '[Cron] Task status update error:', error); }
});

// ─── Every 5 minutes: Check task status transitions near scheduled times ───
schedule('*/5 * * * *', async () => {
  try {
    const now = new Date();
    const nowMinutes = now.getHours() * 60 + now.getMinutes();
    const activeRunsSnap = await db.collection('RunInstance').where('status', '==', 'Active').select('runInstanceId').get();
    const activeRunIds = new Set();
    activeRunsSnap.forEach(doc => activeRunIds.add(doc.id));
    const detailSnapshot = await db.collection('task_details').where('status', '==', 'PLANNED').get();
    const detailBatch = db.batch();
    let openCount = 0, dueSoonCount = 0, skippedCount = 0;
    detailSnapshot.forEach(doc => {
      const data = doc.data();
      if (!activeRunIds.has(data.runInstanceId)) { skippedCount++; return; }
      const [h, m] = (data.scheduledTime || '00:00').split(':').map(Number);
      const taskMinutes = h * 60 + m;
      const diff = taskMinutes - nowMinutes;
      if (diff <= 0 && diff > -120) {
        detailBatch.update(doc.ref, { status: 'OPEN', updatedAt: now.toISOString() });
        openCount++;
      } else if (diff > 0 && diff <= 15) {
        detailBatch.update(doc.ref, { status: 'DUE_SOON', updatedAt: now.toISOString() });
        dueSoonCount++;
      }
    });
    if (openCount + dueSoonCount > 0) { await detailBatch.commit(); logger.info('Cron', `[Cron] Task status updated: ${openCount} OPEN, ${dueSoonCount} DUE_SOON (${skippedCount} skipped - not active)`); }
  } catch (error) { logger.error('Cron', '[Cron] Task detail status error:', error); }
});

// ─── Every 5 minutes: Auto-escalate overdue tasks by time threshold ───
schedule('*/5 * * * *', async () => {
  try {
    const now = new Date();
    const overdueTasksSnap = await db.collection('task_details').where('status', '==', 'OVERDUE').get();
    if (overdueTasksSnap.empty) return;
    const escalationChain = [
      { minutes: 90, escalateTo: 'CM', label: 'CM Alert' },
      { minutes: 60, escalateTo: 'CA', label: 'CA Alert' },
      { minutes: 45, escalateTo: 'CTS', label: 'CTS Alert' },
      { minutes: 30, escalateTo: 'CS', label: 'CS Alert' }
    ];
    const batch = db.batch();
    let escalationCount = 0;
    for (const doc of overdueTasksSnap.docs) {
      const task = doc.data();
      const updatedAt = task.updatedAt ? new Date(task.updatedAt) : null;
      if (!updatedAt) continue;
      const elapsedMinutes = (now - updatedAt) / (1000 * 60);
      const lastEscalation = task.lastEscalationAt || 0;
      for (const level of escalationChain) {
        if (elapsedMinutes >= level.minutes && lastEscalation < level.minutes) {
          const escRef = db.collection('escalations').doc();
          batch.set(escRef, {
            escalationId: escRef.id, sourceEntity: 'task_detail', sourceId: task.detailId || doc.id,
            reason: `${level.label}: Task overdue for ${Math.round(elapsedMinutes)} minutes`,
            details: `${task.taskType} on Coach ${task.coachNo} overdue since ${updatedAt.toISOString()}`,
            escalatedBy: 'system', escalatedByName: 'System', escalatedByRole: 'system',
            escalatedToRole: level.escalateTo, status: 'OPEN', createdAt: now.toISOString(), updatedAt: now.toISOString()
          });
          batch.update(doc.ref, { lastEscalationAt: level.minutes, escalationLevel: level.label, updatedAt: now.toISOString() });
          escalationCount++;
          break;
        }
      }
    }
    if (escalationCount > 0) { await batch.commit(); logger.info('Cron', `[Cron] Auto-escalated ${escalationCount} overdue tasks`); }
  } catch (error) { logger.error('Cron', '[Cron] Escalation error:', error); }
});

// ─── Every minute: Auto-approve station-cleaning shift summaries not acted on
// (approved/rejected) by a railway approver within 1 hour of submission ───
schedule('*/1 * * * *', async () => {
  try {
    const result = await stationCleaningService.autoApproveExpiredShiftSummaries({ maxAgeMs: 3600000 });
    if (result.autoApprovedCount > 0) {
      logger.info('Cron', `[Cron] Auto-approved ${result.autoApprovedCount} shift summar${result.autoApprovedCount === 1 ? 'y' : 'ies'}`);
    }
  } catch (error) { logger.error('Cron', '[Cron] Shift summary auto-approve error:', error); }
});

logger.info('Cron', 'Cron jobs initialized');
