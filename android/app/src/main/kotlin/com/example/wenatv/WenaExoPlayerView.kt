package tv.wena.app

import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class WenaExoPlayerViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        WenaExoPlayerView(context, messenger, viewId, args as? Map<*, *>)

    companion object {
        const val viewType = "tv.wena.app/exo_player_view"
    }
}

private class WenaExoPlayerView(
    context: Context,
    messenger: BinaryMessenger,
    private val viewId: Int,
    creationParams: Map<*, *>?,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val trackSelector = DefaultTrackSelector(context)
    private val dataSourceFactory = DefaultHttpDataSource.Factory()
        .setAllowCrossProtocolRedirects(true)
    private val player = ExoPlayer.Builder(context)
        .setTrackSelector(trackSelector)
        .setMediaSourceFactory(DefaultMediaSourceFactory(context).setDataSourceFactory(dataSourceFactory))
        .build()
    private val playerView = PlayerView(context).apply {
        setBackgroundColor(Color.BLACK)
        useController = false
        keepScreenOn = true
        resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
        this.player = this@WenaExoPlayerView.player
        
        subtitleView?.setStyle(
            CaptionStyleCompat(
                Color.WHITE,
                Color.TRANSPARENT,
                Color.TRANSPARENT,
                CaptionStyleCompat.EDGE_TYPE_DROP_SHADOW,
                Color.BLACK,
                null
            )
        )
        subtitleView?.setFractionalTextSize(0.0533f) // Standard 16:9 subtitle size
    }
    private val channel = MethodChannel(messenger, "tv.wena.app/exo_player/$viewId")
    private val handler = Handler(Looper.getMainLooper())
    private val positionTicker = object : Runnable {
        override fun run() {
            sendState()
            handler.postDelayed(this, 500)
        }
    }

    init {
        channel.setMethodCallHandler(this)
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                sendState()
                if (playbackState == Player.STATE_ENDED) {
                    channel.invokeMethod("event", mapOf("type" to "ended"))
                }
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                sendState()
            }

            override fun onTracksChanged(tracks: Tracks) {
                sendTracks()
            }

            override fun onPlayerError(error: PlaybackException) {
                channel.invokeMethod(
                    "event",
                    mapOf(
                        "type" to "error",
                        "message" to (error.message ?: "Playback failed"),
                    ),
                )
            }
        })
        openFromParams(creationParams)
        handler.post(positionTicker)
    }

    override fun getView(): View = playerView

    override fun dispose() {
        handler.removeCallbacksAndMessages(null)
        channel.setMethodCallHandler(null)
        playerView.player = null
        player.release()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "open" -> {
                @Suppress("UNCHECKED_CAST")
                openFromParams(call.arguments as? Map<*, *>)
                result.success(null)
            }
            "play" -> {
                player.play()
                result.success(null)
            }
            "pause" -> {
                player.pause()
                result.success(null)
            }
            "seekTo" -> {
                val positionMs = call.argument<Number>("positionMs")?.toLong() ?: 0L
                player.seekTo(positionMs.coerceAtLeast(0L))
                result.success(null)
            }
            "setAudioTrack" -> {
                selectTrack(C.TRACK_TYPE_AUDIO, call.argument<String>("id"))
                result.success(null)
            }
            "setSubtitleTrack" -> {
                selectSubtitle(call.argument<String>("id") ?: "off")
                result.success(null)
            }
            "setAspectMode" -> {
                playerView.resizeMode = when (call.argument<String>("mode")) {
                    "fill" -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                    "stretch" -> AspectRatioFrameLayout.RESIZE_MODE_FILL
                    "original" -> AspectRatioFrameLayout.RESIZE_MODE_FIXED_WIDTH
                    else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
                }
                playerView.requestLayout()
                playerView.invalidate()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun openFromParams(params: Map<*, *>?) {
        val url = params.string("url")
        if (url.isBlank()) return
        val headers = params.map("headers")
        dataSourceFactory.setDefaultRequestProperties(headers)

        val subtitles = params.list("subtitles").mapNotNull { raw ->
            val item = raw as? Map<*, *> ?: return@mapNotNull null
            val subUrl = item.string("url")
            if (subUrl.isBlank()) return@mapNotNull null
            MediaItem.SubtitleConfiguration.Builder(Uri.parse(subUrl))
                .setLabel(item.string("label").ifBlank { item.string("title") })
                .setLanguage(item.string("language").ifBlank { null })
                .setMimeType(subtitleMime(item.string("format"), subUrl))
                .build()
        }

        val mediaItem = MediaItem.Builder()
            .setUri(Uri.parse(url))
            .setSubtitleConfigurations(subtitles)
            .build()
        player.setMediaItem(mediaItem)
        player.prepare()
        val startMs = params.long("startPositionMs")
        if (startMs > 0) player.seekTo(startMs)
        player.playWhenReady = params?.get("playWhenReady") != false
        sendState()
        sendTracks()
    }

    private fun selectSubtitle(id: String) {
        val builder = trackSelector.buildUponParameters()
            .clearOverridesOfType(C.TRACK_TYPE_TEXT)
        if (id == "off") {
            trackSelector.parameters = builder
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                .build()
            sendTracks()
            return
        }
        if (id == "auto") {
            trackSelector.parameters = builder
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                .build()
            sendTracks()
            return
        }
        selectTrack(C.TRACK_TYPE_TEXT, id)
    }

    private fun selectTrack(trackType: Int, id: String?) {
        val parts = id?.split(":") ?: return
        val groupIndex = parts.getOrNull(0)?.toIntOrNull() ?: return
        val trackIndex = parts.getOrNull(1)?.toIntOrNull() ?: return
        val groups = player.currentTracks.groups
        val group = groups.getOrNull(groupIndex) ?: return
        if (group.type != trackType || trackIndex !in 0 until group.length) return
        val builder = trackSelector.buildUponParameters()
            .setTrackTypeDisabled(trackType, false)
            .clearOverridesOfType(trackType)
            .setOverrideForType(
                TrackSelectionOverride(group.mediaTrackGroup, listOf(trackIndex)),
            )
        trackSelector.parameters = builder.build()
        sendTracks()
    }

    private fun sendState() {
        channel.invokeMethod(
            "event",
            mapOf(
                "type" to "state",
                "positionMs" to player.currentPosition.coerceAtLeast(0L),
                "durationMs" to if (player.duration == C.TIME_UNSET) 0L else player.duration.coerceAtLeast(0L),
                "playing" to player.isPlaying,
                "buffering" to (player.playbackState == Player.STATE_BUFFERING),
                "ready" to (player.playbackState == Player.STATE_READY),
            ),
        )
    }

    private fun sendTracks() {
        val groups = player.currentTracks.groups
        val audio = mutableListOf<Map<String, Any?>>()
        val subtitles = mutableListOf<Map<String, Any?>>()
        groups.forEachIndexed { groupIndex, group ->
            for (trackIndex in 0 until group.length) {
                val format = group.getTrackFormat(trackIndex)
                val id = "$groupIndex:$trackIndex"
                val entry = mapOf(
                    "id" to id,
                    "label" to (format.label ?: ""),
                    "language" to (format.language ?: ""),
                    "codec" to (format.codecs ?: format.sampleMimeType ?: ""),
                    "channelCount" to format.channelCount,
                    "sampleRate" to format.sampleRate,
                    "bitrate" to format.bitrate,
                    "mimeType" to (format.sampleMimeType ?: ""),
                    "selected" to group.isTrackSelected(trackIndex),
                )
                when (group.type) {
                    C.TRACK_TYPE_AUDIO -> audio.add(entry)
                    C.TRACK_TYPE_TEXT -> subtitles.add(entry)
                }
            }
        }
        channel.invokeMethod(
            "event",
            mapOf(
                "type" to "tracks",
                "audio" to audio,
                "subtitles" to subtitles,
            ),
        )
    }

    private fun subtitleMime(format: String, url: String): String {
        val value = format.lowercase().ifBlank { url.substringAfterLast('.', "").lowercase() }
        return when {
            value.contains("vtt") || value.contains("webvtt") -> MimeTypes.TEXT_VTT
            value.contains("srt") || value.contains("subrip") -> MimeTypes.APPLICATION_SUBRIP
            value.contains("ass") || value.contains("ssa") -> MimeTypes.TEXT_SSA
            else -> MimeTypes.TEXT_VTT
        }
    }

    private fun Map<*, *>?.string(key: String): String = this?.get(key)?.toString().orEmpty()
    private fun Map<*, *>?.long(key: String): Long {
        val value = this?.get(key)
        return when (value) {
            is Number -> value.toLong()
            is String -> value.toLongOrNull() ?: 0L
            else -> 0L
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun Map<*, *>?.map(key: String): Map<String, String> {
        val raw = this?.get(key) as? Map<*, *> ?: return emptyMap()
        return raw.entries.associate { it.key.toString() to it.value.toString() }
    }

    @Suppress("UNCHECKED_CAST")
    private fun Map<*, *>?.list(key: String): List<Any?> =
        this?.get(key) as? List<Any?> ?: emptyList()
}
