package com.megumiss.nkas

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout

/** NKAS UI 页：承载本地 Web UI 的 WebView，切页时保留实例避免重新加载。 */
class UiPage(private val activity: Activity) {
    private var webView: WebView? = null

    fun show(container: FrameLayout) {
        val view = webView ?: createWebView().also { webView = it }
        container.addView(view, FrameLayout.LayoutParams(-1, -1))
        val target = SettingsStore.webUiApiUrl(activity, "/app/")
        val current = view.url?.let { Uri.parse(it) }
        val configured = Uri.parse(SettingsStore.webUiUrl(activity))
        if (current == null || current.scheme != configured.scheme || current.host != configured.host || current.port != configured.port) {
            view.loadUrl(target)
        }
    }

    fun goBack(): Boolean {
        val view = webView ?: return false
        if (!view.canGoBack()) return false
        view.goBack()
        return true
    }

    fun destroy() {
        webView?.destroy()
        webView = null
    }

    private fun createWebView() = WebView(activity).apply {
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val uri = request.url
                val configuredHost = SettingsStore.webUiHost(activity)
                if (uri.host.equals(configuredHost, ignoreCase = true) || uri.host == "127.0.0.1" || uri.host == "localhost") return false
                activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(uri.toString())))
                return true
            }
        }
    }
}
