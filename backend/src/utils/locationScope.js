const norm = (r) => String(r || '').trim().toLowerCase().replace(/[_\s]+/g, ' ');

/**
 * The zone / division a request may look at. The app sends the user's own zone and division as filters, but
 * a client can send any value, so the server pins it to the logged-in user's location:
 *  - Super Admin / Company Master: whatever they ask for (or everything).
 *  - Railway Master: their zone; they may narrow to a division inside it.
 *  - everyone else: their own zone and division.
 * When the user has no zone / division on record (older accounts) the requested value is kept.
 */
export function scopedLocation(user, query = {}) {
  const requested = { zone: query.zone || null, division: query.division || null };
  if (!user) return requested;
  const role = norm(user.role);
  if (role === 'super admin' || role === 'company master') return requested;
  const zone = user.zone || requested.zone;
  const division = role === 'railway master' ? requested.division : (user.division || requested.division);
  return { zone, division };
}
