package io.github.dey410.gardendlessloader.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ReferenceNativeTouchStateMachineTest {
    @Test
    fun `single finger uses JavaScript down and up with native moves only`() {
        val machine = ReferenceNativeTouchStateMachine()
        val start = NativeTouchPoint(40f, 30f)
        val moved = NativeTouchPoint(180f, 90f)

        assertTrue(machine.handle(NativeTouchPhase.DOWN, listOf(start)).isEmpty())
        assertEquals(
            listOf(NativeTouchCommand.Move(moved, buttons = 1)),
            machine.handle(NativeTouchPhase.MOVE, listOf(moved)),
        )
        assertTrue(machine.handle(NativeTouchPhase.UP, emptyList()).isEmpty())
    }

    @Test
    fun `second finger abandons primary drag with a neutral center move`() {
        val machine = ReferenceNativeTouchStateMachine()
        machine.handle(NativeTouchPhase.DOWN, listOf(NativeTouchPoint(40f, 40f)))

        assertEquals(
            listOf(NativeTouchCommand.Move(NativeTouchPoint(100f, 60f), buttons = 0)),
            machine.handle(
                NativeTouchPhase.POINTER_DOWN,
                listOf(NativeTouchPoint(60f, 60f), NativeTouchPoint(140f, 60f)),
            ),
        )
        machine.handle(NativeTouchPhase.POINTER_UP, listOf(NativeTouchPoint(60f, 60f)))
        assertTrue(
            machine.handle(
                NativeTouchPhase.MOVE,
                listOf(NativeTouchPoint(80f, 80f)),
            ).isEmpty(),
        )
    }

    @Test
    fun `two finger scroll starts beyond twenty physical pixels`() {
        val machine = ReferenceNativeTouchStateMachine()
        machine.handle(NativeTouchPhase.DOWN, listOf(NativeTouchPoint(80f, 100f)))
        machine.handle(
            NativeTouchPhase.POINTER_DOWN,
            listOf(NativeTouchPoint(80f, 100f), NativeTouchPoint(120f, 100f)),
        )

        assertTrue(
            machine.handle(
                NativeTouchPhase.MOVE,
                listOf(NativeTouchPoint(80f, 120f), NativeTouchPoint(120f, 120f)),
            ).isEmpty(),
        )
        assertEquals(
            listOf(
                NativeTouchCommand.Scroll(
                    point = NativeTouchPoint(100f, 121f),
                    axisValue = 2f / 15f,
                ),
            ),
            machine.handle(
                NativeTouchPhase.MOVE,
                listOf(NativeTouchPoint(80f, 121f), NativeTouchPoint(120f, 121f)),
            ),
        )
    }

    @Test
    fun `cancel clears native gesture without compensation`() {
        val machine = ReferenceNativeTouchStateMachine()
        machine.handle(NativeTouchPhase.DOWN, listOf(NativeTouchPoint(20f, 20f)))
        assertTrue(machine.handle(NativeTouchPhase.CANCEL, emptyList()).isEmpty())
        assertTrue(
            machine.handle(
                NativeTouchPhase.MOVE,
                listOf(NativeTouchPoint(30f, 30f)),
            ).isEmpty(),
        )
    }

    @Test
    fun `three fingers block native output until every finger is lifted`() {
        val machine = ReferenceNativeTouchStateMachine()
        val first = NativeTouchPoint(20f, 20f)
        val second = NativeTouchPoint(40f, 20f)
        val third = NativeTouchPoint(60f, 20f)

        machine.handle(NativeTouchPhase.DOWN, listOf(first))
        machine.handle(NativeTouchPhase.POINTER_DOWN, listOf(first, second))
        assertTrue(
            machine.handle(
                NativeTouchPhase.POINTER_DOWN,
                listOf(first, second, third),
            ).isEmpty(),
        )
        assertTrue(
            machine.handle(
                NativeTouchPhase.MOVE,
                listOf(first, second),
            ).isEmpty(),
        )
        assertTrue(machine.handle(NativeTouchPhase.UP, emptyList()).isEmpty())
        assertTrue(machine.handle(NativeTouchPhase.DOWN, listOf(first)).isEmpty())
        assertEquals(
            listOf(
                NativeTouchCommand.Move(
                    NativeTouchPoint(30f, 30f),
                    buttons = 1,
                ),
            ),
            machine.handle(
                NativeTouchPhase.MOVE,
                listOf(NativeTouchPoint(30f, 30f)),
            ),
        )
    }
}
