package io.github.dey410.gardendlessloader

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.github.dey410.gardendlessloader.game.GameActivity

/**
 * Routes launches that come from outside the launcher: a ZIP another app
 * opens or shares, and home-screen shortcuts. While a game runs, the ZIP
 * waits in the game until the player returns, and a shortcut only brings
 * the game back, so nothing replaces the slot the game is reading.
 */
class LaunchRouterActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val zip: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            }
            else -> null
        }
        val shortcut = intent.getStringExtra(MainActivity.EXTRA_SHORTCUT)
            ?.takeIf { intent.action == MainActivity.ACTION_SHORTCUT }
        val forward = when {
            zip != null -> Intent(
                this,
                if (GameActivity.running) GameActivity::class.java else MainActivity::class.java,
            ).apply {
                action = MainActivity.ACTION_IMPORT_ZIP
                data = zip
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            GameActivity.running -> Intent(this, GameActivity::class.java)
            shortcut != null -> Intent(this, MainActivity::class.java).apply {
                action = MainActivity.ACTION_SHORTCUT
                putExtra(MainActivity.EXTRA_SHORTCUT, shortcut)
            }
            else -> null
        }
        if (forward != null) {
            forward.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            startActivity(forward)
        }
        finish()
    }
}
