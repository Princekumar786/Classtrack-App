/**
 * Free-tier quota identity — pure helpers (unit-tested without the runtime).
 *
 * Problem: the free schedule-scan allowance was counted per Firebase uid
 * (`_aiUsage/{uid}`). Deleting the account wiped that doc, and signing up
 * again with the SAME email produced a brand-new uid → a fresh allowance.
 *
 * Fix: also count free usage against a stable identity derived from the
 * account's email, stored in the server-only `_freeQuota/{key}` collection,
 * which account deletion intentionally does NOT remove. Only a one-way hash
 * of the normalized email is stored (never the address itself).
 */
import { createHash } from "node:crypto";

// Domains where dots in the local part are ignored by the mail provider, so
// "p.r.i.y.a@gmail.com" and "priya@gmail.com" are the same inbox.
const DOT_INSENSITIVE_DOMAINS = new Set(["gmail.com", "googlemail.com"]);

// Fixed namespace so these hashes can't be matched against other datasets'
// plain email hashes. Changing it would reset every free allowance.
const KEY_NAMESPACE = "classtrack:freeQuota:v1:";

/// Canonical form of an email for abuse-limiting purposes:
///  - trims + lowercases,
///  - drops "+tag" sub-addressing (priya+1@x.com → priya@x.com),
///  - removes dots for Gmail and maps googlemail.com → gmail.com.
/// Returns null for anything that isn't a plausible address.
export function normalizeEmail(email) {
  if (typeof email !== "string") return null;
  const e = email.trim().toLowerCase();
  const at = e.lastIndexOf("@");
  if (at <= 0 || at === e.length - 1) return null;
  let local = e.slice(0, at);
  let domain = e.slice(at + 1);
  const plus = local.indexOf("+");
  if (plus >= 0) local = local.slice(0, plus);
  if (DOT_INSENSITIVE_DOMAINS.has(domain)) {
    local = local.replace(/\./g, "");
    domain = "gmail.com";
  }
  if (!local || !domain.includes(".")) return null;
  return `${local}@${domain}`;
}

/// Stable document id for `_freeQuota` — SHA-256 of the normalized email, or
/// null when the account has no usable email (caller falls back to uid only).
export function freeQuotaKey(email) {
  const n = normalizeEmail(email);
  if (!n) return null;
  return createHash("sha256").update(KEY_NAMESPACE + n).digest("hex");
}

/// Decides a free-usage attempt given the counts already recorded under the
/// uid doc and the email-identity doc. The effective usage is the HIGHER of
/// the two (so legacy per-uid usage carries over, and a fresh uid can't reset
/// a used identity). Returns the new count to persist and whether to allow.
export function decideFreeUse(uidCount, identityCount, max) {
  const used = Math.max(Number(uidCount) || 0, Number(identityCount) || 0);
  if (used >= max) return { allowed: false, next: used };
  return { allowed: true, next: used + 1 };
}


/// Bucket id for a recurring allowance: "YYYY-MM" for month, "YYYY-MM-DD" for
/// day (UTC), or null for a lifetime allowance that never resets.
export function periodKey(period, now = new Date()) {
  if (period === "month") return now.toISOString().slice(0, 7);
  if (period === "day") return now.toISOString().slice(0, 10);
  return null;
}

/// Usage already recorded in a quota doc's data for [action]. For a periodic
/// allowance, a count from an older bucket is stale and reads as 0. Field
/// names (`${action}Count` / `${action}Period`) match the existing
/// `_aiUsage` layout so legacy per-uid counts carry over unchanged.
export function usedIn(data, action, key) {
  if (!data) return 0;
  const count = Number(data[`${action}Count`]) || 0;
  if (key == null) return count;
  return data[`${action}Period`] === key ? count : 0;
}
