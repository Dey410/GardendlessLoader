package io.github.dey410.gardendlessloader.game

import android.content.Context
import android.util.AttributeSet
import android.view.InputDevice
import android.view.MotionEvent
import android.webkit.WebView

class MouseGameWebView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : WebView(context, attrs) {
    private var maxTouches = 0
    private var isDragging = false

    init {
        setLongClickable(false)
        setOnLongClickListener { true }
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (event.source == InputDevice.SOURCE_MOUSE) {
            return super.dispatchTouchEvent(event)
        }

        val action = event.actionMasked
        val pointerCount = event.pointerCount
        if (pointerCount > maxTouches) {
            maxTouches = pointerCount
        }

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

        return super.dispatchTouchEvent(event)
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
        val now = System.currentTimeMillis()
        val mouseEvent = MotionEvent.obtain(
            now,
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
        }
    }
}
