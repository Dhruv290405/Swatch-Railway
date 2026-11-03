// Backend-side access rules for OBHS runs (RunInstance documents).
//
// Every rule only fires when the data it needs is present on BOTH the user and the run,
// so legacy runs/users that lack a division or entityId keep their old behaviour.

export const FIELD_WORKER_ROLES = ['JANITOR', 'ATTENDANT', 'WORKER', 'RAILWAY_WORKER'];
export const PLATFORM_ROLES = ['SUPER_ADMIN', 'ADMIN', 'COMPANY_MASTER', 'RAILWAY_MASTER'];

export const roleKeyOf = (user) => String(user?.role || '').toUpperCase().replace(/\s+/g, '_');

export const isFieldWorker = (user) => FIELD_WORKER_ROLES.includes(roleKeyOf(user));

export function isAssignedToRun(user, run) {
  const uid = user?.uid;
  return (run?.coaches || []).some(
    (c) => c.workerId === uid || c.janitorId === uid || c.attendantId === uid,
  );
}

/** Returns an error message when `user` must not access `run`, otherwise null. */
export function runAccessError(user, run) {
  const role = roleKeyOf(user);
  if (FIELD_WORKER_ROLES.includes(role)) {
    return isAssignedToRun(user, run) ? null : 'You are not assigned to this run.';
  }
  if (PLATFORM_ROLES.includes(role)) return null;
  if (user?.division && run?.division && user.division !== run.division) {
    return 'This run belongs to another division.';
  }
  if (String(user?.userType || '').toLowerCase() === 'contractor'
    && user?.entityId && run?.entityId && user.entityId !== run.entityId) {
    return 'This run belongs to another contractor.';
  }
  return null;
}

/** Drops runs that belong to a different contractor company than the caller's. */
export function filterRunsByEntity(user, runs) {
  if (!Array.isArray(runs)) return runs;
  if (PLATFORM_ROLES.includes(roleKeyOf(user))) return runs;
  if (String(user?.userType || '').toLowerCase() !== 'contractor' || !user?.entityId) return runs;
  return runs.filter((r) => !r.entityId || r.entityId === user.entityId);
}
