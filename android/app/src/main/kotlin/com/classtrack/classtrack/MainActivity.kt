package com.classtrack.classtrack

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// When ClassTrack is relaunched from the Recents screen (or the launcher)
/// after having once been started by a "share" (ACTION_SEND) intent, Android
/// re-delivers that ORIGINAL send intent. The receive_sharing_intent plugin
/// then re-emits the same shared link on every launch, so the "New item" sheet
/// kept reopening with the previously shared URL.
///
/// Android marks such relaunches with FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY. When
/// we see that flag we neutralise the intent (drop its action / data / extras)
/// so a historical relaunch is treated as a plain app open and the stale share
/// is never processed again.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Country detection for targeting (opportunities + CMS pushes). Reads
        // the SIM / mobile-network country — no permission, no location.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "classtrack/country")
            .setMethodCallHandler { call, result ->
                if (call.method == "getTelephonyCountry") {
                    result.success(telephonyCountries())
                } else {
                    result.notImplemented()
                }
            }
    }

    /// ISO 3166 alpha-2 codes (lower-case, may be empty) for the SIM and the
    /// network the phone is on. Never throws: missing telephony → empty map.
    private fun telephonyCountries(): Map<String, String> {
        return try {
            val tm = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                ?: return emptyMap()
            mapOf(
                "sim" to (tm.simCountryIso ?: ""),
                "network" to (tm.networkCountryIso ?: ""),
            )
        } catch (_: Exception) {
            emptyMap()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        clearIntentIfFromHistory(intent)?.let { setIntent(it) }
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        val cleaned = clearIntentIfFromHistory(intent)
        if (cleaned != null) setIntent(cleaned)
        super.onNewIntent(cleaned ?: intent)
    }

    /// Returns a neutralised copy of [intent] when it was re-delivered from the
    /// Recents/history stack, or null when the intent is a genuine, fresh one
    /// that should be handled normally.
    private fun clearIntentIfFromHistory(intent: Intent?): Intent? {
        if (intent == null) return null
        val fromHistory =
            (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
        if (!fromHistory) return null
        return Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
            setPackage(packageName)
        }
    }
}
