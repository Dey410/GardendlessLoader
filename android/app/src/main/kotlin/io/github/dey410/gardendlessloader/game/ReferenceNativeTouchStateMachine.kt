package io.github.dey410.gardendlessloader.game

internal data class NativeTouchPoint(
    val x: Float,
    val y: Float,
)

internal enum class NativeTouchPhase {
    DOWN,
    MOVE,
    UP,
    POINTER_DOWN,
    POINTER_UP,
    CANCEL,
}

internal sealed interface NativeTouchCommand {
    data class Down(
        val point: NativeTouchPoint,
    ) : NativeTouchCommand

    data class Move(
        val point: NativeTouchPoint,
        val buttons: Int,
    ) : NativeTouchCommand

    data class Up(
        val point: NativeTouchPoint,
    ) : NativeTouchCommand

    data class Scroll(
        val point: NativeTouchPoint,
        val axisValue: Float,
    ) : NativeTouchCommand
}

internal class ReferenceNativeTouchStateMachine {
    private var primaryActive = false
    private var blocked = false
    private var twoFingerStart: NativeTouchPoint? = null
    private var lastTwoFingerPoint: NativeTouchPoint? = null
    private var twoFingerMoved = false

    fun handle(
        phase: NativeTouchPhase,
        points: List<NativeTouchPoint>,
    ): List<NativeTouchCommand> {
        if (phase == NativeTouchPhase.CANCEL) {
            reset()
            return emptyList()
        }
        if (points.size >= 3) {
            primaryActive = false
            blocked = true
            twoFingerStart = null
            lastTwoFingerPoint = null
            twoFingerMoved = false
            return emptyList()
        }
        if (blocked) {
            if (phase == NativeTouchPhase.UP || phase == NativeTouchPhase.POINTER_UP) {
                reset()
            }
            return emptyList()
        }

        return when (phase) {
            NativeTouchPhase.DOWN -> {
                reset()
                primaryActive = points.size == 1
                if (primaryActive) {
                    listOf(NativeTouchCommand.Down(points.single()))
                } else {
                    emptyList()
                }
            }

            NativeTouchPhase.MOVE -> handleMove(points)
            NativeTouchPhase.POINTER_DOWN -> handlePointerDown(points)
            NativeTouchPhase.UP -> {
                val commands = if (primaryActive && points.size == 1) {
                    listOf(NativeTouchCommand.Up(points.single()))
                } else {
                    emptyList()
                }
                reset()
                commands
            }

            NativeTouchPhase.POINTER_UP -> {
                reset()
                emptyList()
            }

            NativeTouchPhase.CANCEL -> emptyList()
        }
    }

    private fun handlePointerDown(points: List<NativeTouchPoint>): List<NativeTouchCommand> {
        if (points.size != 2) {
            return emptyList()
        }
        primaryActive = false
        val center = center(points)
        twoFingerStart = center
        lastTwoFingerPoint = center
        twoFingerMoved = false
        return listOf(NativeTouchCommand.Move(center, buttons = 0))
    }

    private fun handleMove(points: List<NativeTouchPoint>): List<NativeTouchCommand> {
        if (points.size == 1 && primaryActive) {
            return listOf(NativeTouchCommand.Move(points.single(), buttons = 1))
        }
        if (points.size != 2) {
            return emptyList()
        }
        val start = twoFingerStart ?: return emptyList()
        val previous = lastTwoFingerPoint ?: start
        val current = center(points)
        if (!twoFingerMoved && kotlin.math.abs(current.y - start.y) > 20f) {
            twoFingerMoved = true
        }
        lastTwoFingerPoint = current
        if (!twoFingerMoved) {
            return emptyList()
        }
        val axisValue = (current.y - previous.y) * 2f / 15f
        return if (axisValue == 0f) {
            emptyList()
        } else {
            listOf(NativeTouchCommand.Scroll(current, axisValue))
        }
    }

    private fun center(points: List<NativeTouchPoint>): NativeTouchPoint = NativeTouchPoint(
        x = points.sumOf { it.x.toDouble() }.toFloat() / points.size,
        y = points.sumOf { it.y.toDouble() }.toFloat() / points.size,
    )

    private fun reset() {
        primaryActive = false
        blocked = false
        twoFingerStart = null
        lastTwoFingerPoint = null
        twoFingerMoved = false
    }
}
