import { describe, it, expect, vi, beforeEach } from 'vitest';

/* ==========================================================================
   MCC (Mechanised Coach Cleaning) — Washing Plant / Depot module tests.
   Covers: depot creation, washing-run schedule + coach task generation,
   worker submit -> supervisor approve/reject, run rollup, attendance flow.
   ========================================================================== */

const state = vi.hoisted(() => ({
  mcc_depots: {},
  mcc_washing_runs: {},
  mcc_washing_tasks: {},
  mcc_attendance: {},
}));

vi.mock('../src/database/index.js', () => {
  let autoId = 0;
  function makeRef(name, id) {
    const refId = id || `auto_${++autoId}`;
    return {
      id: refId,
      get: async () => {
        const d = (state[name] || {})[refId];
        return { exists: !!d, id: refId, data: () => d || {} };
      },
      set: async (val) => { state[name] = state[name] || {}; state[name][refId] = { ...val }; },
      update: async (val) => {
        if (!(state[name] || {})[refId]) throw new Error('doc does not exist (simulating Firestore update-on-missing)');
        state[name][refId] = { ...state[name][refId], ...val };
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
          docs = docs.filter((d) => (op === '==' ? d.data()[k] === v : d.data()[k] === v));
        }
        if (chain._limit) docs = docs.slice(0, chain._limit);
        return { empty: docs.length === 0, size: docs.length, forEach: (cb) => docs.forEach(cb) };
      },
    };
    return chain;
  }
  return {
    db: {
      collection: (name) => ({
        doc: (id) => makeRef(name, id),
        where: (k, op, v) => makeQuery(name).where(k, op, v),
        limit: (n) => makeQuery(name).limit(n),
      }),
    },
    admin: {},
  };
});

const { mccService } = await import('../src/services/mccService.js');

const manager = () => ({ uid: 'm1', fullName: 'MCC Manager', role: 'CONTRACTOR_MASTER', entityId: 'e1' });
const worker = () => ({ uid: 'w1', fullName: 'Coach Washer' });

describe('MCC Depots', () => {
  beforeEach(() => {
    Object.keys(state).forEach(k => { state[k] = {}; });
  });

  it('creates a washing-plant depot', async () => {
    const result = await mccService.createDepot(manager(), {
      name: 'NDLS Washing Plant',
      stationId: 'st1',
      stationName: 'New Delhi',
      capacity: 12,
      machines: 3,
    });
    expect(result.success).toBe(true);
    expect(result.depotId).toBeTruthy();
    const depot = state.mcc_depots[result.depotId];
    expect(depot.name).toBe('NDLS Washing Plant');
    expect(depot.status).toBe('active');
  });

  it('rejects depot creation without a name', async () => {
    await expect(mccService.createDepot(manager(), { stationId: 'st1' })).rejects.toThrow(/Depot name/);
  });

  it('lists depots sorted newest first', async () => {
    await mccService.createDepot(manager(), { name: 'D1', stationId: 'st1' });
    const { depots } = await mccService.listDepots();
    expect(depots.length).toBe(1);
    expect(depots[0].name).toBe('D1');
  });
});

describe('MCC Washing Runs', () => {
  beforeEach(() => {
    Object.keys(state).forEach(k => { state[k] = {}; });
  });

  async function makeRun(trainNo = '12301') {
    await mccService.createDepot(manager(), { name: 'Plant A', stationId: 'st1' });
    const depotId = Object.keys(state.mcc_depots)[0];
    return mccService.createWashingRun(manager(), {
      depotId,
      trainNo,
      trainName: 'Rajdhani',
      coachNos: ['A1', 'B1'],
      assignedWorkers: [{ coachNo: 'A1', workerId: 'w1', workerName: 'Coach Washer' }],
    });
  }

  it('creates a run with per-coach tasks', async () => {
    const result = await makeRun();
    expect(result.success).toBe(true);
    expect(result.tasks.length).toBe(2);
    const run = state.mcc_washing_runs[result.runId];
    expect(run.status).toBe('SCHEDULED');
    expect(run.taskCount).toBe(2);
    expect(run.runNumber).toMatch(/^MCC-/);
  });

  it('starts a SCHEDULED run', async () => {
    const { runId } = await makeRun();
    const starter = await mccService.startWashingRun(manager(), runId);
    expect(starter.success).toBe(true);
    expect(state.mcc_washing_runs[runId].status).toBe('IN_PROGRESS');
  });

  it('rejects starting an already-started run', async () => {
    const { runId } = await makeRun();
    await mccService.startWashingRun(manager(), runId);
    await expect(mccService.startWashingRun(manager(), runId)).rejects.toThrow(/cannot be started/);
  });

  it('fetching a run returns its tasks sorted by coach', async () => {
    const { runId } = await makeRun();
    const { run, tasks } = await mccService.getWashingRun(runId);
    expect(run.taskCount).toBe(2);
    expect(tasks.map(t => t.coachNo)).toEqual(['A1', 'B1']);
  });
});

describe('MCC Task Lifecycle', () => {
  beforeEach(() => {
    Object.keys(state).forEach(k => { state[k] = {}; });
  });

  async function makeTask(trainNo = '12302') {
    await mccService.createDepot(manager(), { name: 'Plant B', stationId: 'st1' });
    const depotId = Object.keys(state.mcc_depots)[0];
    const run = await mccService.createWashingRun(manager(), {
      depotId,
      trainNo,
      coachNos: ['A1'],
      assignedWorkers: [{ coachNo: 'A1', workerId: 'w1', workerName: 'Coach Washer' }],
    });
    return run.tasks[0];
  }

  it('worker submits the assigned coach task', async () => {
    const taskId = await makeTask();
    const res = await mccService.submitTask(worker(), {
      taskId,
      afterPhoto: 'photos://after-a1.jpg',
    });
    expect(res.success).toBe(true);
    expect(state.mcc_washing_tasks[taskId].status).toBe('SUBMITTED');
  });

  it('a different worker cannot submit someone elses task', async () => {
    const taskId = await makeTask();
    await expect(mccService.submitTask({ uid: 'intruder', role: 'WORKER' }, { taskId }))
      .rejects.toThrow(/not assigned/);
  });

  it('supervisor approves the SUBMITTED task and rolls up the run', async () => {
    const taskId = await makeTask();
    await mccService.submitTask(worker(), { taskId, afterPhoto: 'u' });
    const res = await mccService.approveTask(manager(), taskId, { remarks: 'ok' });
    expect(res.success).toBe(true);
    expect(state.mcc_washing_tasks[taskId].status).toBe('APPROVED');
    expect(state.mcc_washing_tasks[taskId].approvedBy).toBe('m1');
    const runDoc = Object.values(state.mcc_washing_runs)[0];
    expect(runDoc.approvedTaskCount).toBe(1);
    expect(runDoc.completedTaskCount).toBe(1);
  });

  it('cannot approve a non-SUBMITTED task', async () => {
    const taskId = await makeTask();
    await expect(mccService.approveTask(manager(), taskId)).rejects.toThrow(/Only SUBMITTED tasks/);
  });

  it('rejection moves task to REJECTED with a reason', async () => {
    const taskId = await makeTask('12303');
    await mccService.submitTask(worker(), { taskId, afterPhoto: 'u' });
    const res = await mccService.rejectTask(manager(), taskId, { reason: 'Streaks left' });
    expect(res.success).toBe(true);
    expect(state.mcc_washing_tasks[taskId].status).toBe('REJECTED');
    expect(state.mcc_washing_tasks[taskId].rejectionReason).toBe('Streaks left');
  });
});

describe('MCC Attendance', () => {
  beforeEach(() => {
    Object.keys(state).forEach(k => { state[k] = {}; });
  });

  it('requires start before mid', async () => {
    await expect(mccService.markAttendance(worker(), { attendanceType: 'mid' }))
      .rejects.toThrow(/start/);
  });

  it('marks start -> mid -> end', async () => {
    await mccService.markAttendance(worker(), { attendanceType: 'start', imageUrl: 'u1' });
    const mid = await mccService.markAttendance(worker(), { attendanceType: 'mid', imageUrl: 'u2' });
    expect(mid.success).toBe(true);
    await mccService.markAttendance(worker(), { attendanceType: 'end', imageUrl: 'u3' });
    const status = await mccService.getAttendanceStatus(worker(), {});
    expect(status.isStartMarked).toBe(true);
    expect(status.isMidMarked).toBe(true);
    expect(status.isEndMarked).toBe(true);
  });

  it('does not allow double end attendance', async () => {
    await mccService.markAttendance(worker(), { attendanceType: 'start' });
    await mccService.markAttendance(worker(), { attendanceType: 'end' });
    await expect(mccService.markAttendance(worker(), { attendanceType: 'end' }))
      .rejects.toThrow(/already/);
  });
});

describe('MCC Dashboard', () => {
  beforeEach(() => {
    Object.keys(state).forEach(k => { state[k] = {}; });
  });

  it('returns aggregate run/task counts', async () => {
    await mccService.createDepot(manager(), { name: 'Plant D', stationId: 'st1' });
    const depotId = Object.keys(state.mcc_depots)[0];
    const { runId } = await mccService.createWashingRun(manager(), {
      depotId,
      trainNo: '12304',
      coachNos: ['A1'],
      assignedWorkers: [{ coachNo: 'A1', workerId: 'w1', workerName: 'Coach Washer' }],
    });
    const { dashboard } = await mccService.getDashboard(worker());
    expect(dashboard.depots).toBe(1);
    expect(dashboard.runs.total).toBe(1);
    expect(dashboard.runs.scheduled).toBe(1);
    expect(dashboard.myTasks.total).toBe(1);
    expect(dashboard.tasks.open).toBe(1);
  });
});