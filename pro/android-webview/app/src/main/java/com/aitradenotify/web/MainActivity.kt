package com.aitradenotify.web

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.os.Bundle
import android.view.View
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.EditText
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout

// ============================== SETTINGS ==============================
// Address of your api_server.py. At home: http://<your-PC-IP>:5000
// On a cloud server with HTTPS: https://your-domain.com
const val DEFAULT_SERVER_URL = "http://192.168.1.10:5000"
// ======================================================================

class MainActivity : AppCompatActivity() {

    private lateinit var web: WebView
    private lateinit var swipe: SwipeRefreshLayout
    private lateinit var errorView: TextView
    private val prefs by lazy { getSharedPreferences("settings", MODE_PRIVATE) }

    private val serverUrl: String
        get() = prefs.getString("server_url", null) ?: DEFAULT_SERVER_URL

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        web = findViewById(R.id.web)
        swipe = findViewById(R.id.swipe)
        errorView = findViewById(R.id.error)

        web.settings.javaScriptEnabled = true
        web.settings.domStorageEnabled = true
        web.setBackgroundColor(0xFF0A0F1E.toInt())
        web.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                errorView.visibility = View.GONE
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                swipe.isRefreshing = false
            }

            override fun onReceivedError(view: WebView?, request: WebResourceRequest?, error: WebResourceError?) {
                if (request?.isForMainFrame == true) {
                    swipe.isRefreshing = false
                    errorView.text = getString(R.string.cannot_connect, serverUrl)
                    errorView.visibility = View.VISIBLE
                }
            }
        }

        swipe.setOnRefreshListener { web.reload() }
        // Tap the error message, or long-press the page, to change the server address.
        errorView.setOnClickListener { askServerUrl() }
        web.setOnLongClickListener { askServerUrl(); true }

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (web.canGoBack()) web.goBack() else finish()
            }
        })

        if (prefs.getString("server_url", null) == null) askServerUrl() else web.loadUrl(serverUrl)
    }

    private fun askServerUrl() {
        val input = EditText(this).apply {
            setText(serverUrl)
            setSingleLine()
        }
        AlertDialog.Builder(this)
            .setTitle(R.string.server_title)
            .setMessage(R.string.server_message)
            .setView(input)
            .setCancelable(false)
            .setPositiveButton(R.string.connect) { _, _ ->
                var url = input.text.toString().trim().trimEnd('/')
                if (!url.startsWith("http")) url = "http://$url"
                prefs.edit().putString("server_url", url).apply()
                web.loadUrl(url)
            }
            .show()
    }
}
