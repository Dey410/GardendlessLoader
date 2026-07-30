package io.github.dey410.gardendlessloader.game

import android.content.Context
import android.graphics.Color
import android.view.View
import android.widget.FrameLayout
import kotlin.math.floor

internal object GameViewportSize {
    private const val MIN_ASPECT_RATIO = 16.0 / 10.0
    private const val MAX_ASPECT_RATIO = 17.0 / 9.0

    fun fit(width: Int, height: Int): Pair<Int, Int> {
        if (width <= 0 || height <= 0) return 0 to 0
        val aspectRatio = width.toDouble() / height
        return when {
            aspectRatio > MAX_ASPECT_RATIO ->
                floor(height * MAX_ASPECT_RATIO).toInt() to height
            aspectRatio < MIN_ASPECT_RATIO ->
                width to floor(width / MIN_ASPECT_RATIO).toInt()
            else -> width to height
        }
    }
}

internal class GameViewportLayout(context: Context) : FrameLayout(context) {
    init {
        setBackgroundColor(Color.BLACK)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val height = MeasureSpec.getSize(heightMeasureSpec)
        setMeasuredDimension(width, height)
        if (childCount == 0) return

        val (viewportWidth, viewportHeight) = GameViewportSize.fit(width, height)
        val childWidthSpec = MeasureSpec.makeMeasureSpec(viewportWidth, MeasureSpec.EXACTLY)
        val childHeightSpec = MeasureSpec.makeMeasureSpec(viewportHeight, MeasureSpec.EXACTLY)
        for (index in 0 until childCount) {
            getChildAt(index).measure(childWidthSpec, childHeightSpec)
        }
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val width = right - left
        val height = bottom - top
        for (index in 0 until childCount) {
            val child: View = getChildAt(index)
            val childLeft = (width - child.measuredWidth) / 2
            val childTop = (height - child.measuredHeight) / 2
            child.layout(
                childLeft,
                childTop,
                childLeft + child.measuredWidth,
                childTop + child.measuredHeight,
            )
        }
    }
}
