package com.example.task_habit_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Build
import android.view.View
import android.widget.RemoteViews

/**
 * Widget hiển thị công việc hôm nay.
 *
 * Dữ liệu do phía Flutter ghi bằng shared_preferences, nên nằm trong file
 * "FlutterSharedPreferences" với tiền tố "flutter." (xem lib/services/widget_service.dart).
 */
class TaskWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE
        )

        val headline = prefs.getString("flutter.daily_task_headline", null)
            ?: "Không có công việc nào hôm nay."
        val nextTitle = prefs.getString("flutter.daily_task_title", null)
            ?: "Chạm để mở ứng dụng và xem công việc hôm nay."
        val nextTime = prefs.getString("flutter.daily_task_next_time", "") ?: ""
        val taskList = prefs.getString("flutter.daily_task_list", "") ?: ""
        val updatedAt = prefs.getString("flutter.daily_task_updated_at", "") ?: ""

        // Chạm vào widget thì mở app
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        // FLAG_IMMUTABLE chỉ có từ API 23 trở lên
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            launchIntent,
            flags
        )

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.task_widget_layout).apply {
                setTextViewText(R.id.widget_headline, headline)
                setTextViewText(R.id.widget_task_text, nextTitle)

                setTextViewText(R.id.widget_next_time, nextTime)
                setViewVisibility(
                    R.id.widget_next_time,
                    if (nextTime.isBlank()) View.GONE else View.VISIBLE
                )

                setTextViewText(R.id.widget_task_list, taskList)
                setViewVisibility(
                    R.id.widget_task_list,
                    if (taskList.isBlank()) View.GONE else View.VISIBLE
                )

                setTextViewText(R.id.widget_updated_at, updatedAt)
                setViewVisibility(
                    R.id.widget_updated_at,
                    if (updatedAt.isBlank()) View.GONE else View.VISIBLE
                )

                setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
