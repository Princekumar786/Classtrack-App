/**
 * Grant ClassTrack Pro to a user directly (server-trusted `_entitlements/{uid}`).
 *
 * This is the SIMPLEST, most reliable way to comp a user — it writes the flag
 * your app already reads live, so Pro appears without any RevenueCat grant,
 * webhook, or app update. Use it for support comps, testers, giveaways, etc.
 *
 * Auth: needs ./serviceAccount.json (same file the other admin scripts use).
 *
 * SAFE BY DEFAULT: prints what it WOULD do and writes nothing until --commit.
 *
 * Usage:
 *   # 30 days of Pro (time-boxed, auto-expires):
 *   node grantPro.mjs --uid <UID> --days 30
 *   node grantPro.mjs --uid <UID> --days 30 --commit
 *
 *   # Grant until a specific date (ISO):
 *   node grantPro.mjs --uid <UID> --until 2026-10-25T17:42:03Z --commit
 *
 *   # Permanent / lifetime comp (never expires until you revoke it):
 *   node grantPro.mjs --uid <UID> --lifetime --commit
 *
 *   # Revoke a comp (clears pro + proUntil): use revokeEntitlements.mjs instead.
 *
 * Flags:
 *   --uid <UID>       Target Firebase user id (required).
 *   --days <N>        Grant N days of Pro from now (sets proUntil).
 *   --until <ISO>     Grant until this ISO datetime (sets proUntil).
 *   --lifetime        Permanent grant (sets pro:true). Overrides --days/--until.
 *   --commit          Actually write. Without it, this is a dry run.
 */

import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { readFileSync } from "node:fs";

const args = process.argv.slice(2);
const has = (f) => args.includes(f);
const val = (f) => {
  const i = args.indexOf(f);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
};

const UID = val("--uid");
const DAYS = val("--days");
const UNTIL = val("--until");
const LIFETIME = has("--lifetime");
const COMMIT = has("--commit");

if (!UID) {
  console.error("Missing --uid <UID>. See usage at top of this file.");
  process.exit(1);
}

let patch;
let human;
if (LIFETIME) {
  patch = { pro: true, updatedAt: Date.now(), lastEvent: "ADMIN_GRANT_LIFETIME", needsReconcile: false };
  human = "LIFETIME (permanent pro:true)";
} else if (UNTIL) {
  const ms = Date.parse(UNTIL);
  if (!Number.isFinite(ms)) {
    console.error(`--until "${UNTIL}" is not a valid ISO datetime.`);
    process.exit(1);
  }
  patch = { proUntil: ms, pro: false, updatedAt: Date.now(), lastEvent: "ADMIN_GRANT", needsReconcile: false };
  human = `until ${new Date(ms).toISOString()}`;
} else if (DAYS) {
  const n = Number(DAYS);
  if (!Number.isFinite(n) || n <= 0) {
    console.error(`--days "${DAYS}" must be a positive number.`);
    process.exit(1);
  }
  const ms = Date.now() + n * 24 * 60 * 60 * 1000;
  patch = { proUntil: ms, pro: false, updatedAt: Date.now(), lastEvent: "ADMIN_GRANT", needsReconcile: false };
  human = `${n} day(s) → until ${new Date(ms).toISOString()}`;
} else {
  console.error("Choose one of: --days <N>, --until <ISO>, or --lifetime.");
  process.exit(1);
}

const sa = JSON.parse(readFileSync("./serviceAccount.json", "utf8"));
initializeApp({ credential: cert(sa) });
const db = getFirestore();

const ref = db.collection("_entitlements").doc(UID);
const snap = await ref.get();
const cur = snap.exists ? snap.data() || {} : {};
console.log(`Target: _entitlements/${UID}`);
console.log(`Current: pro=${cur.pro === true}, proUntil=${cur.proUntil ?? "none"}, lastEvent=${cur.lastEvent ?? "none"}`);
console.log(`${COMMIT ? "GRANTING" : "[dry-run] would grant"}: ${human}`);

if (!COMMIT) {
  console.log("\nDry run only — re-run with --commit to apply.");
  process.exit(0);
}

await ref.set(patch, { merge: true });
console.log("\u2713 Granted. The app reads this flag live, so Pro appears on next open.");
process.exit(0);
