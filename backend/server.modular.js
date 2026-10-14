import { db, admin } from './src/database/index.js';
import { validateEnvironment } from './src/config/env.js';
import app from './src/app.js';
import logger from './src/logger/index.js';
import config from './src/config/index.js';
import { stationCleaningService } from './src/services/stationCleaningService.js';

validateEnvironment();

db.initialize();

logger.info('Server', `Environment: ${config.nodeEnv}`);

async function seedDefaultAdmin() {
  try {
    const adminEmail = 'admin@gmail.com';
    const snapshot = await db.collection('users').where('email', '==', adminEmail).limit(1).get();
    if (snapshot.empty) {
      logger.info('Seed', 'Admin user not found. Creating default admin...');
      await db.collection('users').doc('admin-uid').set({
        uid: 'admin-uid',
        fullName: 'Admin',
        email: adminEmail,
        password: '123456',
        mobile: '9999999990',
        role: 'SUPER_ADMIN',
        userType: 'railway',
        zone: 'NR',
        division: 'DELHI',
        status: 'APPROVED',
        createdAt: new Date().toISOString()
      });
      try {
        await admin.auth().createUser({
          uid: 'admin-uid',
          email: adminEmail,
          password: '123456',
          displayName: 'Admin'
        });
      } catch (authErr) {
        logger.warn('Seed', `Firebase Auth user creation skipped: ${authErr.message}`);
      }
      logger.info('Seed', `Default admin created: ${adminEmail}`);
    } else {
      logger.info('Seed', 'Admin user already exists, skipping seed.');
    }
  } catch (err) {
    logger.error('Seed', `Seed failed: ${err.message}`);
  }
}

// On boot, pre-generate upcoming station-cleaning tasks for all active schedules
// so a missed midnight cron / Render restart never leaves a day empty. Uses
// generateForDays>1 to create today AND upcoming dates (no backfill of the past).
async function preGenerateStationCleaningTasks() {
  try {
    const today = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' });
    const dayName = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][new Date(`${today}T12:00:00Z`).getUTCDay()];
    try {
      await stationCleaningService.ensureShiftSchedulesForAllStations();
    } catch (scheduleErr) {
      logger.error('Boot', `Shift-schedule reconcile failed: ${scheduleErr.message}`);
    }
    const scheduleSnap = await db.collection('stationSchedules')
      .where('status', '==', 'active').get();
    let totalSchedules = 0;
    let totalTasks = 0;
    for (const doc of scheduleSnap.docs) {
      const s = doc.data();
      if (s.daysOfWeek && Array.isArray(s.daysOfWeek) && s.daysOfWeek.length > 0) {
        if (!s.daysOfWeek.includes(dayName)) continue;
      }
      try {
        const result = await stationCleaningService.generateTasksFromSchedule({
          scheduleId: doc.id,
          date: today,
          generateForDays: 3,
        });
        totalSchedules++;
        totalTasks += result.count || 0;
      } catch (err) {
        logger.error('Boot', `StationSchedule pre-gen error ${doc.id}: ${err.message}`);
      }
    }
    if (totalSchedules > 0) {
      logger.info('Boot', `Pre-generated ${totalTasks} tasks across ${totalSchedules} schedule(s) for upcoming days`);
    }
  } catch (err) {
    logger.error('Boot', `Pre-generation failed: ${err.message}`);
  }
}

import './src/cron.js';
await seedDefaultAdmin();
if (process.env.DISABLE_BACKGROUND_JOBS !== 'true') {
  await preGenerateStationCleaningTasks();
} else {
  logger.warn('Boot', 'Background jobs disabled by DISABLE_BACKGROUND_JOBS');
}

app.listen(config.port, () => {
  logger.info('Server', `Modular Swachh Railways server running on http://localhost:${config.port}`);
});
