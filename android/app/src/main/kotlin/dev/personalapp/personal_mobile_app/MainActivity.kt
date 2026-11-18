package dev.personalapp.personal_mobile_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        /** The intent extra a widget button sets: "sketch:new", "sketch:<note id>" or "jar:add". */
        const val EXTRA_OPEN = "dev.personalapp.personal_mobile_app.OPEN"
    }

    private var channel: MethodChannel? = null

    /** What a widget button asked to open (see EXTRA_OPEN), until Flutter takes it. */
    private var pending: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pending = intent?.getStringExtra(EXTRA_OPEN)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hyeti/launch").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "take") {
                    result.success(pending)
                    pending = null
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    // The app was already running when a widget button was tapped.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val open = intent.getStringExtra(EXTRA_OPEN) ?: return
        channel?.invokeMethod("open", open)
    }

    override fun onPause() {
        super.onPause()
        // Whatever changed in the app shows on the home-screen widgets as soon as the app is left.
        SketchWidget.render(this)
        JarWidget.render(this)
    }
}
