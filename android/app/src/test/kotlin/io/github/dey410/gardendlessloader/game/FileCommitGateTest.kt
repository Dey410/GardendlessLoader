package io.github.dey410.gardendlessloader.game

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

class FileCommitGateTest {
    @Test fun stoppedHostCannotCommit() {
        val gate = FileCommitGate()
        assertTrue(gate.stop())
        assertFalse(gate.stop())
        var wrote = false
        try {
            gate.commit { wrote = true }
            fail("stopped host committed")
        } catch (_: IllegalStateException) { }
        assertFalse(wrote)
    }

    @Test fun stopWaitsForCommitAndPreventsEveryLaterCommit() {
        val gate = FileCommitGate()
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val stopping = CountDownLatch(1)
        val stopped = CountDownLatch(1)
        val writer = thread {
            gate.commit { entered.countDown(); assertTrue(release.await(2, TimeUnit.SECONDS)) }
        }
        assertTrue(entered.await(2, TimeUnit.SECONDS))
        val closer = thread { stopping.countDown(); gate.stop(); stopped.countDown() }
        assertTrue(stopping.await(2, TimeUnit.SECONDS))
        assertFalse(stopped.await(50, TimeUnit.MILLISECONDS))
        release.countDown()
        assertTrue(stopped.await(2, TimeUnit.SECONDS))
        writer.join(); closer.join()
        assertFalse(gate.active)
        try { gate.commit { fail("late commit") }; fail("late commit accepted") }
        catch (_: IllegalStateException) { }
    }
}
