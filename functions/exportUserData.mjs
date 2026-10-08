// functions/exportUserData.mjs
// Export every user's profile + entitlement + all subcollections to JSON.
//
// Auth: needs ./serviceAccount.json (same file setAdmin.mjs uses).
//
// Usage:
//   node exportUserData.mjs            -> exports ALL users
//   node exportUserData.mjs <uid>      -> exports a single user
//
// Output: functions/export/<uid>.json per user + functions/export/all_users.json
import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import { readFileSync, mkdirSync, writeFileSync } from "node:fs";

const sa = JSON.parse(readFileSync("./serviceAccount.json", "utf8"));
initializeApp({ credential: cert(sa) });
const db = getFirestore();

// Recursively read a doc: its fields + every subcollection under it.
async function dumpDoc(ref) {
  const snap = await ref.get();
  const out = {
    id: ref.id,
    data: snap.exists ? snap.data() : null,
    subcollections: {},
  };
  const subs = await ref.listCollections();
  for (const sub of subs) {
    const docs = await sub.get();
    out.subcollections[sub.id] = [];
    for (const d of docs.docs) {
      out.subcollections[sub.id].push(await dumpDoc(d.ref)); // recurse
    }
  }
  return out;
}

async function exportOne(uid) {
  const user = await dumpDoc(db.collection("users").doc(uid));
  const ent = await db.collection("_entitlements").doc(uid).get();
  let email = null;
  try {
    email = (await getAuth().getUser(uid)).email;
  } catch {
    /* auth user may not exist */
  }
  return {
    uid,
    email,
    profile: user.data,
    entitlement: ent.exists ? ent.data() : null,
    collections: user.subcollections,
  };
}

mkdirSync("export", { recursive: true });
const argUid = process.argv[2];

let uids;
if (argUid) {
  uids = [argUid];
} else {
  const snap = await db.collection("users").get();
  uids = snap.docs.map((d) => d.id);
}

const all = [];
for (const uid of uids) {
  const record = await exportOne(uid);
  writeFileSync(`export/${uid}.json`, JSON.stringify(record, null, 2), "utf8");
  all.push(record);
  console.log(`\u2713 ${record.email || "(no email)"}  ->  export/${uid}.json`);
}
writeFileSync("export/all_users.json", JSON.stringify(all, null, 2), "utf8");
console.log(`\nDone. ${all.length} user(s) -> functions/export/`);
process.exit(0);
