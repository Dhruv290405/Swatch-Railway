import { beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({ db: { collection: vi.fn() } }));

vi.mock('../src/database/index.js', () => ({ db: state.db, admin: {} }));

const { userService } = await import('../src/services/userService.js');

describe('worker profile run assignments', () => {
  beforeEach(() => vi.clearAllMocks());

  it('returns the assigned run and coach for an attendantId assignment', async () => {
    const run = {
      runInstanceId: 'run-1',
      instanceId: 'train-instance-1',
      trainNo: '12345',
      trainName: 'Test Express',
      departureDate: '2026-10-22',
      status: 'Active',
      coaches: [{
        coachPosition: 'B1',
        coachType: 'AC',
        workerId: 'janitor-1',
        attendantId: 'attendant-1',
      }],
    };

    state.db.collection.mockImplementation(name => {
      if (name === 'users') {
        return { doc: () => ({ get: async () => ({ exists: true, data: () => ({ uid: 'attendant-1', fullName: 'Attendant One' }) }) }) };
      }
      if (name === 'RunInstance') {
        const query = {
          where: () => query,
          limit: () => query,
          get: async () => ({
            forEach: callback => callback({ id: 'run-1', data: () => run }),
          }),
        };
        return query;
      }
      throw new Error(`Unexpected collection: ${name}`);
    });

    const result = await userService.getWorkerProfile('attendant-1');

    expect(result.assignedRuns).toHaveLength(1);
    expect(result.assignedRuns[0]).toMatchObject({
      runInstanceId: 'run-1',
      myCoach: {
        coachPosition: 'B1',
        workerType: 'Attendant',
      },
    });
  });
});
