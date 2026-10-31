package io.github.dey410.gardendlessloader.game

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.view.View
import android.widget.FrameLayout
import kotlin.math.floor

internal object GameViewportSize {
    private const val MIN_ASPECT_RATIO = 16.0 / 10.0
    private const val MAX_ASPECT_RATIO = 17.0 / 9.0

    /** Show all keeps the whole 17:9 picture; the other fits allow 16:10–17:9. */
    fun fit(width: Int, height: Int, screenFit: GameScreenFit): Pair<Int, Int> {
        if (width <= 0 || height <= 0) return 0 to 0
        val minAspectRatio =
            if (screenFit == GameScreenFit.SHOW_ALL) MAX_ASPECT_RATIO else MIN_ASPECT_RATIO
        val aspectRatio = width.toDouble() / height
        return when {
            aspectRatio > MAX_ASPECT_RATIO ->
                floor(height * MAX_ASPECT_RATIO).toInt() to height
            aspectRatio < minAspectRatio ->
                width to floor(width / minAspectRatio).toInt()
            else -> width to height
        }
    }
}

internal class GameViewportLayout(
    context: Context,
    private val screenFit: GameScreenFit,
) : FrameLayout(context) {
    private val outerColor = Color.rgb(0x0B, 0x15, 0x12)
    private val innerColor = Color.rgb(0x2A, 0x55, 0x48)
    private val barPaint = Paint()
    private val rimPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1.5f
        color = Color.argb(0x1A, 0xFF, 0xFF, 0xFF)
    }

    init {
        setBackgroundColor(outerColor)
        // The bars are drawn behind the page, so they read as a frame instead
        // of an empty gap.
        setWillNotDraw(false)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (screenFit == GameScreenFit.STRETCH || childCount == 0) return
        val page = getChildAt(0)
        if (page.width <= 0 || page.height <= 0) return
        val pageRect = RectF(
            page.left.toFloat(),
            page.top.toFloat(),
            page.right.toFloat(),
            page.bottom.toFloat(),
        )
        drawBar(canvas, RectF(0f, 0f, width.toFloat(), pageRect.top), 0f, 0f, 0f, pageRect.top)
        drawBar(canvas, RectF(0f, pageRect.bottom, width.toFloat(), height.toFloat()),
            0f, height.toFloat(), 0f, pageRect.bottom)
        drawBar(canvas, RectF(0f, 0f, pageRect.left, height.toFloat()), 0f, 0f, pageRect.left, 0f)
        drawBar(canvas, RectF(pageRect.right, 0f, width.toFloat(), height.toFloat()),
            width.toFloat(), 0f, pageRect.right, 0f)
        canvas.drawRect(
            pageRect.left - 0.75f,
            pageRect.top - 0.75f,
            pageRect.right + 0.75f,
            pageRect.bottom + 0.75f,
            rimPaint,
        )
    }

    private fun drawBar(
        canvas: Canvas,
        rect: RectF,
        startX: Float,
        startY: Float,
        endX: Float,
        endY: Float,
    ) {
        if (rect.width() <= 0f || rect.height() <= 0f) return
        barPaint.shader = LinearGradient(
            startX,
            startY,
            endX,
            endY,
            outerColor,
            innerColor,
            Shader.TileMode.CLAMP,
        )
        canvas.drawRect(rect, barPaint)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val height = MeasureSpec.getSize(heightMeasureSpec)
        setMeasuredDimension(width, height)
        if (childCount == 0) return

        val (viewportWidth, viewportHeight) = GameViewportSize.fit(width, height, screenFit)
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
            if (screenFit == GameScreenFit.STRETCH && child.measuredWidth > 0 && child.measuredHeight > 0) {
                // The page keeps the balanced viewport; scaling from the top-left
                // corner stretches it over the whole window.
                child.layout(0, 0, child.measuredWidth, child.measuredHeight)
                child.pivotX = 0f
                child.pivotY = 0f
                child.scaleX = width.toFloat() / child.measuredWidth
                child.scaleY = height.toFloat() / child.measuredHeight
                continue
            }
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
