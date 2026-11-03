import { describe, it, expect } from 'vitest';
import jwt from 'jsonwebtoken';
import { errorHandler } from '../src/middleware/errorHandler.js';

const run = (err) => {
  let out;
  const res = {
    status(c) { this.code = c; return this; },
    json(b) { out = { status: this.code, body: b }; return this; },
  };
  errorHandler(err, {}, res, () => {});
  return out;
};

describe('errorHandler JWT mapping', () => {
  it('maps a malformed token to 401', () => {
    let err;
    try { jwt.verify('garbage.token.value', 'secret'); } catch (e) { err = e; }
    const r = run(err);
    expect(r.status).toBe(401);
    expect(r.body.success).toBe(false);
  });

  it('maps an expired token to 401 with a re-login message', () => {
    const token = jwt.sign({ uid: 'u' }, 'secret', { expiresIn: -10 });
    let err;
    try { jwt.verify(token, 'secret'); } catch (e) { err = e; }
    const r = run(err);
    expect(r.status).toBe(401);
    expect(r.body.error).toMatch(/log in again/i);
  });

  it('maps a Firestore undefined-query-constraint error to 400', () => {
    const err = new Error('Value for argument "value" is not a valid query constraint. "undefined" values are only ignored inside of objects.');
    const r = run(err);
    expect(r.status).toBe(400);
    expect(r.body.code).toBe('VALIDATION_ERROR');
  });

  it('still returns 500 for ordinary errors', () => {
    expect(run(new Error('boom')).status).toBe(500);
  });
});
