import { beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({
  db: {
    collection: vi.fn(),
    batch: vi.fn(),
  },
  runData: { status: 'Active', instanceId: 'train-instance-1' },
  attendanceDocs: [],
  taskDocs: [],
  deletedRun: false,
}));

vi.mock('../src/database/index.js', () => ({ db: state.db, admin: {} }));

const { runInstanceService } = await import('../src/services/runInstanceService.js');

function querySnapshot(docs = []) {
  return { empty: docs.length === 0, docs, forEach: callback => docs.forEach(callback) };
}

describe('run instance deletion', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    state.runData = { status: 'Active', instanceId: 'train-instance-1' };
    state.attendanceDocs = [];
    state.taskDocs = [];
    state.deletedRun = false;

    state.db.collection.mockImplementation(name => {
      if (name === 'RunInstance') {
        return {
          doc: () => ({
            get: async () => ({ exists: true, data: () => state.runData }),
            delete: async () => { state.deletedRun = true; },
          }),
        };
      }
      if (name === 'TrainPairs') return { doc: () => ({ update: vi.fn() }) };

      return {
        where: () => ({
          limit: () => ({
            get: async () => querySnapshot(
              name === 'obhs_attendance' ? state.attendanceDocs :
              name === 'task_instances' ? state.taskDocs : [],
            ),
          }),
        }),
      };
    });
  });

  it('deletes an Active run that has not started attendance or tasks', async () => {
    const result = await runInstanceService.deleteRunInstance('run-1');

    expect(result.success).toBe(true);
    expect(state.deletedRun).toBe(true);
  });

  it('keeps a run once attendance has started', async () => {
    state.attendanceDocs = [{ id: 'attendance-1' }];

    await expect(runInstanceService.deleteRunInstance('run-1')).rejects.toThrow();
    expect(state.deletedRun).toBe(false);
  });

  it('keeps a run after task execution begins', async () => {
    state.taskDocs = [{ data: () => ({ status: 'COMPLETED' }) }];

    await expect(runInstanceService.deleteRunInstance('run-1')).rejects.toThrow();
    expect(state.deletedRun).toBe(false);
  });
});
