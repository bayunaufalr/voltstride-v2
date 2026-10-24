package com.example.voltstride

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Alarm reminder yang tetap tampil sampai pengguna menekan tombol Selesai. */
class ReminderPulseReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> restoreSchedules(context)
            ACTION_COMPLETE -> completeOccurrence(context, intent)
            ACTION_REPEAT -> repeatOccurrence(context, intent)
            ACTION_START -> startOccurrence(context, intent)
        }
    }

    companion object {
        const val ACTION_START = "com.example.voltstride.REMINDER_START"
        const val ACTION_REPEAT = "com.example.voltstride.REMINDER_REPEAT"
        const val ACTION_COMPLETE = "com.example.voltstride.REMINDER_COMPLETE"

        private const val PREFERENCES = "VoltStrideReminderPulse"
        private const val FLUTTER_PREFERENCES = "FlutterSharedPreferences"
        private const val FLUTTER_REMINDERS_KEY = "flutter.voltstride_training_reminders_v1"
        private const val CHANNEL_ID = "voltstride_training_pulse_v8"
        private const val START_REQUEST_BASE = 510000
        private const val REPEAT_REQUEST_BASE = 610000
        private const val COMPLETE_REQUEST_BASE = 710000
        private const val NOTIFICATION_BASE = 810000
        private const val EXTRA_ID = "reminderId"
        private const val EXTRA_START_AT = "occurrenceStartAt"

        fun schedule(
            context: Context,
            id: Int,
            title: String,
            category: String,
            weekdays: List<Int>,
            hour: Int,
            minute: Int,
            durationMinutes: Int,
            repeatIntervalSeconds: Int,
            doneLabel: String,
            bodyLabel: String,
        ) {
            val safeDays = weekdays.distinct().filter { it in 1..7 }.sorted()
            require(safeDays.isNotEmpty()) { "Pilih setidaknya satu hari." }
            val config = JSONObject().apply {
                put("id", id)
                put("title", title)
                put("category", category)
                put("weekdays", JSONArray(safeDays))
                put("hour", hour.coerceIn(0, 23))
                put("minute", minute.coerceIn(0, 59))
                put("durationMinutes", durationMinutes.coerceIn(5, 360))
                put("repeatIntervalSeconds", repeatIntervalSeconds.coerceIn(30, 600))
                put("doneLabel", doneLabel)
                put("bodyLabel", bodyLabel)
            }
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .edit().putString(scheduleKey(id), config.toString()).apply()
            cancelAlarms(context, id)
            scheduleNextStart(context, id, System.currentTimeMillis())
        }

        fun cancel(context: Context, id: Int) {
            cancelAlarms(context, id)
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .edit()
                .remove(scheduleKey(id))
                .remove(activeStartKey(id))
                .remove(activeEndKey(id))
                .apply()
            notificationManager(context).cancel(NOTIFICATION_BASE + id)
        }

        private fun scheduleKey(id: Int) = "schedule_$id"
        private fun activeStartKey(id: Int) = "active_start_$id"
        private fun activeEndKey(id: Int) = "active_end_$id"

        private fun preferences(context: Context) =
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

        private fun loadConfig(context: Context, id: Int): JSONObject? = try {
            preferences(context).getString(scheduleKey(id), null)?.let(::JSONObject)
        } catch (_: Exception) {
            null
        }

        private fun restoreSchedules(context: Context) {
            val stored = preferences(context).all
            val now = System.currentTimeMillis()
            stored.keys.filter { it.startsWith("schedule_") }.forEach { key ->
                val id = key.removePrefix("schedule_").toIntOrNull() ?: return@forEach
                val config = loadConfig(context, id) ?: return@forEach
                val activeStart = preferences(context).getLong(activeStartKey(id), 0L)
                val activeEnd = preferences(context).getLong(activeEndKey(id), 0L)
                if (activeStart > 0L) {
                    // Pulihkan notifikasi aktif setelah reboot. Jika durasi masih berjalan,
                    // lanjutkan pulse dari waktu sekarang; jika sudah habis, notifikasi
                    // tetap menunggu tombol Selesai tanpa mengirim pulse baru.
                    showReminder(context, id, config, activeStart)
                    if (activeEnd > now) {
                        scheduleNextPulse(
                            context,
                            id,
                            activeStart,
                            activeEnd,
                            config.optInt("repeatIntervalSeconds", 60),
                        )
                    }
                }
                scheduleNextStart(context, id, maxOf(now, activeEnd))
            }
        }

        private fun scheduleNextStart(context: Context, id: Int, afterMillis: Long) {
            val config = loadConfig(context, id) ?: return
            val startAt = nextOccurrence(config, afterMillis) ?: return
            val intent = Intent(context, ReminderPulseReceiver::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_ID, id)
                putExtra(EXTRA_START_AT, startAt)
            }
            val pending = PendingIntent.getBroadcast(
                context,
                START_REQUEST_BASE + id,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, startAt, pending)
            } else {
                alarmManager.set(AlarmManager.RTC_WAKEUP, startAt, pending)
            }
        }

        private fun nextOccurrence(config: JSONObject, afterMillis: Long): Long? {
            val days = config.optJSONArray("weekdays") ?: return null
            if (days.length() == 0) return null
            val selected = (0 until days.length()).map { days.optInt(it) }.toSet()
            val hour = config.optInt("hour", 7)
            val minute = config.optInt("minute", 0)
            val calendar = Calendar.getInstance(TimeZone.getTimeZone("Asia/Jakarta"), Locale.US)
            calendar.timeInMillis = afterMillis
            calendar.set(Calendar.SECOND, 0)
            calendar.set(Calendar.MILLISECOND, 0)
            for (offset in 0..7) {
                val candidate = calendar.clone() as Calendar
                candidate.add(Calendar.DAY_OF_YEAR, offset)
                candidate.set(Calendar.HOUR_OF_DAY, hour)
                candidate.set(Calendar.MINUTE, minute)
                val flutterWeekday = when (candidate.get(Calendar.DAY_OF_WEEK)) {
                    Calendar.MONDAY -> 1
                    Calendar.TUESDAY -> 2
                    Calendar.WEDNESDAY -> 3
                    Calendar.THURSDAY -> 4
                    Calendar.FRIDAY -> 5
                    Calendar.SATURDAY -> 6
                    else -> 7
                }
                if (flutterWeekday in selected && candidate.timeInMillis > afterMillis) {
                    return candidate.timeInMillis
                }
            }
            return null
        }

        private fun startOccurrence(context: Context, intent: Intent) {
            val id = intent.getIntExtra(EXTRA_ID, -1)
            if (id < 0) return
            val config = loadConfig(context, id) ?: return
            val startAt = intent.getLongExtra(EXTRA_START_AT, System.currentTimeMillis())
            val durationMillis = config.optLong("durationMinutes", 30) * 60_000L
            val endAt = startAt + durationMillis
            preferences(context).edit()
                .putLong(activeStartKey(id), startAt)
                .putLong(activeEndKey(id), endAt)
                .apply()

            // Jadwalkan kejadian mingguan berikutnya secara terpisah dari pulse sesi ini.
            scheduleNextStart(context, id, endAt + 1000L)
            showReminder(context, id, config, startAt)
            scheduleNextPulse(context, id, startAt, endAt, config.optInt("repeatIntervalSeconds", 60))
        }

        private fun repeatOccurrence(context: Context, intent: Intent) {
            val id = intent.getIntExtra(EXTRA_ID, -1)
            if (id < 0) return
            val config = loadConfig(context, id) ?: return
            val startAt = intent.getLongExtra(EXTRA_START_AT, 0L)
            val prefs = preferences(context)
            if (prefs.getLong(activeStartKey(id), 0L) != startAt) return
            val endAt = prefs.getLong(activeEndKey(id), 0L)
            val now = System.currentTimeMillis()
            if (endAt <= 0L || now >= endAt) return
            showReminder(context, id, config, startAt)
            scheduleNextPulse(context, id, startAt, endAt, config.optInt("repeatIntervalSeconds", 60))
        }

        private fun scheduleNextPulse(
            context: Context,
            id: Int,
            startAt: Long,
            endAt: Long,
            intervalSeconds: Int,
        ) {
            val nextAt = System.currentTimeMillis() + intervalSeconds.coerceIn(30, 600) * 1000L
            if (nextAt >= endAt) return
            val intent = Intent(context, ReminderPulseReceiver::class.java).apply {
                action = ACTION_REPEAT
                putExtra(EXTRA_ID, id)
                putExtra(EXTRA_START_AT, startAt)
            }
            val pending = PendingIntent.getBroadcast(
                context,
                REPEAT_REQUEST_BASE + id,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, nextAt, pending)
            } else {
                alarms.set(AlarmManager.RTC_WAKEUP, nextAt, pending)
            }
        }

        private fun showReminder(context: Context, id: Int, config: JSONObject, startAt: Long) {
            createNotificationChannel(context)
            val title = config.optString("title", "Latihan")
            val category = config.optString("category", "Lari")
            val duration = config.optInt("durationMinutes", 30)
            val interval = config.optInt("repeatIntervalSeconds", 60)
            val english = config.optString("doneLabel", "Selesai") == "Done"
            val body = if (english) {
                "$category · $duration min · repeats every $interval sec"
            } else {
                "$category · $duration menit · diulang setiap $interval detik"
            }
            val doneIntent = Intent(context, ReminderPulseReceiver::class.java).apply {
                action = ACTION_COMPLETE
                putExtra(EXTRA_ID, id)
                putExtra(EXTRA_START_AT, startAt)
            }
            val donePending = PendingIntent.getBroadcast(
                context,
                COMPLETE_REQUEST_BASE + id,
                doneIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val notification = Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setCategory(Notification.CATEGORY_REMINDER)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setPriority(Notification.PRIORITY_MAX)
                .setWhen(startAt)
                .setOngoing(true)
                .setAutoCancel(false)
                .setOnlyAlertOnce(false)
                .setDefaults(Notification.DEFAULT_ALL)
                .addAction(android.R.drawable.ic_menu_save, config.optString("doneLabel", "Selesai"), donePending)
                .build()
            // FLAG_NO_CLEAR memastikan notifikasi tidak terhapus dari tombol hapus semua.
            // Tombol aksi Selesai tetap menjadi jalur normal untuk menutup notifikasi.
            notification.flags = notification.flags or
                Notification.FLAG_NO_CLEAR or Notification.FLAG_ONGOING_EVENT
            notificationManager(context).notify(NOTIFICATION_BASE + id, notification)
        }

        private fun completeOccurrence(context: Context, intent: Intent) {
            val id = intent.getIntExtra(EXTRA_ID, -1)
            if (id < 0) return
            val startAt = intent.getLongExtra(EXTRA_START_AT, 0L)
            val prefs = preferences(context)
            if (prefs.getLong(activeStartKey(id), 0L) == startAt) {
                prefs.edit().remove(activeStartKey(id)).remove(activeEndKey(id)).apply()
            }
            val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val repeatIntent = Intent(context, ReminderPulseReceiver::class.java).apply {
                action = ACTION_REPEAT
                putExtra(EXTRA_ID, id)
                putExtra(EXTRA_START_AT, startAt)
            }
            alarms.cancel(PendingIntent.getBroadcast(
                context,
                REPEAT_REQUEST_BASE + id,
                repeatIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ))
            notificationManager(context).cancel(NOTIFICATION_BASE + id)
            markFlutterOccurrenceCompleted(context, id, startAt)
        }

        private fun markFlutterOccurrenceCompleted(context: Context, id: Int, startAt: Long) {
            try {
                val storage = context.getSharedPreferences(FLUTTER_PREFERENCES, Context.MODE_PRIVATE)
                val raw = storage.getString(FLUTTER_REMINDERS_KEY, null) ?: return
                val list = JSONArray(raw)
                val dateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
                    timeZone = TimeZone.getTimeZone("Asia/Jakarta")
                }
                val dateKey = dateFormat.format(Date(startAt))
                for (index in 0 until list.length()) {
                    val item = list.optJSONObject(index) ?: continue
                    if (item.optInt("id", -1) != id) continue
                    val completed = item.optJSONArray("completedDates") ?: JSONArray()
                    var exists = false
                    for (dateIndex in 0 until completed.length()) {
                        if (completed.optString(dateIndex) == dateKey) exists = true
                    }
                    if (!exists) completed.put(dateKey)
                    item.put("completedDates", completed)
                    list.put(index, item)
                    storage.edit().putString(FLUTTER_REMINDERS_KEY, list.toString()).apply()
                    return
                }
            } catch (_: Exception) {
                // Notifikasi tetap selesai meskipun sinkronisasi status UI gagal.
            }
        }

        private fun cancelAlarms(context: Context, id: Int) {
            val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val startIntent = Intent(context, ReminderPulseReceiver::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_ID, id)
            }
            val repeatIntent = Intent(context, ReminderPulseReceiver::class.java).apply {
                action = ACTION_REPEAT
                putExtra(EXTRA_ID, id)
            }
            alarms.cancel(PendingIntent.getBroadcast(
                context, START_REQUEST_BASE + id, startIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ))
            alarms.cancel(PendingIntent.getBroadcast(
                context, REPEAT_REQUEST_BASE + id, repeatIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ))
        }

        private fun createNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Pengingat VoltStride",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Pengingat latihan yang berulang sampai ditandai selesai."
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 250, 500)
                setSound(android.provider.Settings.System.DEFAULT_NOTIFICATION_URI, null)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            notificationManager(context).createNotificationChannel(channel)
        }

        private fun notificationManager(context: Context) =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    }
}
