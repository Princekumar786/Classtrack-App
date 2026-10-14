import { test } from "node:test";
import assert from "node:assert/strict";
import {
  REFERRAL_MILESTONE_DAYS,
  REFERRAL_MILESTONE_SIZE,
  MAX_REFERRAL_PRO_DAYS,
  milestonesReached,
  milestoneDaysEarned,
  milestoneDaysMissing,
  milestoneProgress,
} from "./referral.js";

test("rule is 7 days of Pro per 5 friends", () => {
  assert.equal(REFERRAL_MILESTONE_SIZE, 5);
  assert.equal(REFERRAL_MILESTONE_DAYS, 7);
});

test("milestones only count full groups of 5", () => {
  assert.equal(milestonesReached(0), 0);
  assert.equal(milestonesReached(4), 0);
  assert.equal(milestonesReached(5), 1);
  assert.equal(milestonesReached(9), 1);
  assert.equal(milestonesReached(10), 2);
  assert.equal(milestoneDaysEarned(4), 0);
  assert.equal(milestoneDaysEarned(5), 7);
  assert.equal(milestoneDaysEarned(12), 14);
});

test("missing days are earned minus granted, never negative", () => {
  assert.equal(milestoneDaysMissing(5, 0), 7); // just hit the first milestone
  assert.equal(milestoneDaysMissing(5, 7), 0); // already granted: idempotent
  assert.equal(milestoneDaysMissing(6, 7), 0); // 6th friend: no new reward
  assert.equal(milestoneDaysMissing(10, 7), 7); // second milestone
  assert.equal(milestoneDaysMissing(3, 7), 0); // over-granted: no clawback
});

test("junk input is treated as zero and grants are capped", () => {
  assert.equal(milestoneDaysMissing(NaN, 0), 0);
  assert.equal(milestoneDaysMissing(-5, 0), 0);
  assert.equal(milestoneDaysMissing(5, "x"), 7);
  assert.equal(milestoneDaysMissing(1e9, 0), MAX_REFERRAL_PRO_DAYS);
});

test("progress toward the next milestone", () => {
  assert.deepEqual(milestoneProgress(0), {
    milestonesReached: 0,
    inCycle: 0,
    toNext: 5,
  });
  assert.deepEqual(milestoneProgress(3), {
    milestonesReached: 0,
    inCycle: 3,
    toNext: 2,
  });
  assert.deepEqual(milestoneProgress(5), {
    milestonesReached: 1,
    inCycle: 0,
    toNext: 5,
  });
  assert.deepEqual(milestoneProgress(7), {
    milestonesReached: 1,
    inCycle: 2,
    toNext: 3,
  });
});
