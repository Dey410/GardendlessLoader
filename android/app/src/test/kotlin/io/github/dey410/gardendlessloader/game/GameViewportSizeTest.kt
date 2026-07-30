package io.github.dey410.gardendlessloader.game

import org.junit.Assert.assertEquals
import org.junit.Test

class GameViewportSizeTest {
    @Test
    fun `square-ish windows are limited to 16 by 10`() {
        assertEquals(1600 to 1000, GameViewportSize.fit(1600, 1200))
        assertEquals(1400 to 875, GameViewportSize.fit(1400, 1000))
    }

    @Test
    fun `supported aspect ratios fill the window`() {
        assertEquals(1600 to 1000, GameViewportSize.fit(1600, 1000))
        assertEquals(1920 to 1080, GameViewportSize.fit(1920, 1080))
        assertEquals(1700 to 900, GameViewportSize.fit(1700, 900))
    }

    @Test
    fun `ultrawide windows are limited to 17 by 9`() {
        assertEquals(2040 to 1080, GameViewportSize.fit(2400, 1080))
        assertEquals(1700 to 900, GameViewportSize.fit(2100, 900))
    }

    @Test
    fun `invalid dimensions produce an empty viewport`() {
        assertEquals(0 to 0, GameViewportSize.fit(0, 1080))
        assertEquals(0 to 0, GameViewportSize.fit(1920, 0))
    }
}
