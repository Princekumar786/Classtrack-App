/**
 * Fix inaccurate auto-generated discount content.
 *
 * The old template asserted "Students pay a reduced rate of {X}" for every
 * discount — which is FALSE for free offers (e.g. Dify "$708/year(Free)",
 * Kiro) and mislabels products. This rewrites every discount `description` to
 * an accurate, neutral form that makes no invented price claim and defers
 * specifics to the official page. It also normalizes clearly-FREE offer
 * headlines (discountText) — the "(Free)" ones + an explicit free list.
 *
 *   node fix_descriptions.mjs         # DRY RUN
 *   node fix_descriptions.mjs --live  # apply
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
const __dirname = dirname(fileURLToPath(import.meta.url));
const LIVE = process.argv.includes("--live");

// Titles the user confirmed are FREE for students.
const FREE_TITLES = new Set([
  "Kiro AI Code Editor for Students",
  "Dify Education Plan",
]);

const displayName = (r) => (r.company || r.organization || r.title || "this brand").trim();

/** Accurate, neutral description — no invented price/plan claims. */
function newDescription(r) {
  const n = displayName(r);
  return (
    `${n} offers an exclusive student discount. You'll need to verify that ` +
    `you're a currently enrolled student to unlock it.\n\n` +
    `The exact plan, savings and eligibility are set by ${n} and can vary by ` +
    `country, so open the official student page (linked on this listing) for ` +
    `the current offer and to redeem.`
  );
}

/** Is the stored offer text clearly a FREE-for-students offer? */
function isFreeOffer(r) {
  if (FREE_TITLES.has(r.title)) return true;
  const s = (r.discountText || "").toLowerCase();
  return s.includes("(free)");
}

const sa = JSON.parse(readFileSync(resolve(__dirname, "serviceAccount.json"), "utf8"));
const { initializeApp, cert } = await import("firebase-admin/app");
const { getFirestore, FieldValue } = await import("firebase-admin/firestore");
initializeApp({ credential: cert(sa) });
const db = getFirestore();
const col = db.collection("resources");

console.log(`Project: ${sa.project_id}   Mode: ${LIVE ? "LIVE WRITE" : "DRY RUN"}\n`);

const snap = await col.where("type", "==", "discount").get();
const updates = [];
snap.forEach((d) => {
  const r = { id: d.id, ...d.data() };
  const u = { description: newDescription(r) };
  if (isFreeOffer(r) && r.discountText !== "Free for students") {
    u.discountText = "Free for students";
  }
  updates.push({ r, u });
});

const offerFixes = updates.filter((x) => x.u.discountText);
console.log(`Discounts: ${updates.length}`);
console.log(`Descriptions rewritten : ${updates.length}`);
console.log(`Offer headlines set to "Free for students" : ${offerFixes.length}`);
offerFixes.forEach((x) => console.log(`  ${x.r.company || x.r.organization} — ${x.r.title}: "${x.r.discountText}" → "Free for students"`));

console.log(`\nSample rewritten description (Kiro):`);
const kiro = updates.find((x) => x.r.title.includes("Kiro"));
if (kiro) console.log(`  discountText: ${kiro.u.discountText || kiro.r.discountText}\n  ${kiro.u.description.replace(/\n\n/g, "\n  ")}`);

// Ambiguous headlines (still a bare price/credit) the user may want to verify.
const ambiguous = updates.filter((x) => !x.u.discountText &&
  /\$|€|£|¥|\/year|\/mo|credit|value|over \d/i.test(x.r.discountText || ""));
console.log(`\nOffer headlines left unchanged that look like a specific amount (verify these): ${ambiguous.length}`);
for (const x of ambiguous.slice(0, 40)) console.log(`  ${x.r.company || x.r.organization} — ${x.r.title}: "${x.r.discountText}"`);
if (ambiguous.length > 40) console.log(`  … and ${ambiguous.length - 40} more`);

if (LIVE) {
  let n = 0, batch = db.batch();
  for (const { r, u } of updates) {
    batch.set(col.doc(r.id), { ...u, updatedAt: FieldValue.serverTimestamp(), updatedBy: "desc-fix" }, { merge: true });
    if (++n % 400 === 0) { await batch.commit(); batch = db.batch(); }
  }
  await batch.commit();
  console.log(`\n✓ Updated ${n} discounts (accurate descriptions; free offers normalized).`);
} else {
  console.log(`\nDRY RUN — nothing written. Re-run with --live to apply.`);
}
process.exit(0);
