package com.erekstudio.pdfprivio

import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver

/**
 * The classic AppWidgetReceiver Android needs to hand widget lifecycle
 * events to Glance. Just a thin wrapper that points at [PrivioWidget];
 * Glance itself does all the rendering and update plumbing.
 *
 * Wired in AndroidManifest as a <receiver> with the
 * AppWidgetProvider intent-filter and a meta-data pointer to
 * @xml/privio_widget_info.
 */
class PrivioWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = PrivioWidget()
}
