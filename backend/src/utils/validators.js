// Reusable format validators. Each `normalize*` trims/upper-cases; each `is*` expects a normalized value.
// Empty values are treated as "not provided" by `assertFormat`, so legacy payloads that omit
// optional fields keep working; only non-empty malformed values are rejected.
import { ValidationError } from '../errors/index.js';

export const PAN_REGEX = /^[A-Z]{5}[0-9]{4}[A-Z]$/;
export const GSTIN_REGEX = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/;
export const MOBILE_REGEX = /^[6-9][0-9]{9}$/;
export const EMAIL_REGEX = /^[\w.+-]+@[\w-]+(\.[\w-]+)+$/;
export const AADHAAR_REGEX = /^[0-9]{12}$/;
export const IFSC_REGEX = /^[A-Z]{4}0[A-Z0-9]{6}$/;

export const normalizeCode = (v) => String(v ?? '').trim().toUpperCase().replace(/\s+/g, '');

export const isPAN = (v) => PAN_REGEX.test(normalizeCode(v));
export const isGSTIN = (v) => GSTIN_REGEX.test(normalizeCode(v));
export const isMobile = (v) => MOBILE_REGEX.test(String(v ?? '').trim());
export const isEmail = (v) => EMAIL_REGEX.test(String(v ?? '').trim());

const RULES = {
  pan: { test: isPAN, message: 'Invalid PAN. Expected format: ABCDE1234F (5 letters, 4 digits, 1 letter).', normalize: normalizeCode },
  gstin: { test: isGSTIN, message: 'Invalid GSTIN. Expected 15-character format, e.g. 22ABCDE1234F1Z5.', normalize: normalizeCode },
  mobile: { test: isMobile, message: 'Invalid mobile number. Must be a 10-digit Indian number starting with 6-9.', normalize: (v) => String(v).trim() },
  email: { test: isEmail, message: 'Invalid email address.', normalize: (v) => String(v).trim().toLowerCase() },
};

/**
 * Returns the normalized value, null/undefined/'' passthrough when not provided,
 * and throws ValidationError for a provided-but-malformed value.
 */
export function assertFormat(kind, value, label) {
  const rule = RULES[kind];
  if (value === undefined || value === null || String(value).trim() === '') return value;
  const normalized = rule.normalize(value);
  if (!rule.test(normalized)) {
    throw new ValidationError(label ? `${label}: ${rule.message}` : rule.message);
  }
  return normalized;
}
