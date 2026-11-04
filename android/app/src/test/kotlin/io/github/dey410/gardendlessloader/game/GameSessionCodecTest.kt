package io.github.dey410.gardendlessloader.game

import org.json.JSONObject
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GameSessionCodecTest {
    private fun sessionJson(): JSONObject = JSONObject(
        """
        {
          "schemaVersion": 1,
          "sessionId": "session-1",
          "resourceRoot": "/tmp/gardendless/slot-a",
          "platform": "android",
          "origin": "https://appassets.androidplatform.net",
          "entryUrl": "https://appassets.androidplatform.net/index.html?generation=7",
          "activationGeneration": 7,
          "hasGpNext": true,
          "gpNextCompatible": true,
          "gpNextVersion": "1.4.2",
          "watermarkEnabled": true,
          "autoCollectSunEnabled": false,
          "allowedRemoteHosts": ["pvzge.com"],
          "gpNextRoot": "/tmp/gardendless/gp-next",
          "exportTemporaryRoot": "/tmp/gardendless/gp-next/.exports"
        }
        """.trimIndent(),
    )

    @Test
    fun `missing canvas frame defaults on for older prepared sessions`() {
        assertTrue(
            GameSessionCodec.decode(sessionJson().toString()).canvasFrameEnabled,
        )
    }

    @Test
    fun `explicit canvas frame false disables the frame`() {
        assertFalse(
            GameSessionCodec.decode(
                sessionJson().put("canvasFrameEnabled", false).toString(),
            ).canvasFrameEnabled,
        )
    }

    @Test
    fun `explicit canvas frame true keeps the frame`() {
        assertTrue(
            GameSessionCodec.decode(
                sessionJson().put("canvasFrameEnabled", true).toString(),
            ).canvasFrameEnabled,
        )
    }
}
