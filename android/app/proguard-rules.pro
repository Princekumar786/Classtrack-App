# ProGuard / R8 rules for ClassTrack (release, R8 full mode).
#
# Philosophy: keep ONLY what reflection-heavy libraries genuinely need. The
# previous file used broad `-keep class <pkg>.** { *; }` rules for Firebase,
# Google Play Services, Play Core and the Flutter embedding. Those forced R8 to
# leave entire (very large) SDKs completely un-obfuscated and un-shrunk, which
# is exactly what dragged the Play Console DEX
# Optimization / Obfuscation / Shrinking rates below the 25% threshold.
#
# Why removing them is safe here:
#  • firebase-*, play-services-* and the Flutter tooling each ship their OWN
#    consumer ProGuard rules inside their AARs; R8 applies those automatically,
#    so a blanket app-level keep is redundant.
#  • This app maps every Firestore document MANUALLY (toMap/fromMap) — there is
#    no `toObject(MyModel.class)` reflection — so no model classes need keeping.
# The genuinely reflection-instantiated pieces (Gson-backed notifications,
# RevenueCat billing, WorkManager/Room) keep targeted rules below.

# ---------------------------------------------------------------------------
# flutter_local_notifications — Gson (de)serialisation of scheduled notifs.
# Without these, R8 strips generic TypeToken info and scheduling throws.
# ---------------------------------------------------------------------------
-keep class com.dexterous.** { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
-keepattributes Signature, *Annotation*, InnerClasses, EnclosingMethod
-dontwarn com.dexterous.**

# ---------------------------------------------------------------------------
# Firebase / Google Play Services / Play Core.
# No keeps — their AAR consumer rules cover what's needed, and Firestore data
# is mapped manually. Only silence warnings about optional/absent references so
# R8 is free to obfuscate + shrink the unused surface (the main score win).
# ---------------------------------------------------------------------------
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
-dontwarn com.google.android.play.core.**

# ---------------------------------------------------------------------------
# RevenueCat (purchases_flutter).
# Billing must never break; the SDK is small relative to Firebase/GMS, so keep
# it intact rather than risk a shrink stripping a reflectively-used model.
# ---------------------------------------------------------------------------
-keep class com.revenuecat.purchases.** { *; }
-dontwarn com.revenuecat.purchases.**

# ---------------------------------------------------------------------------
# PostHog. The AAR ships its own consumer ProGuard rules, so no blanket keep is
# needed (letting R8 shrink/obfuscate the unused surface keeps the Play score
# up). Just silence warnings about optional transitive references.
# ---------------------------------------------------------------------------
-dontwarn com.posthog.**

# ---------------------------------------------------------------------------
# WorkManager + Room (pulled in by home_widget). WorkManager's Room-backed
# WorkDatabase is instantiated by REFLECTION at launch via the
# WorkManagerInitializer ContentProvider. Keep only the reflectively-created
# entry points — the generated *_Impl DB classes and Worker/RoomDatabase
# constructors — so R8 can still shrink/obfuscate the rest of these packages.
# (This is what actually prevents the "Failed to create an instance of
# androidx.work.impl.WorkDatabase" launch crash; the old blanket keeps were
# broader than necessary.)
# ---------------------------------------------------------------------------
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class * extends androidx.work.ListenableWorker { <init>(...); }
-keep class * extends androidx.work.Worker
-keep class androidx.work.impl.WorkDatabase_Impl { <init>(); }
-keepclassmembers class * extends androidx.room.RoomDatabase {
  public static ** getInstance(...);
}
-dontwarn androidx.work.**
-dontwarn androidx.room.**
