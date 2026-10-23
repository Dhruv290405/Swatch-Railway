import { beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({ db: { collection: vi.fn() } }));

vi.mock('../src/database/index.js', () => ({ db: state.db, admin: {} }));

const { v2Service } = await import('../src/services/v2Service.js');

const run = {
  trainNo: '12345',
  trainName: 'Test Express',
  scheduledDeparture: '2026-10-24T06:00:00.000Z',
  coaches: [{
    coachPosition: 'S1',
    coachType: 'Sleeper',
    janitorId: 'janitor-1',
    workerId: 'janitor-1',
  }],
};

const tasks = [
  { runInstanceId: 'run-1', isParentTask: false, coachNo: 'S1', workerId: 'janitor-1', taskType: 'CLEANING', taskName: 'Clean toilet', status: 'pending' },
  { runInstanceId: 'run-1', isParentTask: false, coachNo: 'S1', workerId: 'janitor-1', taskType: 'LINEN_CHANGE', taskName: 'Linen change', status: 'pending' },
];

function mockDb({ runDoc = run, runExists = true, taskDocs = tasks } = {}) {
  state.db.collection.mockImplementation(name => {
    if (name === 'RunInstance') {
      return {
        doc: id => ({ get: async () => ({ id, exists: runExists, data: () => runDoc }) }),
      };
    }
    if (name === 'task_instances') {
      const query = {
        where: () => query,
        limit: () => query,
        get: async () => ({
          forEach: callback => taskDocs.forEach(task => callback({ data: () => task })),
        }),
      };
      return query;
    }
    throw new Error(`Unexpected collection: ${name}`);
  });
}

describe('worker task board', () => {
  beforeEach(() => vi.clearAllMocks());

  it('resolves a janitor assignment stored only in janitorId', async () => {
    mockDb();

    const result = await v2Service.getWorkerMyTasks(
      'janitor-1',
      { runInstanceId: 'run-1' },
      { role: 'JANITOR' },
    );

    expect(result.success).toBe(true);
    expect(result.journey.runInstanceId).toBe('run-1');
    expect(result.tasks.map(task => task.taskType)).toEqual(['CLEANING']);
  });

  it('uses the requested run instance instead of any other active run', async () => {
    mockDb();

    const result = await v2Service.getWorkerMyTasks(
      'janitor-1',
      { runInstanceId: 'run-1' },
      { role: 'JANITOR' },
    );

    expect(state.db.collection).toHaveBeenCalledWith('RunInstance');
    expect(result.journey.runInstanceId).toBe('run-1');
  });

  it('returns no journey when the requested run is not assigned to the worker', async () => {
    mockDb({
      runDoc: {
        ...run,
        coaches: [{ coachPosition: 'S1', workerId: 'someone-else' }],
      },
    });

    const result = await v2Service.getWorkerMyTasks(
      'janitor-1',
      { runInstanceId: 'run-1' },
      { role: 'JANITOR' },
    );

    expect(result.success).toBe(false);
  });
});
