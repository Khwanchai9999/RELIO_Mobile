package com.relio.relio_mobile

import android.app.Activity
import android.app.AlertDialog
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.MediaController
import android.widget.VideoView
import java.io.File

class RelioVideoPlayerActivity : Activity() {
    private lateinit var videoView: VideoView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val requestedPath = intent.getStringExtra(EXTRA_PATH)
        val mediaRoot = File(filesDir, "relio_media").canonicalPath + File.separator
        val video = try {
            requestedPath?.let { File(it).canonicalFile }
        } catch (_: Exception) {
            null
        }
        if (video == null || !video.isFile || !video.path.startsWith(mediaRoot)) {
            showPlaybackError()
            return
        }

        window.statusBarColor = Color.BLACK
        window.navigationBarColor = Color.BLACK
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.BLACK)
        }
        val back = Button(this).apply {
            text = "‹  กลับไปแชท"
            contentDescription = "กลับไปแชท"
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
            setOnClickListener { finish() }
        }
        root.addView(
            back,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )

        videoView = VideoView(this).apply {
            contentDescription = "วิดีโอที่ได้รับ"
            val controls = MediaController(this@RelioVideoPlayerActivity)
            controls.setAnchorView(this)
            setMediaController(controls)
            setOnPreparedListener { player ->
                player.isLooping = false
                start()
            }
            setOnErrorListener { _, _, _ ->
                showPlaybackError()
                true
            }
        }
        root.addView(
            videoView,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )
        setContentView(
            FrameLayout(this).apply { addView(root) },
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        videoView.setVideoURI(Uri.fromFile(video))
    }

    private fun showPlaybackError() {
        if (isFinishing) return
        AlertDialog.Builder(this)
            .setMessage("ไม่สามารถเล่นวิดีโอนี้ได้")
            .setPositiveButton("ปิด") { _, _ -> finish() }
            .setOnCancelListener { finish() }
            .show()
    }

    override fun onPause() {
        if (::videoView.isInitialized && videoView.isPlaying) videoView.pause()
        super.onPause()
    }

    companion object {
        const val EXTRA_PATH = "relio_video_path"
    }
}
