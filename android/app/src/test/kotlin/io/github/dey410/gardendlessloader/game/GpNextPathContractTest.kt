package io.github.dey410.gardendlessloader.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.File

class GpNextPathContractTest {
    private val root = File("/data/gardendless/gp-next")

    @Test
    fun `AppData GP-Next paths use the explicit sandbox root`() {
        assertEquals(
            File(root, "configuration-state.json").absoluteFile,
            resolveGpNextSandboxPath(root, "gp-next/configuration-state.json"),
        )
        assertEquals(root.absoluteFile, resolveGpNextSandboxPath(root, "gp-next"))
    }

    @Test
    fun `foreign relative and traversal paths stay rejected`() {
        assertThrows(IllegalArgumentException::class.java) {
            resolveGpNextSandboxPath(root, "settings.json")
        }
        assertThrows(IllegalArgumentException::class.java) {
            resolveGpNextSandboxPath(root, "gp-next/../settings.json")
        }
        assertThrows(IllegalArgumentException::class.java) {
            resolveGpNextSandboxPath(root, "gp-next/./settings.json")
        }
    }
}
