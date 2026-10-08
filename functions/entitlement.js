/**
 * Pure entitlement logic, extracted so it can be unit-tested without the
 * Firestore / functions runtime (mirrors lifecycle.js).
 *
 * `deriveEntitlement` maps a RevenueCat REST v1 `subscriber` object to the Pro
 * state ClassTrack stores at `_entitlements/{uid}`:
 *   - pro:true      → a permanent / non-expiring entitlement (lifetime comp)
 *   - proUntil:<ms> → a time-boxed subscription/promo, expiring at that instant
 *   - neither       → nothing active
 * This is the single source of truth used by the reconcileEntitlement callable,
 * the reconcileFlaggedEntitlements cron, and the reconcileEntitlements.mjs
 * backfill script, so the webhook can never permanently strand a paying user.
 */

/// Normalizes a `proUntil` value (millis number or Firestore Timestamp) to ms.
export function toMillisMaybe(v) {
  if (typeof v === "number") return v;
  if (v && typeof v.toMillis === "function") return v.toMillis();
  return null;
}

/// Given a RevenueCat REST v1 `subscriber` object, decide the Pro state.
/// Returns { active, pro, proUntil }. Falls back to ANY active entitlement when
/// the configured id isn't present, so it stays robust to the dashboard's exact
/// entitlement id.
export function deriveEntitlement(subscriber, entitlementId, now) {
  const ents = (subscriber && subscriber.entitlements) || {};
  const isActive = (e) => {
    if (!e) return false;
    if (e.expires_date == null) return true; // non-expiring => lifetime
    const ms = Date.parse(e.expires_date);
    return Number.isFinite(ms) && ms > now;
  };
  let ent = ents[entitlementId];
  if (!isActive(ent)) {
    ent = Object.values(ents).find(isActive) || null;
  }
  if (!isActive(ent)) return { active: false, pro: false, proUntil: null };
  if (ent.expires_date == null) {
    return { active: true, pro: true, proUntil: null };
  }
  return { active: true, pro: false, proUntil: Date.parse(ent.expires_date) };
}
