package com.anish.ytaudioair.companion

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.*
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.os.Build
import android.os.IBinder
import android.os.ParcelUuid
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.VolumeProviderCompat
import androidx.media.session.MediaButtonReceiver
import org.json.JSONObject
import java.util.*

class BLEMediaService : Service() {

    companion object {
        val SERVICE_UUID: UUID = UUID.fromString("12345678-1234-1234-1234-123456789abc")
        val CONTROL_CHAR_UUID: UUID = UUID.fromString("87654321-4321-4321-4321-cba987654321")
        val METADATA_CHAR_UUID: UUID = UUID.fromString("98765432-4321-4321-4321-abcdef123456")
        val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        const val CMD_TOGGLE_PLAY_PAUSE: Byte = 0x01
        const val CMD_NEXT_TRACK: Byte       = 0x02
        const val CMD_PREV_TRACK: Byte       = 0x03
        const val CMD_VOLUME_UP: Byte        = 0x04
        const val CMD_VOLUME_DOWN: Byte      = 0x05

        const val ACTION_BLE_STATUS = "com.anish.ytaudioair.companion.BLE_STATUS"
        const val ACTION_MEDIA_CONTROL = "com.anish.ytaudioair.companion.MEDIA_CONTROL"
        const val EXTRA_CMD = "cmd_byte"

        const val EXTRA_STATUS = "status"
        const val EXTRA_TITLE = "title"
        const val EXTRA_ARTIST = "artist"
        const val EXTRA_IS_PLAYING = "isPlaying"

        private const val CHANNEL_ID = "yt_audio_air_ble_channel"
        private const val NOTIFICATION_ID = 1001

        var instance: BLEMediaService? = null
    }

    private lateinit var mediaSession: MediaSessionCompat
    private var bluetoothGatt: BluetoothGatt? = null
    private var controlCharacteristic: BluetoothGattCharacteristic? = null
    private var metadataCharacteristic: BluetoothGattCharacteristic? = null

    var isConnected: Boolean = false
        private set

    var connectionStatus: String = "Disconnected"
        private set
    var currentTitle: String = "YT Audio Air"
        private set
    var currentArtist: String = "YouTube"
        private set
    var isMediaPlaying: Boolean = false
        private set

    private var defaultArtworkBitmap: Bitmap? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        try {
            defaultArtworkBitmap = createGradientArtwork()
            createNotificationChannel()
            setupMediaSession()
            startForeground(NOTIFICATION_ID, buildNotification())
            updateStatus("Scanning for Mac...")
            startBLEScan()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent != null) {
            MediaButtonReceiver.handleIntent(mediaSession, intent)
            if (intent.hasExtra(EXTRA_CMD)) {
                val cmd = intent.getByteExtra(EXTRA_CMD, 0)
                if (cmd.toInt() != 0) {
                    sendBLECommand(cmd)
                }
            }
        }
        return START_STICKY
    }

    private fun updateStatus(status: String) {
        connectionStatus = status
        updateNotification()
        broadcastUpdate()
    }

    private fun broadcastUpdate() {
        val intent = Intent(ACTION_BLE_STATUS).apply {
            putExtra(EXTRA_STATUS, connectionStatus)
            putExtra(EXTRA_TITLE, currentTitle)
            putExtra(EXTRA_ARTIST, currentArtist)
            putExtra(EXTRA_IS_PLAYING, isMediaPlaying)
        }
        sendBroadcast(intent)
    }

    private fun setupMediaSession() {
        mediaSession = MediaSessionCompat(this, "YTAudioAirBLEService").apply {
            setFlags(MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS)

            val sessionActivityPendingIntent = PendingIntent.getActivity(
                this@BLEMediaService,
                0,
                Intent(this@BLEMediaService, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            setSessionActivity(sessionActivityPendingIntent)

            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    sendBLECommand(CMD_TOGGLE_PLAY_PAUSE)
                    isMediaPlaying = true
                    updatePlaybackState(true)
                    updateNotification()
                }

                override fun onPause() {
                    sendBLECommand(CMD_TOGGLE_PLAY_PAUSE)
                    isMediaPlaying = false
                    updatePlaybackState(false)
                    updateNotification()
                }

                override fun onSkipToNext() {
                    sendBLECommand(CMD_NEXT_TRACK)
                }

                override fun onSkipToPrevious() {
                    sendBLECommand(CMD_PREV_TRACK)
                }
            })

            // Enable Remote Volume Control with standard notification seekbar slider
            var currentVol = 50
            var lastVolTime = 0L
            val volumeProvider = object : VolumeProviderCompat(VOLUME_CONTROL_ABSOLUTE, 100, currentVol) {
                override fun onSetVolumeTo(volume: Int) {
                    val now = System.currentTimeMillis()
                    if (now - lastVolTime > 120) {
                        lastVolTime = now
                        if (volume > currentVol) {
                            sendBLECommand(CMD_VOLUME_UP)
                        } else if (volume < currentVol) {
                            sendBLECommand(CMD_VOLUME_DOWN)
                        }
                        currentVol = volume
                    }
                }

                override fun onAdjustVolume(direction: Int) {
                    val now = System.currentTimeMillis()
                    if (now - lastVolTime > 120) {
                        lastVolTime = now
                        if (direction > 0) {
                            sendBLECommand(CMD_VOLUME_UP)
                            currentVol = Math.min(100, currentVol + 5)
                        } else if (direction < 0) {
                            sendBLECommand(CMD_VOLUME_DOWN)
                            currentVol = Math.max(0, currentVol - 5)
                        }
                    }
                }
            }
            setPlaybackToRemote(volumeProvider)
            isActive = true
        }

        updateMediaSessionMetadata(currentTitle, currentArtist)
        updatePlaybackState(false)
    }

    private fun updateMediaSessionMetadata(title: String, artist: String) {
        val builder = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)

        defaultArtworkBitmap?.let { bmp ->
            builder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, bmp)
            builder.putBitmap(MediaMetadataCompat.METADATA_KEY_ART, bmp)
        }

        mediaSession.setMetadata(builder.build())
    }

    private fun startBLEScan() {
        try {
            val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val adapter = bluetoothManager?.adapter ?: return
            if (!adapter.isEnabled) {
                updateStatus("Bluetooth Disabled")
                return
            }

            val scanner = adapter.bluetoothLeScanner ?: return

            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build()

            scanner.startScan(null, settings, object : ScanCallback() {
                override fun onScanResult(callbackType: Int, result: ScanResult?) {
                    val device = result?.device ?: return
                    val name = try { device.name ?: "" } catch (e: SecurityException) { "" }
                    val uuids = result?.scanRecord?.serviceUuids?.map { it.uuid } ?: emptyList()

                    if (uuids.contains(SERVICE_UUID) || name.contains("YT Audio Air", ignoreCase = true) || name.contains("M5 Air", ignoreCase = true)) {
                        try {
                            scanner.stopScan(this)
                        } catch (e: Exception) {}
                        updateStatus("Connecting to ${if (name.isNotEmpty()) name else "Mac"}...")
                        connectToDevice(device)
                    }
                }

                override fun onScanFailed(errorCode: Int) {
                    updateStatus("Scan Failed ($errorCode)")
                }
            })
        } catch (e: SecurityException) {
            updateStatus("Bluetooth Permission Required")
        } catch (e: Exception) {
            updateStatus("Scan Error: ${e.message}")
        }
    }

    private fun connectToDevice(device: BluetoothDevice) {
        try {
            bluetoothGatt = device.connectGatt(this, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        } catch (e: SecurityException) {
            updateStatus("Connection Permission Error")
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                this@BLEMediaService.isConnected = true
                updateStatus("Connected to Mac!")
                try {
                    gatt?.discoverServices()
                } catch (e: SecurityException) {
                    e.printStackTrace()
                }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                this@BLEMediaService.isConnected = false
                controlCharacteristic = null
                metadataCharacteristic = null
                updateStatus("Disconnected. Re-scanning...")
                startBLEScan()
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS || gatt == null) return

            val service = gatt.getService(SERVICE_UUID)
            if (service == null) {
                updateStatus("Service Not Found")
                return
            }

            controlCharacteristic = service.getCharacteristic(CONTROL_CHAR_UUID)
            metadataCharacteristic = service.getCharacteristic(METADATA_CHAR_UUID)

            metadataCharacteristic?.let { char ->
                try {
                    gatt.setCharacteristicNotification(char, true)
                    val descriptor = char.getDescriptor(CCCD_UUID)
                    if (descriptor != null) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            gatt.writeDescriptor(descriptor, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                        } else {
                            descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                            gatt.writeDescriptor(descriptor)
                        }
                    }
                    updateStatus("Connected (Synced)")
                } catch (e: SecurityException) {
                    e.printStackTrace()
                }
            }
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray
        ) {
            if (characteristic.uuid == METADATA_CHAR_UUID) {
                parseAndApplyMetadata(String(value, Charsets.UTF_8))
            }
        }

        @Deprecated("Deprecated for API < 33")
        override fun onCharacteristicChanged(
            gatt: BluetoothGatt?,
            characteristic: BluetoothGattCharacteristic?
        ) {
            if (characteristic?.uuid == METADATA_CHAR_UUID && characteristic.value != null) {
                parseAndApplyMetadata(String(characteristic.value, Charsets.UTF_8))
            }
        }
    }

    fun sendBLECommand(commandByte: Byte) {
        val gatt = bluetoothGatt ?: return
        val char = controlCharacteristic ?: return

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                gatt.writeCharacteristic(char, byteArrayOf(commandByte), BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE)
            } else {
                char.value = byteArrayOf(commandByte)
                char.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
                gatt.writeCharacteristic(char)
            }
        } catch (e: SecurityException) {
            e.printStackTrace()
        }
    }

    private fun parseAndApplyMetadata(jsonString: String) {
        try {
            val json = JSONObject(jsonString)
            currentTitle = json.optString("title", "YT Audio Air")
            currentArtist = json.optString("artist", "YouTube")
            isMediaPlaying = json.optBoolean("isPlaying", false)

            updateMediaSessionMetadata(currentTitle, currentArtist)
            updatePlaybackState(isMediaPlaying)
            updateNotification()
            broadcastUpdate()

        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun updatePlaybackState(isPlaying: Boolean) {
        val state = if (isPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED
        val actions = PlaybackStateCompat.ACTION_PLAY_PAUSE or
                      PlaybackStateCompat.ACTION_PLAY or
                      PlaybackStateCompat.ACTION_PAUSE or
                      PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                      PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS

        val playbackState = PlaybackStateCompat.Builder()
            .setActions(actions)
            .setState(state, PlaybackStateCompat.PLAYBACK_POSITION_UNKNOWN, 1.0f)
            .build()

        mediaSession.setPlaybackState(playbackState)
    }

    private fun updateNotification() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun buildNotification(): Notification {
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val prevPendingIntent = MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS)
        val targetPlayPauseAction = if (isMediaPlaying) PlaybackStateCompat.ACTION_PAUSE else PlaybackStateCompat.ACTION_PLAY
        val playPausePendingIntent = MediaButtonReceiver.buildMediaButtonPendingIntent(this, targetPlayPauseAction)
        val nextPendingIntent = MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_SKIP_TO_NEXT)

        val playPauseIcon = if (isMediaPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        val playPauseTitle = if (isMediaPlaying) "Pause" else "Play"

        val style = androidx.media.app.NotificationCompat.MediaStyle()
            .setMediaSession(mediaSession.sessionToken)
            .setShowActionsInCompactView(0, 1, 2)

        val contentTitleText = if (currentTitle.isNotEmpty() && currentTitle != "YT Audio Air") currentTitle else connectionStatus
        val contentArtistText = if (currentArtist.isNotEmpty()) currentArtist else "YT Audio Air Remote"

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(contentTitleText)
            .setContentText(contentArtistText)
            .setSubText(connectionStatus)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(contentIntent)
            .setStyle(style)
            .setOngoing(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(NotificationCompat.Action(android.R.drawable.ic_media_previous, "Previous", prevPendingIntent))
            .addAction(NotificationCompat.Action(playPauseIcon, playPauseTitle, playPausePendingIntent))
            .addAction(NotificationCompat.Action(android.R.drawable.ic_media_next, "Next", nextPendingIntent))

        defaultArtworkBitmap?.let { bmp ->
            builder.setLargeIcon(bmp)
        }

        return builder.build()
    }

    private fun createGradientArtwork(): Bitmap {
        val width = 300
        val height = 300
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val paint = Paint().apply {
            shader = LinearGradient(
                0f, 0f, width.toFloat(), height.toFloat(),
                Color.parseColor("#FF0000"),
                Color.parseColor("#800020"),
                Shader.TileMode.CLAMP
            )
        }
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)

        val textPaint = Paint().apply {
            color = Color.WHITE
            textSize = 36f
            isAntiAlias = true
            textAlign = Paint.Align.CENTER
        }
        canvas.drawText("YT AUDIO AIR", width / 2f, height / 2f + 12f, textPaint)

        return bitmap
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "YT Audio Air BLE Remote",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        instance = null
        try {
            bluetoothGatt?.disconnect()
            bluetoothGatt?.close()
        } catch (e: SecurityException) {
            e.printStackTrace()
        }
        mediaSession.release()
        super.onDestroy()
    }
}
