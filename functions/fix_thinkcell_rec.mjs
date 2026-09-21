/**
 * One-off: make Think-cell eligible for the recommended (home) feed.
 * Sets recommendationEligible=true on the Think-cell ambassador resource.
 *
 *   node fix_thinkcell_rec.mjs           # DRY RUN
 *   node fix_thinkcell_rec.mjs --live    # apply
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const LIVE = process.argv.includes("--live");
const sa = JSON.parse(readFileSync(resolve(__dirname, "serviceAccount.json"), "utf8"));
const { initializeApp, cert } = await import("firebase-admin/app");
const { getFirestore, FieldValue } = await import("firebase-admin/firestore");
initializeApp({ credential: cert(sa) });
const db = getFirestore();
const col = db.collection("resources");

// Match by title (case-insensitive) among ambassador resources.
const snap = await col.where("type", "==", "ambassador").get();
const targets = [];
snap.forEach((d) => {
  const r = d.data();
  if ((r.title || "").toLowerCase().includes("think-cell") ||
      (r.organization || "").toLowerCase().includes("think-cell")) {
    targets.push({ id: d.id, title: r.title, current: r.recommendationEligible });
  }
});

console.log(`Project: ${sa.project_id}   Mode: ${LIVE ? "LIVE WRITE" : "DRY RUN"}`);
console.log(`Matched ${targets.length} doc(s):`);
for (const t of targets) console.log(`  ${t.id} — ${t.title} (recommendationEligible=${t.current})`);

if (targets.length === 0) { console.log("Nothing to update."); process.exit(0); }

if (LIVE) {
  const batch = db.batch();
  for (const t of targets) {
    batch.set(col.doc(t.id), {
      recommendationEligible: true,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: "fix-thinkcell-rec",
    }, { merge: true });
  }
  await batch.commit();
  console.log(`\n\u2713 Set recommendationEligible=true on ${targets.length} doc(s).`);
} else {
  console.log(`\nDRY RUN \u2014 nothing written. Re-run with --live to apply.`);
}
process.exit(0);
