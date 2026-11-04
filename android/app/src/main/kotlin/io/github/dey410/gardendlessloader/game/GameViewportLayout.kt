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
    private val frameEnabled: Boolean = true,
) : FrameLayout(context) {
    private val tone = LetterboxTone.of(frameAccent)
    private val topBar = RectF()
    private val bottomBar = RectF()
    private val leadingBar = RectF()
    private val trailingBar = RectF()
    private val canvasRect = RectF()
    private val topPaint = Paint()
    private val bottomPaint = Paint()
    private val leadingPaint = Paint()
    private val trailingPaint = Paint()
    private val rimPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        // 1.5 points on iOS becomes 1.5 dp here, so both hosts draw the same
        // hairline whatever the screen density.
        strokeWidth = 1.5f * resources.displayMetrics.density
        color = Color.argb(0x1A, 0xFF, 0xFF, 0xFF)
    }

    init {
        setBackgroundColor(if (frameEnabled) tone.outer else Color.BLACK)
        // The bars are drawn behind the page, so they read as a frame instead
        // of an empty gap.
        setWillNotDraw(false)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (!frameEnabled || screenFit == GameScreenFit.STRETCH || childCount == 0) return
        canvas.drawRect(topBar, topPaint)
        canvas.drawRect(bottomBar, bottomPaint)
        canvas.drawRect(leadingBar, leadingPaint)
        canvas.drawRect(trailingBar, trailingPaint)
        val hasBars = canvasRect.left > 0f || canvasRect.top > 0f ||
            canvasRect.right < width.toFloat() || canvasRect.bottom < height.toFloat()
        if (hasBars) {
            val inset = rimPaint.strokeWidth / 2
            canvas.drawRect(
                canvasRect.left - inset,
                canvasRect.top - inset,
                canvasRect.right + inset,
                canvasRect.bottom + inset,
                rimPaint,
            )
        }
    }

    private fun updateFrame(width: Int, height: Int) {
        if (!frameEnabled) {
            clearFrame()
            return
        }
        if (childCount == 0) {
            clearFrame()
            return
        }
        val page = getChildAt(0)
        if (page.width <= 0 || page.height <= 0) {
            clearFrame()
            return
        }

        val left = page.left.toFloat()
        val top = page.top.toFloat()
        val right = page.right.toFloat()
        val bottom = page.bottom.toFloat()
        val viewWidth = width.toFloat()
        val viewHeight = height.toFloat()
        if (
            canvasRect.left == left && canvasRect.top == top &&
            canvasRect.right == right && canvasRect.bottom == bottom &&
            topBar.right == viewWidth && leadingBar.bottom == viewHeight
        ) {
            return
        }

        canvasRect.set(left, top, right, bottom)
        topBar.set(0f, 0f, viewWidth, top)
        bottomBar.set(0f, bottom, viewWidth, viewHeight)
        leadingBar.set(0f, 0f, left, viewHeight)
        trailingBar.set(right, 0f, viewWidth, viewHeight)
        updateGradient(topPaint, topBar, 0f, 0f, 0f, top)
        updateGradient(bottomPaint, bottomBar, 0f, viewHeight, 0f, bottom)
        updateGradient(leadingPaint, leadingBar, 0f, 0f, left, 0f)
        updateGradient(trailingPaint, trailingBar, viewWidth, 0f, right, 0f)
    }

    private fun updateGradient(
        paint: Paint,
        rect: RectF,
        startX: Float,
        startY: Float,
        endX: Float,
        endY: Float,
    ) {
        paint.shader = if (rect.width() > 0f && rect.height() > 0f) {
            LinearGradient(
                startX,
                startY,
                endX,
                endY,
                tone.outer,
                tone.inner,
                Shader.TileMode.CLAMP,
            )
        } else {
            null
        }
    }

    private fun clearFrame() {
        canvasRect.setEmpty()
        topBar.setEmpty()
        bottomBar.setEmpty()
        leadingBar.setEmpty()
        trailingBar.setEmpty()
        topPaint.shader = null
        bottomPaint.shader = null
        leadingPaint.shader = null
        trailingPaint.shader = null
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
        if (screenFit == GameScreenFit.STRETCH) {
            clearFrame()
        } else {
            updateFrame(width, height)
        }
        invalidate()
    }
}
