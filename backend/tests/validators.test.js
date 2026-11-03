import { describe, it, expect } from 'vitest';
import { assertFormat, isPAN, isGSTIN, isMobile, isEmail } from '../src/utils/validators.js';

describe('PAN', () => {
  it('accepts ABCDE1234F (case-insensitive, trimmed)', () => {
    expect(isPAN('ABCDE1234F')).toBe(true);
    expect(assertFormat('pan', ' abcde1234f ')).toBe('ABCDE1234F');
  });
  for (const bad of ['ABCDE12345', '1BCDE1234F', 'ABCD1234FF', 'ABCDE1234', 'ABCDE1234FG']) {
    it(`rejects ${bad}`, () => {
      expect(isPAN(bad)).toBe(false);
      expect(() => assertFormat('pan', bad, 'PAN')).toThrow(/PAN/);
    });
  }
});

describe('GSTIN', () => {
  it('accepts a valid 15-char GSTIN', () => {
    expect(isGSTIN('22ABCDE1234F1Z5')).toBe(true);
    expect(assertFormat('gstin', '22abcde1234f1z5')).toBe('22ABCDE1234F1Z5');
  });
  for (const bad of ['22ABCDE1234F1X5', 'ABCDE1234F1Z5', '22ABCDE1234F0Z5', '22ABCDE1234F1Z', '']) {
    it(`rejects "${bad}" when provided`, () => {
      expect(isGSTIN(bad)).toBe(false);
    });
  }
});

describe('assertFormat passthrough for legacy payloads', () => {
  it('does not reject empty / missing optional values', () => {
    expect(assertFormat('pan', '')).toBe('');
    expect(assertFormat('gstin', undefined)).toBeUndefined();
    expect(assertFormat('mobile', null)).toBeNull();
  });
});

describe('mobile / email', () => {
  it('validates Indian mobile numbers', () => {
    expect(isMobile('9876543210')).toBe(true);
    expect(isMobile('5876543210')).toBe(false);
    expect(isMobile('98765')).toBe(false);
  });
  it('validates emails', () => {
    expect(isEmail('a.b@test.co.in')).toBe(true);
    expect(isEmail('not-an-email')).toBe(false);
  });
});
