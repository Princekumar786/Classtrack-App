/**
 * Backfill: reconcile server-trusted `_entitlements/{uid}` against RevenueCat's
 * authoritative REST API and REPAIR any account that was under-granted by a
 * missed/delayed/denied webhook (e.g. the "renewal charged but no Pro" bug, or
 * a promo that stuck as permanent "Lifetime").
 *
 * This is the ONE-OFF companion to the in-app `reconcileEntitlement` callable
 * and the hourly `reconcileFlaggedEntitlements` cron — use it to fix everyone
 * who was already affected, right now, without waiting for them to open the app.
 *
 * REPAIR-ONLY: grants/extends access to match RevenueCat but NEVER revokes, so
 * it can't strip a manual comp (`pro:true`) or a referral `proUntil` gift.
 * (Use revokeEntitlements.mjs for the revoke side.)
 *
 * Auth: needs ./serviceAccount.json (same file setAdmin.mjs / revokeEntitlements.mjs use).
 * RevenueCat: needs the SECRET REST key (starts with "sk_"), via either
 *   --api-key sk_xxx   OR   env REVENUECAT_API_KEY.
 *
 * SAFE BY DEFAULT: prints what it WOULD do and writes nothing until --commit.
 *
 * Usage:
 *   # Fix only the docs the webhook flagged as needing a re-check (recommended):
 *   node reconcileEntitlements.mjs --flagged
 *   node reconcileEntitlements.mjs --flagged --commit
 *
 *   # Fix specific users:
 *   node reconcileEntitlements.mjs --uids uidA,uidB --commit
 *
 *   # Sweep EVERY entitlement doc (heavier — one RevenueCat call each):
 *   node reconcileEntitlements.mjs --all --commit
 *
 * Flags:
 *   --flagged        Target docs where needsReconcile === true.
 *   --uids a,b,c     Target these specific UIDs.
 *   --all            Target every `_entitlements` doc.
 *   --api-key sk_..  RevenueCat secret REST key (else env REVENUECAT_API_KEY).
 *   --commit         Actually write. Without it, this is a dry run.
 */

import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { readFileSync } from "node:fs";
import { deriveEntitlement, toMillisMaybe } from "./entitlement.js";

const args = process.argv.slice(2);
const has = (f) => args.includes(f);
const val = (f) => {
  const i = args.indexOf(f);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
};

const FLAGGED = has("--flagged");
const ALL = has("--all");
const COMMIT = has("--commit");
const UIDS = (val("--uids") || "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);
const API_KEY = val("--api-key") || process.env.REVENUECAT_API_KEY || "";

const PRO_ENTITLEMENT_ID = "pro";

if (!API_KEY) {
  console.error(
    "Missing RevenueCat secret key. Pass --api-key sk_xxx or set REVENUECAT_API_KEY."
  );
  process.exit(1);
}

const sa = JSON.parse(readFileSync("./serviceAccount.json", "utf8"));
initializeApp({ credential: cert(sa) });
const db = getFirestore();

async function fetchSubscriber(uid) {
  const resp = await fetch(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`,
    {
      headers: {
        Authorization: `Bearer ${API_KEY}`,
        "Content-Type": "application/json",
      },
    }
  );
  if (resp.status === 404) return null;
  if (!resp.ok) throw new Error(`RevenueCat REST ${resp.status} for ${uid}`);
  const json = await resp.json();
  return json.subscriber || {};
}

// ── Determine target UIDs ──────────────────────────────────────────────────
let targets = [];
if (UIDS.length) {
  targets = UIDS;
} else if (FLAGGED) {
  const snap = await db
    .collection("_entitlements")
    .where("needsReconcile", "==", true)
    .get();
  targets = snap.docs.map((d) => d.id);
} else if (ALL) {
  const snap = await db.collection("_entitlements").get();
  targets = snap.docs.map((d) => d.id);
} else {
  console.error("Nothing to do. Pass --flagged, --uids a,b,c, or --all.");
  process.exit(1);
}

if (targets.length === 0) {
  console.log("No matching accounts found.");
  process.exit(0);
}

console.log(
  `${COMMIT ? "RECONCILING" : "[dry-run] would reconcile"} ${targets.length} account(s) against RevenueCat…\n`
);

let granted = 0;
let extended = 0;
let unchanged = 0;
let noSub = 0;
let failed = 0;
const now = Date.now();

for (const uid of targets) {
  try {
    const subscriber = await fetchSubscriber(uid);
    if (subscriber === null) {
      noSub++;
      console.log(`  ${uid}: RevenueCat has no record — skipped.`);
      continue;
    }
    const derived = deriveEntitlement(subscriber, PRO_ENTITLEMENT_ID, now);
    const ref = db.collection("_entitlements").doc(uid);
    const snap = await ref.get();
    const cur = snap.exists ? snap.data() || {} : {};
    const curUntil = toMillisMaybe(cur.proUntil) || 0;
    const hadAccess = cur.pro === true || curUntil > now;

    let action = "no change";
    const patch = { updatedAt: now, lastEvent: "RECONCILE_BACKFILL", needsReconcile: false };

    if (derived.pro === true) {
      if (cur.pro !== true) {
        patch.pro = true;
        action = "GRANT lifetime";
        granted++;
      } else unchanged++;
    } else if (derived.proUntil) {
      const best = Math.max(derived.proUntil, curUntil);
      if (best !== curUntil) patch.proUntil = best;
      if (!hadAccess) {
        action = `GRANT until ${new Date(derived.proUntil).toISOString()}`;
        granted++;
      } else if (best !== curUntil) {
        action = `EXTEND until ${new Date(best).toISOString()}`;
        extended++;
      } else unchanged++;
    } else {
      // RevenueCat shows nothing active — repair-only, do not revoke.
      unchanged++;
    }

    console.log(
      `  ${uid}: RC=${derived.pro ? "lifetime" : derived.proUntil ? new Date(derived.proUntil).toISOString() : "none"} | had=${hadAccess} | ${action}`
    );

    if (COMMIT && action !== "no change") {
      await ref.set(patch, { merge: true });
    } else if (COMMIT && cur.needsReconcile === true) {
      // Clear a stale flag even when nothing else changed.
      await ref.set({ needsReconcile: false, updatedAt: now }, { merge: true });
    }
  } catch (e) {
    failed++;
    console.error(`  ${uid}: FAILED — ${e.message}`);
  }
}

console.log(
  `\n${COMMIT ? "Done" : "Dry run"}: granted=${granted}, extended=${extended}, unchanged=${unchanged}, noRevenueCatRecord=${noSub}, failed=${failed}.`
);
if (!COMMIT) console.log("Re-run with --commit to apply.");
process.exit(0);
