/**
 * Clear generic stock hero images (Unsplash/Pexels) from `resources`.
 *
 * Some opportunities had imageUrl set to the SAME generic stock photo, which
 * cards show in preference to the brand logo — so several unrelated listings
 * displayed an identical photo. Nulling imageUrl makes the card fall back to
 * the brand logo (logoUrl). We only touch clearly-generic stock hosts.
 *
 *   node fix_stock_images.mjs         # DRY RUN
 *   node fix_stock_images.mjs --live  # apply
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
const __dirname = dirname(fileURLToPath(import.meta.url));
const LIVE = process.argv.includes("--live");

const STOCK_HOSTS = ["unsplash.com", "images.unsplash.com", "pexels.com", "images.pexels.com"];
const isStock = (u) => !!u && STOCK_HOSTS.some((h) => u.toLowerCase().includes(h));

const sa = JSON.parse(readFileSync(resolve(__dirname, "serviceAccount.json"), "utf8"));
const { initializeApp, cert } = await import("firebase-admin/app");
const { getFirestore, FieldValue } = await import("firebase-admin/firestore");
initializeApp({ credential: cert(sa) });
const db = getFirestore();
const col = db.collection("resources");

console.log(`Project: ${sa.project_id}   Mode: ${LIVE ? "LIVE WRITE" : "DRY RUN"}\n`);

const snap = await col.get();
const todo = [];
snap.forEach((d) => {
  const r = d.data();
  if (isStock(r.imageUrl)) {
    todo.push({ id: d.id, brand: r.company || r.organization, title: r.title, imageUrl: r.imageUrl, logoUrl: r.logoUrl });
  }
});

console.log(`Resources with a generic stock imageUrl: ${todo.length}\n`);
for (const t of todo.slice(0, 40)) {
  console.log(`  ${t.brand} — ${t.title}\n     drop imageUrl: ${t.imageUrl}\n     keep logo:     ${t.logoUrl || "(none)"}`);
}
if (todo.length > 40) console.log(`  … and ${todo.length - 40} more`);

if (LIVE) {
  let n = 0, batch = db.batch();
  for (const t of todo) {
    batch.set(col.doc(t.id), {
      imageUrl: null,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: "stock-image-cleanup",
    }, { merge: true });
    if (++n % 400 === 0) { await batch.commit(); batch = db.batch(); }
  }
  await batch.commit();
  console.log(`\n✓ Cleared stock imageUrl on ${n} resources (brand logo now shows).`);
} else {
  console.log(`\nDRY RUN — nothing written. Re-run with --live to apply.`);
}
process.exit(0);
