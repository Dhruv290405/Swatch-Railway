import { describe, expect, it, vi } from 'vitest';

vi.mock('../src/database/index.js', () => ({ db: {}, admin: {} }));

const { executionSheetService } = await import('../src/services/executionSheetService.js');

describe('execution sheet monthly BOQ requirement', () => {
  it('requires the daily BOQ count for every day of the month', () => {
    expect(executionSheetService._expectedPassesForMonth(
      { boqTimesPerPeriod: 3, cleaningFrequency: 'daily' },
      30,
    )).toBe(90);
  });

  it('uses requiredPassesPerDay when the area master provides it', () => {
    expect(executionSheetService._expectedPassesForMonth(
      { boqTimesPerPeriod: 3, cleaningFrequency: 'daily', requiredPassesPerDay: 2 },
      30,
    )).toBe(60);
  });

  it('keeps a monthly frequency at its per-month count', () => {
    expect(executionSheetService._expectedPassesForMonth(
      { boqTimesPerPeriod: 2, cleaningFrequency: 'monthly' },
      31,
    )).toBe(2);
  });

  it('scales a weekly frequency to the days in the month', () => {
    expect(executionSheetService._expectedPassesForMonth(
      { boqTimesPerPeriod: 7, cleaningFrequency: 'weekly' },
      28,
    )).toBe(28);
  });
});
