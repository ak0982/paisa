package com.paisa.paisa_app

import android.Manifest
import android.content.ContentResolver
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "com.paisa.paisa_app/sms"
    private val inboxUri: Uri = Uri.parse("content://sms/inbox")
    private val projection = arrayOf(
        Telephony.Sms._ID,
        Telephony.Sms.ADDRESS,
        Telephony.Sms.BODY,
        Telephony.Sms.DATE
    )

    // ISSUE-10: content-provider reads + native filtering must not run on the
    // Android main thread (ANR risk on large inboxes). One worker is enough —
    // batches are already sequential from Dart.
    private val smsExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> result.success(hasSmsPermission())
                    "getInboxCount" -> {
                        if (!hasSmsPermission()) {
                            result.error("PERMISSION_DENIED", "SMS permission not granted", null)
                            return@setMethodCallHandler
                        }
                        val sinceMs = call.argument<Number>("sinceMs")?.toLong()
                        smsExecutor.execute {
                            try {
                                val count = getInboxCount(sinceMs)
                                mainHandler.post { result.success(count) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("SMS_COUNT_FAILED", e.message, null)
                                }
                            }
                        }
                    }
                    "scanInboxBatch" -> {
                        if (!hasSmsPermission()) {
                            result.error("PERMISSION_DENIED", "SMS permission not granted", null)
                            return@setMethodCallHandler
                        }
                        val offset = call.argument<Int>("offset") ?: 0
                        val limit = call.argument<Int>("limit") ?: 500
                        val sinceMs = call.argument<Number>("sinceMs")?.toLong()
                        smsExecutor.execute {
                            try {
                                val payload = scanInboxBatch(offset, limit, sinceMs)
                                mainHandler.post { result.success(payload) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("SMS_SCAN_FAILED", e.message, null)
                                }
                            }
                        }
                    }
                    "getSmsById" -> {
                        if (!hasSmsPermission()) {
                            result.error("PERMISSION_DENIED", "SMS permission not granted", null)
                            return@setMethodCallHandler
                        }
                        val id = call.argument<String>("id")
                        if (id.isNullOrBlank()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        smsExecutor.execute {
                            try {
                                val row = getSmsById(id)
                                mainHandler.post { result.success(row) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("SMS_READ_FAILED", e.message, null)
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasSmsPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.READ_SMS
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun getInboxCount(sinceMs: Long?): Int {
        val selection = sinceMs?.let { "${Telephony.Sms.DATE} >= ?" }
        val selectionArgs = sinceMs?.let { arrayOf(it.toString()) }

        val cursor = contentResolver.query(
            inboxUri,
            arrayOf(Telephony.Sms._ID),
            selection,
            selectionArgs,
            null
        ) ?: return 0

        cursor.use { return it.count }
    }

    /**
     * Reads a single inbox message by its `Telephony.Sms._ID`, so a stored
     * transaction can show the alert it was parsed from without Paisa ever
     * persisting message bodies. Returns null when the row is gone (the user
     * deleted the SMS) — the caller renders that as an empty reverse, not an
     * error.
     */
    private fun getSmsById(id: String): Map<String, Any?>? {
        val cursor = contentResolver.query(
            inboxUri,
            projection,
            "${Telephony.Sms._ID} = ?",
            arrayOf(id),
            null
        ) ?: return null

        cursor.use {
            if (!it.moveToFirst()) return null
            val idIdx = it.getColumnIndex(Telephony.Sms._ID)
            val addressIdx = it.getColumnIndex(Telephony.Sms.ADDRESS)
            val bodyIdx = it.getColumnIndex(Telephony.Sms.BODY)
            val dateIdx = it.getColumnIndex(Telephony.Sms.DATE)
            return mapOf(
                "id" to it.getString(idIdx),
                "sender" to (it.getString(addressIdx) ?: ""),
                "body" to (it.getString(bodyIdx) ?: ""),
                "timestamp" to it.getLong(dateIdx)
            )
        }
    }

    /**
     * Reads one page of inbox SMS with SQL LIMIT/OFFSET (no O(n²) skip loop).
     * Pre-filters on native side — only bank candidates are returned to Flutter.
     */
    private fun scanInboxBatch(
        offset: Int,
        limit: Int,
        sinceMs: Long?
    ): Map<String, Any?> {
        val candidates = mutableListOf<Map<String, Any?>>()
        val allRows = mutableListOf<Map<String, Any?>>()
        var rowsRead = 0

        val cursor = queryInboxPage(offset, limit, sinceMs) ?:         return mapOf(
            "candidates" to candidates,
            "allRows" to emptyList<Map<String, Any?>>(),
            "rowsRead" to 0,
            "hasMore" to false
        )

        cursor.use {
            val idIdx = it.getColumnIndex(Telephony.Sms._ID)
            val addressIdx = it.getColumnIndex(Telephony.Sms.ADDRESS)
            val bodyIdx = it.getColumnIndex(Telephony.Sms.BODY)
            val dateIdx = it.getColumnIndex(Telephony.Sms.DATE)

            while (it.moveToNext()) {
                rowsRead++
                val sender = it.getString(addressIdx) ?: ""
                val body = it.getString(bodyIdx) ?: ""
                val row = mapOf(
                    "id" to it.getString(idIdx),
                    "sender" to sender,
                    "body" to body,
                    "timestamp" to it.getLong(dateIdx)
                )
                allRows.add(row)
                if (!SmsNativeFilter.passesPreFilter(sender, body)) continue

                candidates.add(row)
            }
        }

        return mapOf(
            "candidates" to candidates,
            "allRows" to allRows,
            "rowsRead" to rowsRead,
            "hasMore" to (rowsRead >= limit)
        )
    }

    private fun queryInboxPage(offset: Int, limit: Int, sinceMs: Long?) =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Preferred path (API 26+): pass paging via a Bundle. Some OEM SMS
            // providers (certain Samsung / Xiaomi / Vivo builds) do not implement
            // the QUERY_ARG_* contract and throw or ignore it — so fall back to
            // the classic LIMIT/OFFSET sort-order string, which is universally
            // supported, whenever the Bundle query fails or returns null.
            try {
                val args = Bundle().apply {
                    putStringArray(
                        ContentResolver.QUERY_ARG_SORT_COLUMNS,
                        arrayOf(Telephony.Sms.DATE)
                    )
                    putInt(
                        ContentResolver.QUERY_ARG_SORT_DIRECTION,
                        ContentResolver.QUERY_SORT_DIRECTION_DESCENDING
                    )
                    putInt(ContentResolver.QUERY_ARG_LIMIT, limit)
                    putInt(ContentResolver.QUERY_ARG_OFFSET, offset)
                    if (sinceMs != null) {
                        putString(
                            ContentResolver.QUERY_ARG_SQL_SELECTION,
                            "${Telephony.Sms.DATE} >= ?"
                        )
                        putStringArray(
                            ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS,
                            arrayOf(sinceMs.toString())
                        )
                    }
                }
                contentResolver.query(inboxUri, projection, args, null)
                    ?: queryInboxPageLegacy(offset, limit, sinceMs)
            } catch (e: Exception) {
                queryInboxPageLegacy(offset, limit, sinceMs)
            }
        } else {
            queryInboxPageLegacy(offset, limit, sinceMs)
        }

    private fun queryInboxPageLegacy(offset: Int, limit: Int, sinceMs: Long?) =
        try {
            val selection = sinceMs?.let { "${Telephony.Sms.DATE} >= ?" }
            val selectionArgs = sinceMs?.let { arrayOf(it.toString()) }
            val sortOrder = "${Telephony.Sms.DATE} DESC LIMIT $limit OFFSET $offset"
            contentResolver.query(inboxUri, projection, selection, selectionArgs, sortOrder)
        } catch (e: Exception) {
            // Last resort: some providers reject LIMIT in the sort clause too.
            // Read the whole (filtered) inbox ordered by date; the Dart side
            // de-duplicates by SMS id so re-reading rows is safe.
            val selection = sinceMs?.let { "${Telephony.Sms.DATE} >= ?" }
            val selectionArgs = sinceMs?.let { arrayOf(it.toString()) }
            contentResolver.query(
                inboxUri,
                projection,
                selection,
                selectionArgs,
                "${Telephony.Sms.DATE} DESC"
            )
        }
}
