import { describe, it, expect, vi, beforeEach } from 'vitest';

/* ==========================================================================
   Contractor-supervisor PERSISTENT face baseline (station-cleaning attendance):
   - The FIRST attendance photo ever is saved as the person's permanent
     identity reference on the users doc.
   - Every later attendance with the same credential must match that photo;
     a different person is rejected at START (and mid/end compare against the
     baseline too).
   ========================================================================== */

const state = vi.hoisted(() => ({
  users: {},
  cleaningTasks: [],
  stationRuns: {},
}));

const todayIST = () => new Date(Date.now() + 5.5 * 60 * 60 * 1000).toISOString().slice(0, 10);

vi.mock('../src/database/index.js', () => {
  function makeRef(name, id) {
    return {
      get: async () => {
        const d = (state[name] || {})[id];
        return { exists: !!d, id, data: () => d || {} };
      },
      set: async (val) => { state[name] = state[name] || {}; state[name][id] = { ...val }; },
      update: async (val) => {
        if (!(state[name] || {})[id]) throw new Error('doc does not exist (simulating Firestore update-on-missing)');
        state[name][id] = { ...state[name][id], ...val };
      },
    };
  }
  function makeQuery(name) {
    const conds = [];
    const chain = {
      where: (k, op, v) => { conds.push({ k, op, v }); return chain; },
      limit: (n) => { chain._limit = n; return chain; },
      get: async () => {
        let docs = Object.keys(state[name] || {}).map((id) => ({ id, exists: true, data: () => state[name][id] }));
        for (const { k, op, v } of conds) {
          docs = docs.filter((d) => (op === '==' ? d.data()[k] === v : true));
        }
        if (chain._limit) docs = docs.slice(0, chain._limit);
        return { empty: docs.length === 0, forEach: (cb) => docs.forEach(cb) };
      },
    };
    return chain;
  }
  return {
    db: {
      collection: (name) => ({
        doc: (id) => makeRef(name, id),
        where: (k, op, v) => makeQuery(name).where(k, op, v),
      }),
    },
    admin: {},
  };
});

vi.mock('../src/services/rekognitionService.js', () => ({
  verifyFacePresent: vi.fn(async () => ({ matched: true })),
  compareFaces: vi.fn(async () => ({ matched: true, similarity: 97, reason: 'Face matched successfully.' })),
}));

const reko = await import('../src/services/rekognitionService.js');
const { stationCleaningAttendanceService } = await import('../src/services/stationCleaningAttendanceService.js');

const contractor = () => ({ uid: 'w1', fullName: 'Contractor Sup', userType: 'contractor', role: 'CONTRACTOR_SUPERVISOR' });

function seedUsers(user) {
  state.users[user.uid] = { ...user };
  return user;
}

function seedTask(status, count = 1) {
  for (let i = 0; i < count; i++) {
    state.cleaningTasks.push({ date: todayIST(), status, shift: 'morning', supervisorId: 'w1' });
  }
}

const attend = (body, user) => stationCleaningAttendanceService.markAttendance(
  { uid: user.uid, fullName: user.fullName, userType: user.userType, role: user.role },
  { runInstanceId: 'r1', stationId: 's1', deviceTimestamp: new Date().toISOString(), ...body }
);

beforeEach(() => {
  state.users = {};
  state['station_cleaning_attendance'] = {};
  state.cleaningTasks = [];
  state.stationRuns = {};
  reko.verifyFacePresent.mockClear();
  reko.compareFaces.mockClear();
  reko.verifyFacePresent.mockResolvedValue({ matched: true });
  reko.compareFaces.mockResolvedValue({ matched: true, similarity: 97, reason: 'Face matched successfully.' });
});

describe('Persistent contractor-supervisor face baseline', () => {
  it('first-ever START saves the photo as the permanent reference', async () => {
    seedUsers(contractor());
    seedTask('completed');
    await attend({ attendanceType: 'start', imageUrl: 'first_photo.jpg' }, contractor());
    expect(reko.verifyFacePresent).toHaveBeenCalledWith('first_photo.jpg');
    expect(reko.compareFaces).not.toHaveBeenCalled();
    expect(state.users['w1'].attendanceFaceReferenceUrl).toBe('first_photo.jpg');
    expect(state.users['w1'].attendanceFaceReferenceAt).toBeTruthy();
    const doc = Object.values(state['station_cleaning_attendance'])[0];
    expect(doc.startAttendance.photoUrl).toBe('first_photo.jpg');
    expect(doc.identityVerification.status).toBe('BASELINED_FIRST_ATTENDANCE');
  });

  it('same credential, DIFFERENT face at START is rejected', async () => {
    seedUsers({ ...contractor(), attendanceFaceReferenceUrl: 'first_photo.jpg' });
    seedTask('completed');
    reko.compareFaces.mockResolvedValue({ matched: false, similarity: 12, reason: 'Face structure does not match the baseline profile selfie.' });
    await expect(attend({ attendanceType: 'start', imageUrl: 'intruder.jpg' }, contractor())).rejects.toThrow(/different person/);
    expect(reko.compareFaces).toHaveBeenCalledWith('first_photo.jpg', 'intruder.jpg');
    // mismatch is audited on the users doc
    expect(state.users['w1'].attendanceFaceMismatchCount).toBe(1);
    expect(state.users['w1'].attendanceFaceMismatchReason).toContain('Face structure does not match');
    // no attendance doc was created
    expect(Object.values(state['station_cleaning_attendance'])).toHaveLength(0);
  });

  it('same credential, SAME face on later attendance is allowed and compared to the baseline', async () => {
    seedUsers({ ...contractor(), attendanceFaceReferenceUrl: 'first_photo.jpg' });
    seedTask('completed');
    await attend({ attendanceType: 'start', imageUrl: 'same_person.jpg' }, contractor());
    expect(reko.compareFaces).toHaveBeenCalledWith('first_photo.jpg', 'same_person.jpg');
    const doc = Object.values(state['station_cleaning_attendance'])[0];
    expect(doc.identityVerification.status).toBe('VERIFIED');
    expect(doc.faceReferenceUrl).toBe('first_photo.jpg');
  });

  it('mid attendance also compares against the persistent baseline', async () => {
    seedUsers({ ...contractor(), attendanceFaceReferenceUrl: 'first_photo.jpg' });
    seedTask('completed');
    seedTask('pending');
    await attend({ attendanceType: 'start', imageUrl: 'same_person_start.jpg' }, contractor());
    await attend({ attendanceType: 'mid', imageUrl: 'same_person_mid.jpg' }, contractor());
    expect(reko.compareFaces).toHaveBeenCalledWith('first_photo.jpg', 'same_person_mid.jpg');
    const doc = Object.values(state['station_cleaning_attendance'])[0];
    expect(doc.isMidMarked).toBe(true);
  });

  it('non-contractor railway supervisor does NOT get a persistent baseline', async () => {
    seedUsers({ uid: 'rw1', fullName: 'Railway Sup', userType: 'railway', role: 'RAILWAY_SUPERVISOR' });
    const result = await attend({ attendanceType: 'start', imageUrl: 's.jpg' }, { uid: 'rw1', fullName: 'Railway Sup', userType: 'railway', role: 'RAILWAY_SUPERVISOR' });
    expect(result.success).toBe(true);
    expect(state.users['rw1'].attendanceFaceReferenceUrl).toBeUndefined();
    expect(reko.compareFaces).not.toHaveBeenCalled();
  });
});

describe('Mid/end attendance counts only ACTIONABLE tasks (missed windows excluded)', () => {
  it('mid passes on half the actionable tasks even when other windows already lapsed', async () => {
    vi.useFakeTimers();
    // Fixed clock: 2024-01-15 14:30 IST
    vi.setSystemTime(new Date('2024-01-15T09:00:00Z'));
    try {
      seedUsers(contractor());
      // 2 MISSED tasks: 1-hour start window (13:00+1h = 14:00) has elapsed.
      state.cleaningTasks.push(
        { date: '2024-01-15', status: 'pending', shift: 'morning', supervisorId: 'w1', scheduledTime: '13:00' },
        { date: '2024-01-15', status: 'pending', shift: 'morning', supervisorId: 'w1', scheduledTime: '13:30' },
      );
      // 1 ACTIONABLE completed task: window (14:00+1h = 15:00) still open.
      state.cleaningTasks.push({ date: '2024-01-15', status: 'completed', shift: 'morning', supervisorId: 'w1', scheduledTime: '14:00' });

      await attend({ attendanceType: 'start', imageUrl: 'start.jpg' }, contractor());
      // Actionable denominator is 1 (the 2 missed tasks never count), so 1
      // completed >= ceil(1/2) → mid is allowed.
      await attend({ attendanceType: 'mid', imageUrl: 'mid.jpg' }, contractor());
      const doc = Object.values(state['station_cleaning_attendance'])[0];
      expect(doc.isMidMarked).toBe(true);
    } finally {
      vi.useRealTimers();
    }
  });

  it('end still requires all ACTIONABLE tasks, ignoring lapsed-window tasks', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2024-01-15T09:00:00Z'));
    try {
      seedUsers(contractor());
      state.cleaningTasks.push(
        { date: '2024-01-15', status: 'pending', shift: 'morning', supervisorId: 'w1', scheduledTime: '13:00' },
        { date: '2024-01-15', status: 'completed', shift: 'morning', supervisorId: 'w1', scheduledTime: '14:00' },
      );
      state['stationShiftSummaries'] = {
        s1: { supervisorId: 'w1', date: '2024-01-15', status: 'submitted' },
      };
      await attend({ attendanceType: 'start', imageUrl: 'start.jpg' }, contractor());
      await attend({ attendanceType: 'mid', imageUrl: 'mid.jpg' }, contractor());
      await attend({ attendanceType: 'end', imageUrl: 'end.jpg' }, contractor());
      const doc = Object.values(state['station_cleaning_attendance'])[0];
      expect(doc.isEndMarked).toBe(true);
    } finally {
      vi.useRealTimers();
    }
  });
});