/**
 * Referral reward rules (pure, unit-tested in referral.test.js).
 *
 *  • The INVITER earns MILESTONE_DAYS of Pro for every MILESTONE_SIZE friends
 *    who join with their code (5 friends → 7 days, 10 → 14 days, …).
 *  • The FRIEND who redeems a code gets WELCOME_DAYS once, as a welcome gift.
 *
 * Milestone days are tracked in their own running total
 * (`referralMilestoneDaysGranted`) so the reconcile step is idempotent and
 * never touches days granted under the old "3 days per invite" scheme.
 */

export const REFERRAL_MILESTONE_SIZE = 5;
export const REFERRAL_MILESTONE_DAYS = 7;
export const REFERRAL_WELCOME_DAYS = 3;

/** Hard ceiling on what a reconcile may ever grant in one go (10 years). */
export const MAX_REFERRAL_PRO_DAYS = 3650;

/** Non-negative whole number, or 0 for junk. */
export function safeCount(v) {
  return Number.isFinite(v) ? Math.max(0, Math.floor(v)) : 0;
}

/** Completed milestones for an invite count (5 → 1, 9 → 1, 10 → 2). */
export function milestonesReached(count) {
  return Math.floor(safeCount(count) / REFERRAL_MILESTONE_SIZE);
}

/** Total milestone Pro days earned by an invite count. */
export function milestoneDaysEarned(count) {
  return milestonesReached(count) * REFERRAL_MILESTONE_DAYS;
}

/**
 * Milestone days still owed: earned minus already granted, clamped to
 * [0, MAX_REFERRAL_PRO_DAYS] so a data glitch can never mint absurd Pro.
 */
export function milestoneDaysMissing(count, granted) {
  const missing = milestoneDaysEarned(count) - safeCount(granted);
  return Math.min(Math.max(0, missing), MAX_REFERRAL_PRO_DAYS);
}

/** Progress toward the next milestone, for the referral screen. */
export function milestoneProgress(count) {
  const c = safeCount(count);
  const inCycle = c % REFERRAL_MILESTONE_SIZE;
  return {
    milestonesReached: milestonesReached(c),
    inCycle,
    toNext: REFERRAL_MILESTONE_SIZE - inCycle,
  };
}
