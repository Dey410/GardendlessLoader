package io.github.dey410.gardendlessloader.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class FileTransferCursorTest {
    @Test
    fun `empty transfer commits without a chunk`() {
        FileTransferCursor(0).requireComplete()
    }

    @Test
    fun `exact 64 KiB chunks and a final subview preserve byte positions`() {
        val cursor = FileTransferCursor(65_539)
        cursor.validate(0, 0, 65_536)
        cursor.advance(65_536)
        cursor.validate(1, 65_536, 3)
        cursor.advance(3)
        cursor.requireComplete()
        assertEquals(65_539L, cursor.offset)
        assertEquals(2, cursor.nextIndex)
    }

    @Test
    fun `out of order duplicate or wrong offset chunks fail before advancement`() {
        val cursor = FileTransferCursor(10)
        assertThrows(IllegalArgumentException::class.java) { cursor.validate(1, 0, 1) }
        assertThrows(IllegalArgumentException::class.java) { cursor.validate(0, 1, 1) }
        cursor.validate(0, 0, 1)
        cursor.advance(1)
        assertThrows(IllegalArgumentException::class.java) { cursor.validate(0, 0, 1) }
        assertEquals(1L, cursor.offset)
    }

    @Test
    fun `oversize zero length and bytes beyond declared length are rejected`() {
        val cursor = FileTransferCursor(65_536)
        assertThrows(IllegalArgumentException::class.java) { cursor.validate(0, 0, 65_537) }
        assertThrows(IllegalArgumentException::class.java) { cursor.validate(0, 0, 0) }
        val short = FileTransferCursor(2)
        assertThrows(IllegalArgumentException::class.java) { short.validate(0, 0, 3) }
        assertThrows(IllegalArgumentException::class.java) { short.requireComplete() }
    }
}
