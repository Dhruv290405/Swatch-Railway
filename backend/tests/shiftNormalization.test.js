import { describe, expect, it, vi } from 'vitest';

vi.mock('../src/database/index.js', () => ({ db: {}, admin: {} }));

const { taskManagementService } = await import('../src/services/taskManagementService.js');

describe('shift value normalization', () => {
  it('treats station-cleaning evening and generic afternoon as the same shift', () => {
    expect(taskManagementService._normalizeShiftValue('Evening')).toBe('afternoon');
    expect(taskManagementService._normalizeShiftValue(' afternoon ')).toBe('afternoon');
  });

  it('keeps morning and night unchanged', () => {
    expect(taskManagementService._normalizeShiftValue('Morning')).toBe('morning');
    expect(taskManagementService._normalizeShiftValue('NIGHT')).toBe('night');
  });
});
