/**
 * ClassTracks CMS — targeted-notification helpers (pure, testable with
 * `node --test`, no Firebase needed).
 *
 * Targeting is topic-based. Devices subscribe to the broadcast topic `all`
 * today; per-country delivery uses `country_<slug>` topics (the mobile app
 * subscribes to its profile country's topic — an additive change tracked
 * separately). A notification with no/global country broadcasts to `all`.
 */

/** Normalizes a country to a topic slug, or null for global/unknown. */
export function slugForCountry(country) {
  if (typeof country !== "string") return null;
  const c = country.trim().toLowerCase();
  if (!c || c === "global") return null;
  return c.replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
}

/** The FCM topic to publish to for a given target country. */
export function topicForCountry(country) {
  const slug = slugForCountry(country);
  return slug ? `country_${slug}` : "all";
}

/**
 * The country a user is targeted by — the SAME rule the app uses
 * (AppUser.effectiveCountry in lib/features/auth/domain/app_user.dart): the
 * profile `country` the student chose, else the auto-`detectedCountry` from
 * their phone. "Other" in the profile defers to detection. Null when unknown.
 */
export function effectiveCountry(user) {
  if (!user || typeof user !== "object") return null;
  const clean = (v) => (typeof v === "string" && v.trim() ? v.trim() : null);
  const p = clean(user.country);
  if (p && p.toLowerCase() !== "other") return p;
  return clean(user.detectedCountry) || p;
}

/** Builds an FCM message for a topic send. Coerces data values to strings. */
export function buildFcmMessage({ title, body, topic, data }) {
  const safeData =
    data && typeof data === "object"
      ? Object.fromEntries(
          Object.entries(data).map(([k, v]) => [k, v == null ? "" : String(v)])
        )
      : {};
  return {
    topic,
    notification: {
      title: String(title || ""),
      body: String(body || ""),
    },
    data: safeData,
    android: {
      priority: "high",
      notification: { channelId: "classtrack_push" },
    },
  };
}
