import { test } from "node:test";
import assert from "node:assert/strict";
import {
  slugForCountry,
  topicForCountry,
  buildFcmMessage,
  effectiveCountry,
} from "./notifications.js";

test("effectiveCountry: profile wins, else detected (matches the app)", () => {
  assert.equal(effectiveCountry({ country: "Germany", detectedCountry: "India" }), "Germany");
  assert.equal(effectiveCountry({ detectedCountry: "India" }), "India");
  assert.equal(effectiveCountry({ country: "  ", detectedCountry: "India" }), "India");
  assert.equal(effectiveCountry({ country: "Other", detectedCountry: "India" }), "India");
  assert.equal(effectiveCountry({ country: "Other" }), "Other");
  assert.equal(effectiveCountry({}), null);
  assert.equal(effectiveCountry(null), null);
  // A detected Indian user is reached by an India-targeted CMS push.
  assert.equal(topicForCountry(effectiveCountry({ detectedCountry: "India" })), "country_india");
});

test("slugForCountry normalizes, global/null → null", () => {
  assert.equal(slugForCountry("India"), "india");
  assert.equal(slugForCountry("United States"), "united_states");
  assert.equal(slugForCountry("Global"), null);
  assert.equal(slugForCountry(""), null);
  assert.equal(slugForCountry(null), null);
});

test("topicForCountry maps to all or country_<slug>", () => {
  assert.equal(topicForCountry("India"), "country_india");
  assert.equal(topicForCountry("United Kingdom"), "country_united_kingdom");
  assert.equal(topicForCountry(null), "all");
  assert.equal(topicForCountry("Global"), "all");
});

test("buildFcmMessage shapes topic message and stringifies data", () => {
  const m = buildFcmMessage({
    title: "New AI internship",
    body: "Matches your profile",
    topic: "country_india",
    data: { payload: "resource:abc", n: 5, missing: null },
  });
  assert.equal(m.topic, "country_india");
  assert.equal(m.notification.title, "New AI internship");
  assert.equal(m.notification.body, "Matches your profile");
  assert.equal(m.data.payload, "resource:abc");
  assert.equal(m.data.n, "5");
  assert.equal(m.data.missing, "");
  assert.equal(m.android.notification.channelId, "classtrack_push");
});

test("buildFcmMessage tolerates missing fields", () => {
  const m = buildFcmMessage({ topic: "all" });
  assert.equal(m.notification.title, "");
  assert.equal(m.notification.body, "");
  assert.deepEqual(m.data, {});
});
