import { test } from "node:test";
import assert from "node:assert/strict";
import { normalizeEmail, freeQuotaKey, decideFreeUse, periodKey, usedIn } from "./freeQuota.js";

test("normalizeEmail: case, whitespace and +tags collapse", () => {
  assert.equal(normalizeEmail("  Priya+scan2@Example.COM "), "priya@example.com");
});

test("normalizeEmail: Gmail dots and googlemail alias collapse", () => {
  assert.equal(normalizeEmail("p.r.i.y.a@gmail.com"), "priya@gmail.com");
  assert.equal(normalizeEmail("Priya@googlemail.com"), "priya@gmail.com");
});

test("normalizeEmail: dots are significant on other domains", () => {
  assert.equal(normalizeEmail("p.riya@college.edu"), "p.riya@college.edu");
});

test("normalizeEmail: rejects junk", () => {
  for (const bad of [null, undefined, "", "nope", "@x.com", "a@", "a@localhost", "+x@gmail.com", 42]) {
    assert.equal(normalizeEmail(bad), null, String(bad));
  }
});

test("freeQuotaKey: same person → same key; never contains the email", () => {
  const a = freeQuotaKey("priya.sharma+1@gmail.com");
  const b = freeQuotaKey("PriyaSharma@googlemail.com");
  assert.equal(a, b);
  assert.match(a, /^[0-9a-f]{64}$/);
  assert.ok(!a.includes("priya"));
  assert.notEqual(a, freeQuotaKey("someone.else@gmail.com"));
  assert.equal(freeQuotaKey("garbage"), null);
});

test("decideFreeUse: re-created account inherits the identity's usage", () => {
  // Fresh uid (0) but the email already used both scans → blocked.
  assert.deepEqual(decideFreeUse(0, 2, 2), { allowed: false, next: 2 });
});

test("decideFreeUse: legacy per-uid usage still counts", () => {
  // Identity doc doesn't exist yet, uid already used 1 → one left.
  assert.deepEqual(decideFreeUse(1, 0, 2), { allowed: true, next: 2 });
  assert.deepEqual(decideFreeUse(2, undefined, 2), { allowed: false, next: 2 });
});

test("decideFreeUse: brand-new user gets the allowance", () => {
  assert.deepEqual(decideFreeUse(undefined, undefined, 2), { allowed: true, next: 1 });
  assert.deepEqual(decideFreeUse(1, 1, 2), { allowed: true, next: 2 });
});


test("periodKey: month / day / lifetime buckets (UTC)", () => {
  const d = new Date("2026-10-02T23:30:00Z");
  assert.equal(periodKey("month", d), "2026-10");
  assert.equal(periodKey("day", d), "2026-10-02");
  assert.equal(periodKey(null, d), null);
});

test("usedIn: lifetime counts ignore periods", () => {
  assert.equal(usedIn({ parseScheduleFreeCount: 2 }, "parseScheduleFree", null), 2);
  assert.equal(usedIn(null, "parseScheduleFree", null), 0);
});

test("usedIn: monthly counts from an older month read as 0", () => {
  const data = { chatCount: 10, chatPeriod: "2026-09" };
  assert.equal(usedIn(data, "chat", "2026-09"), 10);
  assert.equal(usedIn(data, "chat", "2026-10"), 0);
});

test("chat: re-created account this month inherits the email's usage", () => {
  const identity = { chatCount: 10, chatPeriod: "2026-10" };
  const freshUid = null;
  const d = decideFreeUse(usedIn(freshUid, "chat", "2026-10"), usedIn(identity, "chat", "2026-10"), 10);
  assert.equal(d.allowed, false);
});
