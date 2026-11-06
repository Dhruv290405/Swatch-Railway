import { describe, it, expect } from 'vitest';
import { scopedLocation } from '../src/utils/locationScope.js';

describe('scopedLocation', () => {
  it('super admin and company master get what they ask for', () => {
    expect(scopedLocation({ role: 'SUPER_ADMIN', zone: 'NR' }, { zone: 'WR', division: 'MUMBAI' })).toEqual({ zone: 'WR', division: 'MUMBAI' });
    expect(scopedLocation({ role: 'Company Master' }, {})).toEqual({ zone: null, division: null });
  });
  it('a railway admin is pinned to their own zone and division whatever the app sends', () => {
    expect(scopedLocation({ role: 'Railway Admin', zone: 'NR', division: 'DELHI' }, { zone: 'WR', division: 'MUMBAI' })).toEqual({ zone: 'NR', division: 'DELHI' });
  });
  it('a railway master is pinned to their zone but may narrow to a division', () => {
    expect(scopedLocation({ role: 'RAILWAY_MASTER', zone: 'NR' }, { zone: 'WR', division: 'DELHI' })).toEqual({ zone: 'NR', division: 'DELHI' });
  });
  it('accounts with no location on record keep the requested filter (legacy)', () => {
    expect(scopedLocation({ role: 'Railway Admin' }, { zone: 'WR', division: 'MUMBAI' })).toEqual({ zone: 'WR', division: 'MUMBAI' });
    expect(scopedLocation(null, { zone: 'WR' })).toEqual({ zone: 'WR', division: null });
  });
});
