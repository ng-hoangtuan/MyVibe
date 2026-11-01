package com.example.task_habit_app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews

class TaskWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val taskTitle = prefs.getString(
                "flutter.daily_task_title",
                "Không có công việc nào hôm nay."
            ) ?: "Không có công việc nào hôm nay."

            val views = RemoteViews(context.packageName, R.layout.task_widget_layout).apply {
                setTextViewText(R.id.widget_task_text, taskTitle)
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
