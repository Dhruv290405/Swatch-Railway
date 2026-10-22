import { beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({
  db: {
    collection: vi.fn(),
  },
  storedFeedback: null,
}));

vi.mock('../src/database/index.js', () => ({ db: state.db, admin: {} }));

const { obhsService } = await import('../src/services/obhsService.js');

describe('worker feedback ratings', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    state.storedFeedback = null;
  });

  it('stores the selected worker and returns the submitted rating', async () => {
    const saved = vi.fn(async data => { state.storedFeedback = data; });
    state.db.collection.mockReturnValue({
      doc: () => ({ id: 'feedback-1', set: saved }),
    });

    const result = await obhsService.submitFeedback({ uid: 'inspector-1', fullName: 'Inspector' }, {
      feedbackType: 'official',
      workerId: 'worker-1',
      workerName: 'Worker One',
      raterType: 'Official',
      runInstanceId: 'run-1',
      coachNo: 'B1',
      ratings: { cleanliness: 4, toiletHygiene: 5 },
    });

    expect(state.storedFeedback).toMatchObject({
      workerId: 'worker-1',
      targetWorker: 'worker-1',
      coachNo: 'B1',
      raterType: 'Official',
    });
    expect(result.data).toMatchObject({ feedbackId: 'feedback-1', workerId: 'worker-1' });
  });

  it('returns saved feedback for the worker summary', async () => {
    const queryFor = collectionName => {
      const query = {
        where: vi.fn(() => query),
        limit: vi.fn(() => query),
        get: vi.fn(async () => {
          const docs = collectionName === 'obhs_feedbacks'
            ? [{ id: 'feedback-1', data: () => ({
                workerId: 'worker-1',
                coachNo: 'B1',
                raterType: 'Official',
                overallRating: 4.5,
                ratings: { cleanliness: 4, toiletHygiene: 5 },
                createdAt: '2026-10-22T10:00:00.000Z',
              }) }]
            : [];
          return { forEach: callback => docs.forEach(callback) };
        }),
      };
      return query;
    };
    state.db.collection.mockImplementation(name => queryFor(name));

    const result = await obhsService.getWorkerStats('worker-1');

    expect(result.recentFeedbacks).toHaveLength(1);
    expect(result.recentFeedbacks[0]).toMatchObject({ coachNo: 'B1', overallRating: 4.5 });
    expect(result.ratingStats.totalRatings).toBe(1);
    expect(result.ratingStats.averageScore).toBe(4.5);
  });
});
