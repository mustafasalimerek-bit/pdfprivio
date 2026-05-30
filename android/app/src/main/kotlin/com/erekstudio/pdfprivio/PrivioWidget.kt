package com.erekstudio.pdfprivio

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.state.getAppWidgetState
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.state.GlanceStateDefinition
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.stringPreferencesKey
import org.json.JSONObject

/**
 * Glance home-screen widget that mirrors the iOS WidgetKit extension —
 * shows the top three Privio recent files (tool label + relative time)
 * with the same cream / teal brand palette as the rest of the app.
 *
 * Data flow: WidgetDataService on the Dart side writes a JSON blob via
 * `HomeWidget.saveWidgetData("recent_files_json", ...)`. The
 * `home_widget` package stores that under the shared HomeWidget
 * SharedPreferences file; this widget reads it through the same key
 * via Glance's PreferencesGlanceStateDefinition so updates flow
 * without a separate IPC channel.
 *
 * Tapping the widget opens the Privio app on the Recent tab via the
 * `privio://tab/recent` deep link declared in AndroidManifest.
 */
class PrivioWidget : GlanceAppWidget() {

    override val stateDefinition: GlanceStateDefinition<*> =
        PreferencesGlanceStateDefinition

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        // Read the SharedPreferences-backed Glance state up-front rather
        // than via `currentState<Preferences>()` inside the composable.
        // Kotlin 2.x JVM backend currently fails to inline that generic
        // call ("Couldn't inline method call currentState"); passing the
        // payload as a parameter sidesteps the bug and keeps the
        // composable pure.
        val prefs = getAppWidgetState(context, PreferencesGlanceStateDefinition, id)
                as Preferences
        val payload = prefs[stringPreferencesKey(KEY_PAYLOAD)]

        provideContent {
            GlanceTheme {
                WidgetBody(payload)
            }
        }
    }

    @Composable
    private fun WidgetBody(payload: String?) {
        val files = parsePayload(payload)

        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(BG_CREAM)
                .padding(12.dp)
                .clickable(
                    actionStartActivity<MainActivity>()
                ),
        ) {
            HeaderRow(count = files.size)
            Spacer(modifier = GlanceModifier.height(8.dp))

            if (files.isEmpty()) {
                EmptyState()
            } else {
                files.take(MAX_ROWS).forEach { file ->
                    FileRow(file)
                    Spacer(modifier = GlanceModifier.height(6.dp))
                }
            }
        }
    }

    @Composable
    private fun HeaderRow(count: Int) {
        Row(
            modifier = GlanceModifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "Privio",
                style = TextStyle(
                    color = cp(TEAL_PRIMARY),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                ),
            )
            Spacer(modifier = GlanceModifier.width(8.dp))
            Text(
                text = if (count == 0) "Recent" else "Recent · $count",
                style = TextStyle(
                    color = cp(TEXT_MUTED),
                    fontSize = 11.sp,
                ),
            )
        }
    }

    @Composable
    private fun FileRow(file: RecentFile) {
        Row(
            modifier = GlanceModifier
                .fillMaxWidth()
                .background(SURFACE)
                .cornerRadius(8.dp)
                .padding(horizontal = 10.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Tool icon placeholder — small teal square. A drawable
            // resource per tool can replace this in a follow-up pass.
            Box(
                modifier = GlanceModifier
                    .size(20.dp)
                    .background(TEAL_PRIMARY)
                    .cornerRadius(4.dp),
            ) {}
            Spacer(modifier = GlanceModifier.width(10.dp))
            Column(modifier = GlanceModifier.fillMaxWidth()) {
                Text(
                    text = if (file.name.isBlank()) file.tool else file.name,
                    maxLines = 1,
                    style = TextStyle(
                        color = cp(TEXT_PRIMARY),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                )
                Text(
                    text = "${file.tool} · ${relativeTime(file.openedAtMs)}",
                    maxLines = 1,
                    style = TextStyle(
                        color = cp(TEXT_MUTED),
                        fontSize = 10.sp,
                    ),
                )
            }
        }
    }

    @Composable
    private fun EmptyState() {
        Column(
            modifier = GlanceModifier.fillMaxSize(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = "Open Privio to start",
                style = TextStyle(
                    color = cp(TEXT_MUTED),
                    fontSize = 12.sp,
                ),
            )
        }
    }

    // --- Parsing ----------------------------------------------------------

    private data class RecentFile(
        val name: String,
        val tool: String,
        val openedAtMs: Long,
    )

    /** Parse the JSON blob that WidgetDataService publishes. Tolerant —
     *  any malformed entry is dropped so a single bad record does not
     *  wipe the widget. */
    private fun parsePayload(payload: String?): List<RecentFile> {
        if (payload.isNullOrBlank()) return emptyList()
        return try {
            val root = JSONObject(payload)
            val arr = root.optJSONArray("files") ?: return emptyList()
            val out = mutableListOf<RecentFile>()
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                out += RecentFile(
                    name = obj.optString("name", ""),
                    tool = obj.optString("tool", "—"),
                    openedAtMs = obj.optLong("openedAtMs", 0L),
                )
            }
            out
        } catch (_: Throwable) {
            emptyList()
        }
    }

    private fun relativeTime(openedAtMs: Long): String {
        if (openedAtMs <= 0L) return ""
        val deltaMs = System.currentTimeMillis() - openedAtMs
        val minutes = deltaMs / 60_000
        if (minutes < 1) return "just now"
        if (minutes < 60) return "${minutes}m ago"
        val hours = minutes / 60
        if (hours < 24) return "${hours}h ago"
        val days = hours / 24
        if (days < 7) return "${days}d ago"
        val weeks = days / 7
        if (weeks < 4) return "${weeks}w ago"
        return "${days / 30}mo ago"
    }

    companion object {
        // Brand palette — mirrors AppColors on the Dart side.
        private val BG_CREAM = Color(0xFFFAF3E7)
        private val SURFACE = Color(0xFFFFFFFF)
        private val TEAL_PRIMARY = Color(0xFF0F766E)
        private val TEXT_PRIMARY = Color(0xFF1F2937)
        private val TEXT_MUTED = Color(0xFF5C6B6B)

        /** Day = night for now — widget keeps the cream/teal brand
         *  identity even in system dark mode. A v1.1 dark-aware palette
         *  can swap this for distinct night colors. Return type
         *  inferred to dodge the `ColorProvider` interface vs factory-
         *  function name clash. */
        private fun cp(color: Color) =
            ColorProvider(day = color, night = color)

        private const val MAX_ROWS = 3

        // home_widget stores entries under this prefix in SharedPreferences;
        // WidgetDataService writes the JSON blob under the bare key
        // "recent_files_json". `PreferencesGlanceStateDefinition` reads
        // from the AndroidX DataStore variant that home_widget already
        // mirrors into, so the bare key is the one to look up.
        private const val KEY_PAYLOAD = "recent_files_json"
    }
}
