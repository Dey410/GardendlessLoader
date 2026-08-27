package io.github.dey410.gardendlessloader.game

import android.content.Context
import android.os.SystemClock
import android.util.AttributeSet
import android.view.InputDevice
import android.view.MotionEvent
import android.webkit.WebView

class MouseGameWebView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : WebView(context, attrs) {
    var referenceTouchAdapterEnabled = true
    private val touchStateMachine = ReferenceNativeTouchStateMachine()
    private var mouseDownTime = 0L

    init {
        setLongClickable(false)
        setOnLongClickListener { true }
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        val isActualMouse = event.pointerCount > 0 &&
            event.getToolType(event.actionIndex) == MotionEvent.TOOL_TYPE_MOUSE
        if (!referenceTouchAdapterEnabled || isActualMouse) {
            return super.dispatchTouchEvent(event)
        }

        val touchHandled = super.dispatchTouchEvent(event)
        val phase = event.actionMasked.toNativeTouchPhase() ?: return touchHandled
        val points = List(event.pointerCount) { index ->
            NativeTouchPoint(event.getX(index), event.getY(index))
        }
        val commands = touchStateMachine.handle(phase, points)
        val injectedMouseEvent = commands.isNotEmpty()
        for (command in commands) {
            when (command) {
                is NativeTouchCommand.Down -> injectMouseButton(
                    action = MotionEvent.ACTION_DOWN,
                    point = command.point,
                )
                is NativeTouchCommand.Move -> injectMouseMove(command)
                is NativeTouchCommand.Up -> injectMouseButton(
                    action = MotionEvent.ACTION_UP,
                    point = command.point,
                )
                is NativeTouchCommand.Scroll -> injectMouseScroll(command)
            }
        }
        return touchHandled || injectedMouseEvent
    }

    private fun injectMouseButton(
        action: Int,
        point: NativeTouchPoint,
    ) {
        val event = obtainMouseEvent(
            action = action,
            point = point,
            buttonState = MotionEvent.BUTTON_PRIMARY,
        )
        try {
            super.dispatchTouchEvent(event)
        } finally {
            event.recycle()
            if (action == MotionEvent.ACTION_UP) {
                mouseDownTime = 0L
            }
        }
    }

    private fun injectMouseMove(command: NativeTouchCommand.Move) {
        val event = obtainMouseEvent(
            action = MotionEvent.ACTION_MOVE,
            point = command.point,
            buttonState = command.buttons,
        )
        try {
            super.dispatchTouchEvent(event)
        } finally {
            event.recycle()
        }
    }

    private fun injectMouseScroll(command: NativeTouchCommand.Scroll) {
        val event = obtainMouseEvent(
            action = MotionEvent.ACTION_SCROLL,
            point = command.point,
            buttonState = 0,
            verticalScroll = command.axisValue,
        )
        try {
            super.dispatchGenericMotionEvent(event)
        } finally {
            event.recycle()
        }
    }

    private fun obtainMouseEvent(
        action: Int,
        point: NativeTouchPoint,
        buttonState: Int,
        verticalScroll: Float? = null,
    ): MotionEvent {
        val pointerProperties = arrayOf(
            MotionEvent.PointerProperties().apply {
                id = 0
                toolType = MotionEvent.TOOL_TYPE_MOUSE
            },
        )
        val pointerCoordinates = arrayOf(
            MotionEvent.PointerCoords().apply {
                this.x = point.x
                this.y = point.y
                verticalScroll?.let { setAxisValue(MotionEvent.AXIS_VSCROLL, it) }
            },
        )
        val now = SystemClock.uptimeMillis()
        if (action == MotionEvent.ACTION_DOWN) {
            mouseDownTime = now
        }
        val gestureDownTime = mouseDownTime.takeIf { it > 0L } ?: now
        return MotionEvent.obtain(
            gestureDownTime,
            now,
            action,
            1,
            pointerProperties,
            pointerCoordinates,
            0,
            buttonState,
            1f,
            1f,
            0,
            0,
            InputDevice.SOURCE_MOUSE,
            0,
        )
    }

    private fun Int.toNativeTouchPhase(): NativeTouchPhase? = when (this) {
        MotionEvent.ACTION_DOWN -> NativeTouchPhase.DOWN
        MotionEvent.ACTION_MOVE -> NativeTouchPhase.MOVE
        MotionEvent.ACTION_UP -> NativeTouchPhase.UP
        MotionEvent.ACTION_POINTER_DOWN -> NativeTouchPhase.POINTER_DOWN
        MotionEvent.ACTION_POINTER_UP -> NativeTouchPhase.POINTER_UP
        MotionEvent.ACTION_CANCEL -> NativeTouchPhase.CANCEL
        else -> null
    }
}
