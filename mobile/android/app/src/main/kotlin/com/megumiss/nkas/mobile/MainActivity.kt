package com.megumiss.nkas.mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private lateinit var platformBridge: NkasPlatformBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        platformBridge = NkasPlatformBridge(this)
        platformBridge.register(flutterEngine)
        platformBridge.handleIntent(intent)
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (::platformBridge.isInitialized) platformBridge.handleIntent(intent)
    }

    override fun onDestroy() {
        if (::platformBridge.isInitialized) platformBridge.close()
        super.onDestroy()
    }
}
