package io.github.dey410.gardendlessloader

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DocumentPickerOrientationPolicyTest {
    @Test
    fun `uses portrait when the window width is compact`() {
        assertTrue(DocumentPickerOrientationPolicy.isCompact(599, 900))
    }

    @Test
    fun `uses portrait when the window height is compact`() {
        assertTrue(DocumentPickerOrientationPolicy.isCompact(900, 599))
    }

    @Test
    fun `lets the system choose at the 600dp boundary`() {
        assertFalse(DocumentPickerOrientationPolicy.isCompact(600, 600))
    }

    @Test
    fun `lets the system choose for a large landscape window`() {
        assertFalse(DocumentPickerOrientationPolicy.isCompact(1280, 800))
    }
}
