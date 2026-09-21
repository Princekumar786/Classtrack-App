/**
 * Publish DRAFT opportunities (non-discount resources) that are available now.
 *
 *   - Availability: skip anything whose deadline has already passed
 *     ("not available right now"); publish the rest as `active`.
 *   - Country filter: the resource's existing `countries` targeting is kept
 *     as-is (region-locked ones stay locked, global stay global) — so a user
 *     only sees an opportunity available in their country.
 *   - Dedupe: within drafts AND against already-visible opportunities, by
 *     normalized brand+title and by destination URL.
 *   - Dead links: skip genuinely-dead links (DNS fail / 404 / 410 / 522);
 *     bot-blocked hosts (403/429/timeout) are treated as alive.
 *   - Date priority: sooner deadline → higher `priority` (surfaces first);
 *     evergreen (no deadline) → base priority 0.
 *
 *   node publish_opportunities.mjs           # DRY RUN
 *   node publish_opportunities.mjs --live     # apply
 *   node publish_opportunities.mjs --no-http  # skip link checks
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const LIVE = process.argv.includes("--live");
const NO_HTTP = process.argv.includes("--no-http");
const now = new Date();

const norm = (s) => (s || "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "");
const dedupeKey = (r) => `${norm(r.organization || r.company)}|${norm(r.title)}`;

const DEAD_STATUS = new Set([404, 410, 451, 522, 523, 525, 530]);
async function checkUrl(url) {
  if (!url) return { dead: true, reason: "no link" };
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), 15000);
  try {
    const res = await fetch(url, {
      method: "GET", redirect: "follow", signal: ac.signal,
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,*/*;q=0.8",
      },
    });
    if (DEAD_STATUS.has(res.status)) return { dead: true, reason: `HTTP ${res.status}` };
    return { dead: false, reason: `HTTP ${res.status}` };
  } catch (e) {
    const timedOut = String(e.name || e).includes("Abort");
    return timedOut ? { dead: false, reason: "timeout(assumed alive)" } : { dead: true, reason: "DNS/conn fail" };
  } finally {
    clearTimeout(t);
  }
}
async function mapPool(items, size, fn) {
  const out = new Array(items.length);
  let i = 0;
  const worker = async () => { while (i < items.length) { const idx = i++; out[idx] = await fn(items[idx], idx); } };
  await Promise.all(Array.from({ length: Math.min(size, items.length) }, worker));
  return out;
}

function priorityFor(deadline) {
  if (!deadline) return 0;
  const days = Math.ceil((deadline - now) / 86400000);
  if (days < 0) return 0;
  return Math.max(1, 1000 - Math.min(days, 999)); // sooner deadline → higher
}

const sa = JSON.parse(readFileSync(resolve(__dirname, "serviceAccount.json"), "utf8"));
const { initializeApp, cert } = await import("firebase-admin/app");
const { getFirestore, FieldValue } = await import("firebase-admin/firestore");
initializeApp({ credential: cert(sa) });
const db = getFirestore();
const col = db.collection("resources");

console.log(`Project: ${sa.project_id}   Mode: ${LIVE ? "LIVE WRITE" : "DRY RUN"}${NO_HTTP ? " (no-http)" : ""}\n`);

const snap = await col.get();
const drafts = [];
const publishedOpps = [];
snap.forEach((d) => {
  const r = { id: d.id, ...d.data() };
  if (r.type === "discount") return;
  if (r.status === "draft") drafts.push(r);
  else if (r.status !== "hidden" && r.status !== "archived") publishedOpps.push(r);
});
drafts.sort((a, b) => (a.id < b.id ? -1 : 1));

const link = (r) => r.applicationUrl || r.affiliateUrl || "";
const linkResults = NO_HTTP
  ? drafts.map(() => ({ dead: false, reason: "skipped" }))
  : await (async () => {
      process.stdout.write(`Checking ${drafts.length} links…`);
      const res = await mapPool(drafts.map(link), 12, (u) => checkUrl(u));
      process.stdout.write(" done\n");
      return res;
    })();

const publishedKeys = new Set(publishedOpps.map(dedupeKey));
const publishedUrls = new Set(publishedOpps.map((r) => norm(link(r))));
const seenKeys = new Set();
const seenUrls = new Set();

const decisions = drafts.map((r, i) => {
  const reasons = [];
  const dl = r.deadline?.toDate ? r.deadline.toDate() : null;

  // availability
  if (dl && dl < now) reasons.push(`expired:${dl.toISOString().slice(0, 10)}`);

  // dedupe
  const key = dedupeKey(r);
  const u = norm(link(r));
  if (publishedKeys.has(key)) reasons.push("dedupe:already-live");
  else if (seenKeys.has(key)) reasons.push("dedupe:dup-title");
  else seenKeys.add(key);
  if (u) {
    if (publishedUrls.has(u) || seenUrls.has(u)) reasons.push("dedupe:same-url");
    else seenUrls.add(u);
  }

  // link
  if (!link(r)) reasons.push("no-link");
  else if (linkResults[i].dead) reasons.push(`link-dead:${linkResults[i].reason}`);

  const willPublish = reasons.length === 0;
  return {
    id: r.id, type: r.type, title: r.title, org: r.organization,
    deadline: dl ? dl.toISOString().slice(0, 10) : null,
    countries: (r.countries || []).join("/") || "(global)",
    priority: priorityFor(dl),
    willPublish, reasons,
  };
});

const pub = decisions.filter((d) => d.willPublish);
const skip = decisions.filter((d) => !d.willPublish);
const countBy = (arr, f) => arr.reduce((m, x) => { const k = f(x); m[k] = (m[k] || 0) + 1; return m; }, {});

console.log(`\n══════ SUMMARY ══════`);
console.log(`Draft opportunities : ${drafts.length}   Already-visible : ${publishedOpps.length}`);
console.log(`Would PUBLISH : ${pub.length}`);
console.log(`Would SKIP    : ${skip.length}`);
console.log(`  reasons:`, JSON.stringify(countBy(skip, (d) => d.reasons[0])));

const show = (title, arr) => {
  console.log(`\n── ${title} (${arr.length}) ──`);
  for (const d of arr)
    console.log(`  [${d.type}] ${d.org} — ${d.title} | ${d.countries} | deadline=${d.deadline || "—"} | prio=${d.priority}${d.reasons.length ? "  → " + d.reasons.join(", ") : ""}`);
};
show("PUBLISH", pub);
show("SKIP", skip);

if (LIVE) {
  let n = 0, batch = db.batch();
  for (const d of pub) {
    batch.set(col.doc(d.id), {
      status: "active",
      priority: d.priority,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: "opps-publish",
      publishedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    if (++n % 400 === 0) { await batch.commit(); batch = db.batch(); }
  }
  await batch.commit();
  console.log(`\n✓ Published ${n} opportunities (status=active, date priority set).`);
} else {
  console.log(`\nDRY RUN — nothing written. Re-run with --live to publish.`);
}
process.exit(0);
