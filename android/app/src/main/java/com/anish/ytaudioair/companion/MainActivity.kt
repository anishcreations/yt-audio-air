package com.anish.ytaudioair.companion

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class MainActivity : AppCompatActivity() {

    private val PERMISSION_REQUEST_CODE = 101

    private lateinit var statusTextView: TextView
    private lateinit var titleTextView: TextView
    private lateinit var artistTextView: TextView
    private lateinit var playPauseButton: Button

    private var localIsPlaying = false

    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == BLEMediaService.ACTION_BLE_STATUS) {
                val status = intent.getStringExtra(BLEMediaService.EXTRA_STATUS) ?: "Disconnected"
                val title = intent.getStringExtra(BLEMediaService.EXTRA_TITLE) ?: "YT Audio Air"
                val artist = intent.getStringExtra(BLEMediaService.EXTRA_ARTIST) ?: "YouTube"
                val isPlaying = intent.getBooleanExtra(BLEMediaService.EXTRA_IS_PLAYING, false)

                localIsPlaying = isPlaying
                updateUI(status, title, artist, localIsPlaying)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Dark Glassmorphic Theme Layout
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#121212"))
            setPadding(48, 64, 48, 48)
            gravity = Gravity.CENTER_HORIZONTAL
        }

        // 1. Header Title
        val appHeader = TextView(this).apply {
            text = "YT Audio Air Remote"
            setTextColor(Color.WHITE)
            textSize = 22f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }
        root.addView(appHeader)

        // 2. Connection Status Badge
        statusTextView = TextView(this).apply {
            text = "○ Disconnected"
            setTextColor(Color.parseColor("#FFA500"))
            textSize = 14f
            setPadding(32, 16, 32, 16)
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#1E1E1E"))
        }
        val statusParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { setMargins(0, 24, 0, 40) }
        root.addView(statusTextView, statusParams)

        // 3. Now Playing Track Metadata Card
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#1E1E24"))
            setPadding(48, 48, 48, 48)
            gravity = Gravity.CENTER
        }
        val cardParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { setMargins(0, 0, 0, 48) }

        titleTextView = TextView(this).apply {
            text = "YT Audio Air"
            setTextColor(Color.WHITE)
            textSize = 18f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }
        card.addView(titleTextView)

        artistTextView = TextView(this).apply {
            text = "YouTube"
            setTextColor(Color.parseColor("#AAAAAA"))
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding(0, 12, 0, 0)
        }
        card.addView(artistTextView)
        root.addView(card, cardParams)

        // 4. Interactive Transport Controls Row
        val controlsLayout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }

        val prevBtn = Button(this).apply {
            text = "⏮ Prev"
            setOnClickListener { BLEMediaService.instance?.sendBLECommand(BLEMediaService.CMD_PREV_TRACK) }
        }

        playPauseButton = Button(this).apply {
            text = "▶ Play"
            setOnClickListener {
                // Immediate optimistic UI update for instant response!
                localIsPlaying = !localIsPlaying
                playPauseButton.text = if (localIsPlaying) "⏸ Pause" else "▶ Play"
                BLEMediaService.instance?.sendBLECommand(BLEMediaService.CMD_TOGGLE_PLAY_PAUSE)
            }
        }

        val nextBtn = Button(this).apply {
            text = "Next ⏭"
            setOnClickListener { BLEMediaService.instance?.sendBLECommand(BLEMediaService.CMD_NEXT_TRACK) }
        }

        controlsLayout.addView(prevBtn)
        controlsLayout.addView(playPauseButton)
        controlsLayout.addView(nextBtn)
        root.addView(controlsLayout)

        // 5. Volume Controls Row
        val volumeLayout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, 24, 0, 32)
        }

        val volDownBtn = Button(this).apply {
            text = "🔉 Vol -"
            setOnClickListener { BLEMediaService.instance?.sendBLECommand(BLEMediaService.CMD_VOLUME_DOWN) }
        }
        val volUpBtn = Button(this).apply {
            text = "🔊 Vol +"
            setOnClickListener { BLEMediaService.instance?.sendBLECommand(BLEMediaService.CMD_VOLUME_UP) }
        }

        volumeLayout.addView(volDownBtn)
        volumeLayout.addView(volUpBtn)
        root.addView(volumeLayout)

        // Flexible spacer to push footer to bottom
        val spacer = View(this)
        val spacerParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            0,
            1.0f
        )
        root.addView(spacer, spacerParams)

        // 6. Minimal, soothing footer with version & support on separate lines
        val versionText = TextView(this).apply {
            text = "v1.0.0"
            setTextColor(Color.parseColor("#555555"))
            textSize = 11f
            gravity = Gravity.CENTER
        }
        root.addView(versionText)

        val supportText = TextView(this).apply {
            text = "Support ♡"
            setTextColor(Color.parseColor("#666666"))
            textSize = 12f
            gravity = Gravity.CENTER
            setPadding(0, 4, 0, 8)
            setOnClickListener {
                try {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://anisharyal09.com.np/support?from=yt-audio-air-phone"))
                    startActivity(intent)
                } catch (e: Exception) {}
            }
        }
        root.addView(supportText)

        setContentView(root)

        checkPermissionsAndStartService()
    }

    override fun onResume() {
        super.onResume()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(statusReceiver, IntentFilter(BLEMediaService.ACTION_BLE_STATUS), RECEIVER_EXPORTED)
        } else {
            registerReceiver(statusReceiver, IntentFilter(BLEMediaService.ACTION_BLE_STATUS))
        }

        BLEMediaService.instance?.let { service ->
            localIsPlaying = service.isMediaPlaying
            updateUI(service.connectionStatus, service.currentTitle, service.currentArtist, localIsPlaying)
        }
    }

    override fun onPause() {
        super.onPause()
        try {
            unregisterReceiver(statusReceiver)
        } catch (e: Exception) {}
    }

    private fun updateUI(status: String, title: String, artist: String, isPlaying: Boolean) {
        statusTextView.text = if (status.contains("Ready") || status.contains("Connected")) "● $status" else "○ $status"
        if (status.contains("Ready") || status.contains("Connected")) {
            statusTextView.setTextColor(Color.parseColor("#4CAF50"))
        } else {
            statusTextView.setTextColor(Color.parseColor("#FFA500"))
        }

        titleTextView.text = if (title.isNotEmpty()) title else "YT Audio Air"
        artistTextView.text = if (artist.isNotEmpty()) artist else "YouTube"

        playPauseButton.text = if (isPlaying) "⏸ Pause" else "▶ Play"
    }

    private fun checkPermissionsAndStartService() {
        val permissionsNeeded = mutableListOf<String>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                permissionsNeeded.add(Manifest.permission.BLUETOOTH_CONNECT)
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) {
                permissionsNeeded.add(Manifest.permission.BLUETOOTH_SCAN)
            }
        } else {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                permissionsNeeded.add(Manifest.permission.ACCESS_FINE_LOCATION)
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                permissionsNeeded.add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }

        if (permissionsNeeded.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, permissionsNeeded.toTypedArray(), PERMISSION_REQUEST_CODE)
        } else {
            startBLEService()
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        startBLEService()
    }

    private fun startBLEService() {
        try {
            val serviceIntent = Intent(this, BLEMediaService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
