package tv.wena.app

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import androidx.tvprovider.media.tv.Channel
import androidx.tvprovider.media.tv.PreviewProgram
import androidx.tvprovider.media.tv.TvContractCompat
import androidx.tvprovider.media.tv.WatchNextProgram
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "tv.wena.app/native_tv"
    private var methodChannel: MethodChannel? = null
    private var pendingDeepLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingDeepLink = intent?.dataString
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialDeepLink" -> result.success(pendingDeepLink)
                    "publishWatchNext" -> {
                        @Suppress("UNCHECKED_CAST")
                        publishWatchNext(call.arguments as? Map<String, Any?>)
                        result.success(null)
                    }
                    "removeWatchNext" -> {
                        removeWatchNext(call.argument<String>("id").orEmpty())
                        result.success(null)
                    }
                    "publishChannels" -> {
                        @Suppress("UNCHECKED_CAST")
                        publishChannels(call.arguments as? List<Map<String, Any?>>)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingDeepLink = intent.dataString
        intent.dataString?.let { methodChannel?.invokeMethod("deepLink", it) }
    }

    private fun publishWatchNext(data: Map<String, Any?>?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || data == null) return
        val id = data.string("id")
        if (id.isBlank()) return
        val title = data.string("title").ifBlank { "WenaTV" }
        val program = WatchNextProgram.Builder()
            .setWatchNextType(TvContractCompat.WatchNextPrograms.WATCH_NEXT_TYPE_CONTINUE)
            .setType(
                if (data.string("kind") == "tv") {
                    TvContractCompat.WatchNextPrograms.TYPE_TV_EPISODE
                } else {
                    TvContractCompat.WatchNextPrograms.TYPE_MOVIE
                }
            )
            .setTitle(title)
            .setDescription(data.string("description"))
            .setPosterArtUri(data.uri("posterUrl") ?: data.uri("backdropUrl"))
            .setIntentUri(data.uri("deepLink"))
            .setInternalProviderId(id)
            .setContentId(data.string("contentId").ifBlank { id })
            .setDurationMillis(data.intMillis("durationMs"))
            .setLastPlaybackPositionMillis(data.intMillis("positionMs"))
            .build()

        val existingId = findProgramId(
            TvContractCompat.WatchNextPrograms.CONTENT_URI,
            TvContractCompat.WatchNextPrograms.COLUMN_INTERNAL_PROVIDER_ID,
            id,
        )
        if (existingId != null) {
            contentResolver.update(
                ContentUris.withAppendedId(TvContractCompat.WatchNextPrograms.CONTENT_URI, existingId),
                program.toContentValues(),
                null,
                null,
            )
        } else {
            contentResolver.insert(TvContractCompat.WatchNextPrograms.CONTENT_URI, program.toContentValues())
        }
    }

    private fun removeWatchNext(id: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || id.isBlank()) return
        val existingId = findProgramId(
            TvContractCompat.WatchNextPrograms.CONTENT_URI,
            TvContractCompat.WatchNextPrograms.COLUMN_INTERNAL_PROVIDER_ID,
            id,
        ) ?: return
        contentResolver.delete(
            ContentUris.withAppendedId(TvContractCompat.WatchNextPrograms.CONTENT_URI, existingId),
            null,
            null,
        )
    }

    private fun publishChannels(channels: List<Map<String, Any?>>?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || channels == null) return
        channels.take(4).forEach { channelData ->
            val channelKey = channelData.string("id")
            val channelTitle = channelData.string("title")
            if (channelKey.isBlank() || channelTitle.isBlank()) return@forEach
            val channelId = ensureChannel(channelKey, channelTitle) ?: return@forEach
            clearPreviewPrograms(channelId)
            @Suppress("UNCHECKED_CAST")
            val items = channelData["items"] as? List<Map<String, Any?>> ?: return@forEach
            items.take(20).forEachIndexed { index, item ->
                val title = item.string("title")
                val deepLink = item.uri("deepLink") ?: return@forEachIndexed
                if (title.isBlank()) return@forEachIndexed
                val program = PreviewProgram.Builder()
                    .setChannelId(channelId)
                    .setType(
                        if (item.string("kind") == "tv") {
                            TvContractCompat.PreviewPrograms.TYPE_TV_SERIES
                        } else {
                            TvContractCompat.PreviewPrograms.TYPE_MOVIE
                        }
                    )
                    .setTitle(title)
                    .setDescription(item.string("description"))
                    .setPosterArtUri(item.uri("posterUrl") ?: item.uri("backdropUrl"))
                    .setIntentUri(deepLink)
                    .setInternalProviderId("${channelKey}:${item.string("id")}:$index")
                    .build()
                contentResolver.insert(TvContractCompat.PreviewPrograms.CONTENT_URI, program.toContentValues())
            }
            TvContractCompat.requestChannelBrowsable(this, channelId)
        }
    }

    private fun ensureChannel(key: String, name: String): Long? {
        val prefs = getSharedPreferences("wena_tv_channels", Context.MODE_PRIVATE)
        val saved = prefs.getLong(key, -1L)
        if (saved > 0) return saved
        val channel = Channel.Builder()
            .setDisplayName(name)
            .setType(TvContractCompat.Channels.TYPE_PREVIEW)
            .setInternalProviderId(key)
            .build()
        val uri = contentResolver.insert(TvContractCompat.Channels.CONTENT_URI, channel.toContentValues())
        val id = uri?.let(ContentUris::parseId) ?: return null
        prefs.edit().putLong(key, id).apply()
        return id
    }

    private fun clearPreviewPrograms(channelId: Long) {
        contentResolver.delete(
            TvContractCompat.PreviewPrograms.CONTENT_URI,
            "${TvContractCompat.PreviewPrograms.COLUMN_CHANNEL_ID}=?",
            arrayOf(channelId.toString()),
        )
    }

    private fun findProgramId(uri: Uri, internalProviderColumn: String, internalProviderId: String): Long? {
        val cursor: Cursor? = contentResolver.query(
            uri,
            arrayOf(TvContractCompat.BaseTvColumns._ID),
            "$internalProviderColumn=?",
            arrayOf(internalProviderId),
            null,
        )
        cursor.use {
            if (it != null && it.moveToFirst()) return it.getLong(0)
        }
        return null
    }

    private fun Map<String, Any?>.string(key: String): String = this[key]?.toString().orEmpty()

    private fun Map<String, Any?>.long(key: String): Long {
        val value = this[key]
        return when (value) {
            is Number -> value.toLong()
            is String -> value.toLongOrNull() ?: 0L
            else -> 0L
        }
    }

    private fun Map<String, Any?>.intMillis(key: String): Int =
        long(key).coerceIn(0L, Int.MAX_VALUE.toLong()).toInt()

    private fun Map<String, Any?>.uri(key: String): Uri? {
        val value = string(key)
        return if (value.isBlank()) null else Uri.parse(value)
    }

    private fun WatchNextProgram.toContentValues(): ContentValues = toContentValues(false)
    private fun PreviewProgram.toContentValues(): ContentValues = toContentValues(false)
    private fun Channel.toContentValues(): ContentValues = toContentValues(false)
}
