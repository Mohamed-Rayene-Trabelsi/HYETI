package dev.personalapp.personal_mobile_app

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onPause() {
        super.onPause()
        // Whatever was changed in the app shows on the home-screen widget as soon as the app is left.
        UpNextWidget.render(this)
    }
}
