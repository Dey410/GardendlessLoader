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
    var nativeSingleTouchMouseEnabled = true
    private var maxTouches = 0
    private var isDragging = false
    private var mouseDownTime = 0L

    init {
        setLongClickable(false)
        setOnLongClickListener { true }
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (!nativeSingleTouchMouseEnabled || event.source == InputDevice.SOURCE_MOUSE) {
            return super.dispatchTouchEvent(event)
        }

        val action = event.actionMasked
        val pointerCount = event.pointerCount
        if (pointerCount > maxTouches) {
            maxTouches = pointerCount
        }
        val touchHandled = super.dispatchTouchEvent(event)
        when (action) {
            MotionEvent.ACTION_DOWN -> {
                if (pointerCount == 1) {
                    injectMouseEventAt(
                        event.x,
                        event.y,
                        MotionEvent.ACTION_DOWN,
                        MotionEvent.BUTTON_PRIMARY,
                    )
                    isDragging = true
                }
            }

            MotionEvent.ACTION_MOVE -> {
                if (pointerCount == 1 && isDragging) {
                    injectMouseEventAt(
                        event.x,
                        event.y,
                        MotionEvent.ACTION_MOVE,
                        MotionEvent.BUTTON_PRIMARY,
                    )
                }
            }

            MotionEvent.ACTION_POINTER_DOWN -> {
                if (pointerCount == 2) {
                    isDragging = false
                    injectMouseEventAt(
                        (event.getX(0) + event.getX(1)) / 2,
                        (event.getY(0) + event.getY(1)) / 2,
                        MotionEvent.ACTION_MOVE,
                        0,
                    )
                }
            }

            MotionEvent.ACTION_UP,
            MotionEvent.ACTION_POINTER_UP,
            -> {
                if (maxTouches == 1 && isDragging) {
                    injectMouseEventAt(
                        event.x,
                        event.y,
                        MotionEvent.ACTION_UP,
                        MotionEvent.BUTTON_PRIMARY,
                    )
                }
                maxTouches = 0
                isDragging = false
            }
        }

        return touchHandled
    }

    private fun injectMouseEventAt(
        x: Float,
        y: Float,
        action: Int,
        buttonState: Int,
    ) {
        val pointerProperties = arrayOf(
            MotionEvent.PointerProperties().apply {
                id = 0
                toolType = MotionEvent.TOOL_TYPE_MOUSE
            },
        )
        val pointerCoordinates = arrayOf(
            MotionEvent.PointerCoords().apply {
                this.x = x
                this.y = y
            },
        )
        val now = SystemClock.uptimeMillis()
        if (action == MotionEvent.ACTION_DOWN) {
            mouseDownTime = now
        }
        val gestureDownTime = mouseDownTime.takeIf { it > 0L } ?: now
        val mouseEvent = MotionEvent.obtain(
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
        try {
            super.dispatchTouchEvent(mouseEvent)
        } finally {
            mouseEvent.recycle()
            if (action == MotionEvent.ACTION_UP) {
                mouseDownTime = 0L
            }
        }
    }
}
