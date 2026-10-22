import { describe, expect, it, vi } from 'vitest';
import { authorizeObhsContractAccess } from '../src/middleware/authorization.js';

const allowedMethods = [
  ['GET', '/api/obhs/tasks/board'],
  ['POST', '/api/obhs/tasks/submit'],
  ['GET', '/api/obhs/attendance/status'],
  ['POST', '/api/obhs/attendance'],
  ['GET', '/api/obhs/worker/active-run'],
  ['GET', '/api/obhs/complaints'],
  ['POST', '/api/obhs/complaints/raise'],
  ['GET', '/api/obhs/feedback/worker-summary'],
  ['POST', '/api/obhs/feedback/passenger'],
];

describe('OBHS access for station-cleaning workers', () => {
  it.each(['JANITOR', 'ATTENDANT'])(
    'allows %s to use worker task and attendance endpoints only',
    role => {
      for (const [method, path] of allowedMethods) {
        const next = vi.fn();
        expect(() => authorizeObhsContractAccess({
          user: { contractType: 'station_cleaning', role },
          method,
          originalUrl: `${path}?runInstanceId=run-1`,
          query: { runInstanceId: 'run-1' },
        }, {}, next)).not.toThrow();
        expect(next).toHaveBeenCalledOnce();
      }

      const next = vi.fn();
      expect(() => authorizeObhsContractAccess({
        user: { contractType: 'station_cleaning', role },
        method: 'GET',
        originalUrl: '/api/obhs/complaints',
        query: {},
      }, {}, next)).toThrow(/contract type "station_cleaning"/);
      expect(next).not.toHaveBeenCalled();
    },
  );

  it('allows a typed WORKER account and keeps MCC access blocked', () => {
    const next = vi.fn();
    expect(() => authorizeObhsContractAccess({
      user: { contractType: 'station_cleaning', role: 'WORKER', workerType: 'Attendant' },
      method: 'GET',
      originalUrl: '/api/obhs/worker/active-run',
    }, {}, next)).not.toThrow();
    expect(next).toHaveBeenCalledOnce();

    expect(() => authorizeObhsContractAccess({
      user: { contractType: 'mcc', role: 'WORKER' },
      method: 'GET',
      originalUrl: '/api/obhs/worker/active-run',
    }, {}, vi.fn())).toThrow(/contract type "mcc"/);
  });
});
