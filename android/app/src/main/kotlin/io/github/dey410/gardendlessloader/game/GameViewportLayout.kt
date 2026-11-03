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
import kotlin.math.min

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

/** The two tones of the game frame, derived from the launcher theme accent. */
private class LetterboxTone(val outer: Int, val inner: Int) {
    companion object {
        /** Neutral dark bezel used when the launcher sends no theme accent. */
        val neutral = LetterboxTone(
            outer = 0xFF0E0F11.toInt(),
            inner = 0xFF2A2B30.toInt(),
        )

        /**
         * Keeps the accent's hue but caps saturation and brightness, so every
         * theme yields a deep bezel instead of a bright band around the
         * canvas. The caps are shared with the iOS host.
         */
        fun of(accent: Int?): LetterboxTone {
            if (accent == null || (accent ushr 24) == 0) return neutral
            val hsv = FloatArray(3)
            Color.colorToHSV(accent, hsv)
            return LetterboxTone(
                outer = Color.HSVToColor(floatArrayOf(hsv[0], min(hsv[1], 0.40f), 0.075f)),
                inner = Color.HSVToColor(floatArrayOf(hsv[0], min(hsv[1], 0.55f), 0.34f)),
            )
        }
    }
}

internal class GameViewportLayout(
    context: Context,
    private val screenFit: GameScreenFit,
    frameAccent: Int? = null,
) : FrameLayout(context) {
    private val tone = LetterboxTone.of(frameAccent)
    private val barPaint = Paint()
    private val rimPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        // 1.5 points on iOS becomes 1.5 dp here, so both hosts draw the same
        // hairline whatever the screen density.
        strokeWidth = 1.5f * resources.displayMetrics.density
        color = Color.argb(0x1A, 0xFF, 0xFF, 0xFF)
    }

    init {
        setBackgroundColor(tone.outer)
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
        val inset = rimPaint.strokeWidth / 2
        canvas.drawRect(
            pageRect.left - inset,
            pageRect.top - inset,
            pageRect.right + inset,
            pageRect.bottom + inset,
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
            tone.outer,
            tone.inner,
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
        // The frame follows the page, which moves without a size change here.
        invalidate()
    }
}
