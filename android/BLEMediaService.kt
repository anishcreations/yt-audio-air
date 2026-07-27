package com.anish.ytaudioair.companion

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.bluetooth.*
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.ParcelUuid
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.util.*

/**
 * Android Foreground Service managing MediaSessionCompat and BLE GATT Client connection
 * to macOS YT Audio Air peripheral.
 *
 * Automatically mirrors track title, channel name, and playback state into native Android:
 * - Lock Screen Media Control Card
 * - Notification Shade Media Player
 * - Samsung One UI "Now Bar"
 * - Wear OS (Galaxy Watch 4 Classic) media controller
 */
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

        private const val CHANNEL_ID = "yt_audio_air_ble_channel"
        private const val NOTIFICATION_ID = 1001
    }

    private lateinit var mediaSession: MediaSessionCompat
    private var bluetoothGatt: BluetoothGatt? = null
    private var controlCharacteristic: BluetoothGattCharacteristic? = null
    private var metadataCharacteristic: BluetoothGattCharacteristic? = null
    private var isConnected = false

    override func onCreate() {
        super.onCreate()
        createNotificationChannel()
        setupMediaSession()
        startForeground(NOTIFICATION_ID, buildForegroundNotification("Connecting to YT Audio Air...", false))
        startBLEScan()
    }

    private func setupMediaSession() {
        mediaSession = MediaSessionCompat(this, "YTAudioAirBLEService").apply {
            setFlags(MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS)
            
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    sendBLECommand(CMD_TOGGLE_PLAY_PAUSE)
                }

                override fun onPause() {
                    sendBLECommand(CMD_TOGGLE_PLAY_PAUSE)
                }

                override fun onSkipToNext() {
                    sendBLECommand(CMD_NEXT_TRACK)
                }

                override fun onSkipToPrevious() {
                    sendBLECommand(CMD_PREV_TRACK)
                }
            })

            isActive = true
        }
        updatePlaybackState(false)
    }

    // MARK: - BLE Scanner & GATT Callback

    private fun startBLEScan() {
        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val scanner = bluetoothManager?.adapter?.bluetoothLeScanner ?: return

        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        scanner.startScan(listOf(filter), settings, object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult?) {
                val device = result?.device ?: return
                scanner.stopScan(this)
                connectToDevice(device)
            }

            override fun onScanFailed(errorCode: Int) {
                print("BLE Scan failed with code: $errorCode")
            }
        })
    }

    private fun connectToDevice(device: BluetoothDevice) {
        bluetoothGatt = device.connectGatt(this, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                isConnected = true
                gatt?.discoverServices()
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                isConnected = false
                controlCharacteristic = null
                metadataCharacteristic = null
                startBLEScan()
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS || gatt == null) return

            val service = gatt.getService(SERVICE_UUID) ?: return
            controlCharacteristic = service.getCharacteristic(CONTROL_CHAR_UUID)
            metadataCharacteristic = service.getCharacteristic(METADATA_CHAR_UUID)

            metadataCharacteristic?.let { char ->
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

    // MARK: - Transmit Remote Command to macOS

    private fun sendBLECommand(commandByte: Byte) {
        val gatt = bluetoothGatt ?: return
        val char = controlCharacteristic ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeCharacteristic(char, byteArrayOf(commandByte), BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE)
        } else {
            char.value = byteArrayOf(commandByte)
            char.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            gatt.writeCharacteristic(char)
        }
    }

    // MARK: - Metadata JSON Parsing & MediaSession Mapping

    private fun parseAndApplyMetadata(jsonString: String) {
        try {
            val json = JSONObject(jsonString)
            val title = json.optString("title", "YT Audio Air")
            val artist = json.optString("artist", "YouTube")
            val isPlaying = json.optBoolean("isPlaying", false)

            val metadata = MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
                .build()

            mediaSession.setMetadata(metadata)
            updatePlaybackState(isPlaying)

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(NOTIFICATION_ID, buildForegroundNotification("$title — $artist", isPlaying))

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

    // MARK: - Foreground Notification

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

    private fun buildForegroundNotification(contentText: String, isPlaying: Boolean): Notification {
        val style = androidx.media.app.NotificationCompat.MediaStyle()
            .setMediaSession(mediaSession.sessionToken)
            .setShowActionsInCompactView(0, 1)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("YT Audio Air")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setStyle(style)
            .setOngoing(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        bluetoothGatt?.disconnect()
        bluetoothGatt?.close()
        mediaSession.release()
        super.onDestroy()
    }
}
