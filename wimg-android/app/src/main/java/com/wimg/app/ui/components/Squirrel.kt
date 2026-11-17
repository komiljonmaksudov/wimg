package com.wimg.app.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.text.drawText
import androidx.compose.ui.unit.Dp
import kotlin.math.PI
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.sin

/**
 * The squirrel in the band (Spielgefühl round 3, board "Eichhörnchen im Band").
 * A 1:1 port of sqFlat() from export-html/34-Spielgefuehl-Runde-2/prototyp.html:
 * same path data, colours and gradients, drawn in the prototype's 120×120
 * viewBox and scaled to [size].
 */
enum class SquirrelPose { VOLL, NORMAL, KNAPP, LEER, GEHALT, YAWN, SLEEP, LOOK }

@Composable
fun Squirrel(pose: SquirrelPose, size: Dp, modifier: Modifier = Modifier, blink: Boolean = false, z: Float = 0f) {
    Canvas(modifier.size(size)) {
        val s = this.size.minDimension / 120f
        withTransform({ scale(s, s, pivot = Offset.Zero) }) { drawSquirrel(pose, blink, z) }
    }
}

private object SQ {
    val fur = Color(0xFFC8692E); val furD = Color(0xFF8A3F17); val furL = Color(0xFFE79A5A)
    val cream = Color(0xFFF6EAD3); val creamS = Color(0xFFD9C3A0); val ink = Color(0xFF1B1512)
    val den = Color(0xFF5F86B5); val denD = Color(0xFF2C4A70); val st = Color(0xFFE08A2E)
    val lin = Color(0xFFF6F1E6); val linS = Color(0xFFBDB3A2); val moth = Color(0xFFB7B0A6); val mothD = Color(0xFF7D766C)
}

private val pathCache = HashMap<String, Path>()
private fun path(d: String): Path = pathCache.getOrPut(d) { PathParser().parsePathString(d).toPath() }

/** SVG radialGradient in objectBoundingBox units: centre and radius as fractions of the shape's box. */
private fun bboxRadial(b: Rect, cx: Float, cy: Float, r: Float, vararg stops: Pair<Float, Color>): Brush =
    Brush.radialGradient(colorStops = stops, center = Offset(b.left + b.width * cx, b.top + b.height * cy), radius = maxOf(b.width, b.height) * r)

private fun hd(b: Rect) = bboxRadial(b, .42f, .32f, .72f, 0f to Color(0xFFE4884A), .65f to SQ.fur, 1f to Color(0xFF9F4B1C))
private fun ck(b: Rect) = bboxRadial(b, .45f, .30f, .75f, 0f to Color(0xFFFFFAF0), 1f to Color(0xFFE8D2AE))
private fun ey(b: Rect) = bboxRadial(b, .38f, .32f, .72f, 0f to Color(0xFF5A3E2E), .55f to SQ.ink, 1f to SQ.ink)
private val tl = Brush.radialGradient(0f to Color(0xFFEA9C5E), .6f to Color(0xFFCD6D31), 1f to Color(0xFFA9521F), center = Offset(96f, 44f), radius = 58f)

private fun DrawScope.fillPath(d: String, brush: (Rect) -> Brush) { val p = path(d); drawPath(p, brush(p.getBounds())) }
private fun DrawScope.fillPath(d: String, c: Color, alpha: Float = 1f) = drawPath(path(d), c, alpha)
private fun DrawScope.strokePath(d: String, c: Color, w: Float, alpha: Float = 1f, cap: StrokeCap = StrokeCap.Round, join: StrokeJoin = StrokeJoin.Round) =
    drawPath(path(d), c, alpha, style = Stroke(w, cap = cap, join = join))
private fun DrawScope.oval(cx: Float, cy: Float, rx: Float, ry: Float, c: Color, alpha: Float = 1f) =
    drawOval(c, Offset(cx - rx, cy - ry), Size(rx * 2, ry * 2), alpha)
private fun DrawScope.oval(cx: Float, cy: Float, rx: Float, ry: Float, b: (Rect) -> Brush) =
    drawOval(b(Rect(cx - rx, cy - ry, cx + rx, cy + ry)), Offset(cx - rx, cy - ry), Size(rx * 2, ry * 2))
private fun f(v: Float) = Math.round(v * 10) / 10f

// --- tail: a chain of fur tufts along two cubic curves
private val TAIL = mapOf(
    "up" to listOf(76f to 90f, 102f to 84f, 86f to 40f, 104f to 24f, 124f to 10f, 118f to 40f, 104f to 36f),
    "low" to listOf(74f to 92f, 92f to 92f, 104f to 78f, 112f to 74f, 122f to 70f, 124f to 90f, 114f to 90f),
    "droop" to listOf(80f to 96f, 96f to 94f, 106f to 100f, 108f to 108f, 110f to 118f, 98f to 122f, 96f to 112f),
)
private fun bez(p0: Pair<Float, Float>, p1: Pair<Float, Float>, p2: Pair<Float, Float>, p3: Pair<Float, Float>, t: Float): Pair<Float, Float> {
    val u = 1 - t
    return (u * u * u * p0.first + 3 * u * u * t * p1.first + 3 * u * t * t * p2.first + t * t * t * p3.first) to
        (u * u * u * p0.second + 3 * u * u * t * p1.second + 3 * u * t * t * p2.second + t * t * t * p3.second)
}
private fun DrawScope.tail(kind: String) {
    val P = TAIL.getValue(kind)
    val pts = ArrayList<Pair<Float, Float>>()
    for (i in 0..12) pts += bez(P[0], P[1], P[2], P[3], i / 12f)
    for (i in 1..6) pts += bez(P[3], P[4], P[5], P[6], i / 6f)
    val k = if (kind == "droop") 0.72f else 1f
    val R = pts.indices.map { i -> val t = i / (pts.size - 1f); k * (7 + 9 * sin(PI.toFloat() * min(1f, t * 1.25f)) * (1 - 0.35f * t)) }
    pts.forEachIndexed { i, (x, y) -> drawCircle(SQ.furD, R[i] + 1.7f, Offset(x, y)) }
    pts.forEachIndexed { i, (x, y) -> drawCircle(tl, R[i], Offset(x, y)) }
    var i = 1
    while (i < pts.size - 1) {
        val (x, y) = pts[i]; val (nx, ny) = pts[i + 1]
        val dx = nx - x; val dy = ny - y; val l = hypot(dx, dy).takeIf { it > 0 } ?: 1f; val ox = -dy / l; val oy = dx / l
        for (s in floatArrayOf(-0.45f, 0.15f)) {
            val sx = x + ox * R[i] * s; val sy = y + oy * R[i] * s
            val p = Path().apply { moveTo(sx, sy); relativeQuadraticTo(dx * 0.5f + ox * 2, dy * 0.5f + oy * 2, dx * 1.1f, dy * 1.1f) }
            drawPath(p, if (s < 0) SQ.furL else Color(0xFFA9521F), 0.8f, style = Stroke(1.2f, cap = StrokeCap.Round))
        }
        for (sd in intArrayOf(-1, 1)) {
            val ex = x + ox * R[i] * sd; val ey = y + oy * R[i] * sd
            drawLine(SQ.furD, Offset(ex, ey), Offset(ex + ox * sd * 2.6f + dx * 0.25f, ey + oy * sd * 2.6f + dy * 0.25f), 1.6f, StrokeCap.Round)
        }
        i += 2
    }
    val (ex, ey) = pts.last()
    drawCircle(Color(0xFFA44E1E), R.last() * 0.7f, Offset(ex, ey), 0.55f)
}

private fun DrawScope.ears() {
    val outer = "M41 40 C36 30 34 20 37 12 C42 16 48 26 52 34 Z M79 40 C84 30 86 20 83 12 C78 16 72 26 68 34 Z"
    fillPath(outer, ::hd); strokePath(outer, SQ.furD, 1.6f)
    fillPath("M41.5 34 C39 28 38.5 22 39.5 17 C43 21 46 27 48 32 Z M78.5 34 C81 28 81.5 22 80.5 17 C77 21 74 27 72 32 Z") { b ->
        Brush.verticalGradient(listOf(Color(0xFFF3CDB3), Color(0xFFD79878)), b.top, b.bottom)
    }
    fillPath("M37.5 14 C32 9 33 2 38 -2 C37 3 41 8 40 14 Z M82.5 14 C88 9 87 2 82 -2 C83 3 79 8 80 14 Z", SQ.furD)
    strokePath("M38 11 C35.5 7 36 3 38 0 M82 11 C84.5 7 84 3 82 0", Color(0xFFC9773E), 0.9f)
}

private class FaceOpt(val lid: Float = 0f, val closed: Float = 0f, val cross: Boolean = false, val cheeks: Float = 1f, val py: Float = 0f, val px: Float = 0f, val mouth: Char = 'm', val teeth: Boolean = true)

private fun DrawScope.face(o: FaceOpt) {
    val head = "M32 62 C29 42 42 29 60 29 C78 29 91 42 88 62 C86 73 75 79 60 79 C45 79 34 73 32 62 Z"
    fillPath(head, ::hd); strokePath(head, SQ.furD, 1.8f)
    strokePath("M32 60 l-4 2 l4 1.5 l-3 3 l4.5 0 M88 60 l4 2 l-4 1.5 l3 3 l-4.5 0", SQ.furD, 1.3f)
    strokePath("M52 31 q4 -5 8 -2 q4 -4 8 2", SQ.furD, 1.4f)
    strokePath("M40 42 q7 -6 15 -4 M80 42 q-7 -6 -15 -4", SQ.furL, 1.6f, 0.85f)
    val cr = 10 * o.cheeks; val cy = 65 + 2 * (o.cheeks - 1)
    oval(f(47 - 4 * (o.cheeks - 1)), f(cy), f(cr), f(cr * 0.85f), ::ck)
    oval(f(73 + 4 * (o.cheeks - 1)), f(cy), f(cr), f(cr * 0.85f), ::ck)
    fillPath("M51 58 Q60 52 69 58 Q71 72 60 75 Q49 72 51 58 Z", SQ.cream)
    strokePath("M41 70 q2 2.4 5 2.6 M79 70 q-2 2.4 -5 2.6", SQ.creamS, 1.1f)
    listOf(48.5f to 51f, 71.5f to 51f).forEachIndexed { i, (x, y) ->
        val right = i == 1
        if (o.closed != 0f) {
            oval(x, y, 8.6f, 6.4f, SQ.cream, 0.75f)
            drawPath(Path().apply { moveTo(x - 6.5f, y + 2); quadraticTo(x, y - 5.5f * o.closed, x + 6.5f, y + 2) }, SQ.ink, style = Stroke(2.6f, cap = StrokeCap.Round))
            val sx = x + if (right) 6.5f else -6.5f
            drawLine(SQ.ink, Offset(sx, y + 1), Offset(sx + if (right) 2.4f else -2.4f, y - 0.6f), 1.3f, StrokeCap.Round)
            return@forEachIndexed
        }
        val qx = x + if (o.cross) (if (right) -1.6f else 1.6f) else o.px; val qy = y + o.py
        oval(x, y, 8f, 8.4f, SQ.cream, 0.85f)
        oval(f(x + o.px * 0.4f), y + 0.4f, 5.8f, 6.4f, ::ey)
        drawCircle(Color.White, 2.1f, Offset(f(qx + 1.8f), f(qy - 2.2f)))
        drawCircle(Color.White, 0.9f, Offset(f(qx - 1.8f), f(qy + 2.4f)), 0.7f)
        drawPath(Path().apply { moveTo(x - 5.6f, y - 3.6f); quadraticTo(x, y - 8.6f, x + 5.6f, y - 3.6f) }, SQ.ink, style = Stroke(1.3f, cap = StrokeCap.Round))
        val lx = x + if (right) 5.6f else -5.6f
        drawLine(SQ.ink, Offset(lx, y - 3.6f), Offset(lx + if (right) 2f else -2f, y - 5.2f), 1.3f, StrokeCap.Round)
        if (o.lid > 0) {
            val h = y - 7.6f + o.lid * 15.2f
            val clip = Path().apply { addOval(Rect(x - 7.2f, y + 0.4f - 7.8f, x + 7.2f, y + 0.4f + 7.8f)) }
            clipPath(clip) { drawRect(Color(0xFFD3763A), Offset(x - 9, y - 9), Size(18f, f(h - y + 9))) }
            drawPath(Path().apply { moveTo(x - 6.6f, f(h)); quadraticTo(x, f(h + 1.2f), x + 6.6f, f(h)) }, SQ.ink, style = Stroke(2f, cap = StrokeCap.Round))
        }
    }
    fillPath("M56.6 59.5 Q60 58.2 63.4 59.5 Q62.4 62.6 60 63.4 Q57.6 62.6 56.6 59.5 Z", Color(0xFF5A3326))
    oval(58.8f, 60f, 1.3f, 0.6f, Color.White, 0.6f)
    when (o.mouth) {
        'o' -> { drawLine(SQ.ink, Offset(60f, 63.4f), Offset(60f, 65f), 1.3f); oval(60f, 68f, 2.6f, 2.4f, Color(0xFF3A2016)) }
        'f' -> strokePath("M60 63.4 L60 66 M56 67.4 L64 67.4", SQ.ink, 1.5f)
        else -> {
            strokePath("M60 63.4 L60 65.6 M55.4 66.4 Q57.6 68.6 60 65.6 Q62.4 68.6 64.6 66.4", SQ.ink, 1.5f)
            if (o.teeth) {
                val t = "M58.3 66.6 L58.3 69.6 Q59.1 70.2 59.9 69.6 L59.9 66.9 M60.1 66.9 L60.1 69.6 Q60.9 70.2 61.7 69.6 L61.7 66.6"
                fillPath(t, Color(0xFFFFFDF8)); strokePath(t, Color(0xFFB9A88E), 0.6f)
            }
        }
    }
    strokePath("M49 63 L36 60 M49 65.5 L37 67 M71 63 L84 60 M71 65.5 L83 67", Color(0xFFFFF7EA), 0.7f, 0.9f)
}

private fun DrawScope.torso() {
    val t = "M38 92 C36 80 45 74 60 74 C75 74 84 80 82 92 Z"
    fillPath(t, ::hd); strokePath(t, SQ.furD, 1.6f)
    oval(60f, 86f, 13f, 10f, ::ck)
}

private fun DrawScope.paw(x: Float, y: Float, r: Float = 0f) = translate(x, y) {
    rotate(r, pivot = Offset.Zero) {
        drawRoundRect(SQ.fur, Offset(-6.5f, -6f), Size(13f, 14f), CornerRadius(6.5f))
        drawRoundRect(SQ.furD, Offset(-6.5f, -6f), Size(13f, 14f), CornerRadius(6.5f), style = Stroke(1.4f))
        fillPath("M-6 4 Q0 9.5 6 4 L5.5 7 Q0 10 -5.5 7 Z", SQ.cream)
        strokePath("M-2.2 4.5 l0 3.6 M2.2 4.5 l0 3.6", SQ.furD, 1.1f)
        strokePath("M-4 -3 q2 -2 4 0", SQ.furL, 1f, 0.8f)
    }
}

private fun DrawScope.note(x: Float, y: Float, r: Float, c: Color = Color(0xFF8DBE95)) = translate(x, y) {
    rotate(r, pivot = Offset.Zero) {
        drawRoundRect(c, Offset(-13f, -8f), Size(26f, 16f), CornerRadius(2f))
        drawRoundRect(Color.Black.copy(alpha = 0.28f), Offset(-13f, -8f), Size(26f, 16f), CornerRadius(2f), style = Stroke(1.2f))
        drawRoundRect(Color.White.copy(alpha = 0.4f), Offset(-10f, -5f), Size(20f, 10f), CornerRadius(1f), style = Stroke(0.8f))
        drawCircle(Color.White.copy(alpha = 0.55f), 3.4f, Offset.Zero)
    }
}

private fun DrawScope.acorn(x: Float, y: Float) = translate(x, y) {
    val b = "M-6 -1 Q-7 10 0 13 Q7 10 6 -1 Z"
    fillPath(b, Color(0xFFD29A48)); strokePath(b, Color(0xFF9A6A26), 1.2f)
    strokePath("M-2 2 Q-3 7 -1 9", Color(0xFFF0C27A), 1f)
    fillPath("M-7.5 0 Q-7.5 -7 0 -7 Q7.5 -7 7.5 0 Z", Color(0xFF7A5230))
    strokePath("M-5 -3 l2 0 M-1 -5 l2 0 M3 -3 l2 0", Color(0xFF5A3B20), 0.9f, cap = StrokeCap.Butt)
    strokePath("M0 -7 l1 -4", Color(0xFF5A3B20), 1.6f)
}

private fun DrawScope.moth(x: Float, y: Float) = translate(x, y) {
    val w = "M0 0 C-5 -8 -13 -7 -12 -1 C-11 4 -4 4 0 1 Z M0 0 C5 -8 13 -7 12 -1 C11 4 4 4 0 1 Z"
    fillPath(w, SQ.moth); strokePath(w, SQ.mothD, 1f)
    strokePath("M-6 -3 q-2 1 -3 3 M6 -3 q2 1 3 3", SQ.mothD, 0.7f)
    oval(0f, 1f, 1.8f, 4f, Color(0xFF857C70))
    strokePath("M-1 -3 q-2 -4 -4 -4 M1 -3 q2 -4 4 -4", Color(0xFF6B645B), 0.8f)
    drawCircle(Color.White, 0.9f, Offset(-1f, -1f)); drawCircle(Color.White, 0.9f, Offset(1f, -1f))
}

/** The pocket's hem the squirrel sits in (denim twill, orange stitches, rivets). */
private fun DrawScope.hem(inverted: Boolean) {
    if (inverted) {
        val l = "M20 90 C6 74 -4 80 0 96 C2 104 14 104 22 100 Z M100 90 C114 74 124 80 120 96 C118 104 106 104 98 100 Z"
        fillPath(l, SQ.lin); strokePath(l, SQ.linS, 1.4f)
        strokePath("M8 86 q-2 6 2 10 M112 86 q2 6 -2 10", SQ.linS, 1f)
    }
    val body = "M14 88 Q60 85 106 88 L106 122 L14 122 Z"
    fillPath(body, SQ.den)
    clipPath(path(body)) {
        // Twill: thin light diagonals (the prototype's pattern, rotated −58°).
        var x = -40f
        while (x < 160f) { drawLine(Color(0xFF7A98C8), Offset(x, 122f), Offset(x + 21f, 88f), 1.2f); x += 3f }
    }
    strokePath(body, SQ.denD, 1.8f)
    fillPath("M14 88 Q60 85 106 88 L106 97 Q60 95 14 97 Z", Color(0xFF3F6592), 0.55f)
    fillPath("M28 87 Q60 93 92 87", Color(0xFF0B1630), 0.22f)
    val dash = { on: Float, off: Float -> androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(on, off)) }
    drawPath(path("M19 93.6 Q60 91.4 101 93.6"), SQ.st, style = Stroke(1.9f, cap = StrokeCap.Round, pathEffect = dash(4.2f, 2.8f)))
    drawPath(path("M19 103 L101 103"), SQ.st, 0.75f, style = Stroke(1.6f, cap = StrokeCap.Round, pathEffect = dash(4f, 3f)))
    drawPath(path("M19 107 L101 107"), SQ.st, 0.55f, style = Stroke(1.6f, cap = StrokeCap.Round, pathEffect = dash(4f, 3f)))
    for (x in floatArrayOf(20f, 100f)) {
        drawCircle(Color(0xFFB9703A), 2.4f, Offset(x, 91f)); drawCircle(Color(0xFF7A4520), 2.4f, Offset(x, 91f), style = Stroke(0.8f))
        drawCircle(Color(0xFFF1C79C), 0.8f, Offset(x - 0.6f, 90.3f))
    }
}

private fun DrawScope.drawSquirrel(pose: SquirrelPose, blink: Boolean, z: Float) {
    var tailKind = "up"; var dy = 0f
    var face = when (pose) {
        SquirrelPose.VOLL -> { dy = -2f; FaceOpt(closed = 1f, cheeks = 1.4f) }
        SquirrelPose.NORMAL -> FaceOpt(px = -0.6f)
        SquirrelPose.KNAPP -> { tailKind = "low"; dy = 4f; FaceOpt(py = 1.4f, px = 1.6f, mouth = 'f') }
        SquirrelPose.LEER -> { tailKind = "droop"; dy = 3f; FaceOpt(cross = true, cheeks = 0.85f, mouth = 'o') }
        SquirrelPose.GEHALT -> { dy = 4f; FaceOpt(closed = 1f) }
        SquirrelPose.YAWN -> { dy = -2f; FaceOpt(closed = -0.7f, mouth = 'o', teeth = false) }
        SquirrelPose.SLEEP -> { dy = 3f; FaceOpt(closed = -1f, mouth = 'f') }
        SquirrelPose.LOOK -> FaceOpt(px = -2.4f)
    }
    if (blink && face.closed == 0f) face = FaceOpt(closed = 0.15f, cross = face.cross, cheeks = face.cheeks, mouth = face.mouth, teeth = face.teeth)
    val base = when (pose) { SquirrelPose.YAWN, SquirrelPose.SLEEP, SquirrelPose.LOOK -> SquirrelPose.NORMAL; else -> pose }

    // back
    if (base == SquirrelPose.VOLL) { note(26f, 78f, -22f, Color(0xFFE8BE72)); note(22f, 68f, -34f) }
    if (base != SquirrelPose.LEER) tail(tailKind)
    torso()
    translate(0f, dy) { ears(); face(face) }
    hem(base == SquirrelPose.LEER)
    // front
    if (pose == SquirrelPose.YAWN) { paw(42f, 40f, 160f); paw(78f, 40f, 200f) }
    else {
        if (base == SquirrelPose.VOLL || base == SquirrelPose.NORMAL || base == SquirrelPose.LEER) { paw(50f, 88f); paw(70f, 88f) }
        if (pose == SquirrelPose.KNAPP) { acorn(60f, 85f); paw(50f, 88f, 18f); paw(70f, 88f, -18f) }
        if (pose == SquirrelPose.GEHALT) { note(60f, 14f, -6f, Color(0xFFE8BE72)); paw(47f, 22f, 200f); paw(73f, 22f, 160f) }
        if (base == SquirrelPose.LEER) { tail("droop"); moth(60f, 30f) }
    }
    if (z > 0f) {
        // "z z" while asleep: two small strokes instead of text (no font needed in a Canvas).
        val c = Color(0xFFC9D6E6).copy(alpha = z)
        strokePath("M86 ${f(22 - z * 4)} l6 0 l-6 7 l6 0", c, 2f)
        strokePath("M96 ${f(11 - z * 6)} l4.5 0 l-4.5 5 l4.5 0", c, 1.6f)
    }
}

/**
 * The ring next to "Verfügbar" with the squirrel inside (board "Eichhörnchen im
 * Band", prototype figure(opt 'S') + ring(stitches)): one segment per day of the
 * period, the days left in [color], days gone dimmed, days without spending
 * marked with an orange cross stitch. [size] is the prototype's 112.
 */
@Composable
fun SquirrelRing(
    frame: SquirrelFrame,
    periodDays: Int,
    dayIndex: Int,
    noSpendDays: Set<Int>,
    size: Dp,
    modifier: Modifier = Modifier,
    blink: Boolean = false,
    color: Color = Color(0xFF8FB0D3),
    /** Price-rise moment: the tag's old and new price ("9,99 €", "11,99 €"). */
    ghostPrices: Pair<String, String> = "" to "",
) {
    val measurer = androidx.compose.ui.text.rememberTextMeasurer()
    Canvas(modifier.size(size)) {
        val s = this.size.minDimension / 112f
        withTransform({ scale(s, s, pivot = Offset.Zero) }) {
            val c = 56f; val r = 48f; val w = 7f
            val n = periodDays.coerceAtLeast(1)
            for (i in 0 until n) {
                val a0 = -90f + i * 360f / n + 1.6f
                val sweep = 360f / n - 3.2f
                val past = i < dayIndex
                // Today's stitch while Tag ohne Ausgaben plays (and after: it stays).
                val sewing = i == dayIndex && frame.stitch > 0f
                val ns = (past && (i + 1) in noSpendDays) || sewing
                // Gehalt ist da: the new period fills clockwise up to [refill].
                val unfilled = frame.refill < 1f && (i + 1).toFloat() > frame.refill * n + 0.001f
                val col = when { unfilled -> Color.White.copy(alpha = 0.12f); sewing -> SQ.st.copy(alpha = 0.25f * frame.stitch); !past -> color; ns -> SQ.st.copy(alpha = 0.25f); else -> Color.White.copy(alpha = 0.12f) }
                drawArc(col, a0, sweep, false, Offset(c - r, c - r), Size(2 * r, 2 * r), style = Stroke(w))
                if (ns) {
                    val k = if (sewing) frame.stitch else 1f
                    val m = Math.toRadians((a0 + sweep / 2).toDouble())
                    val mx = c + r * kotlin.math.cos(m).toFloat(); val my = c + r * kotlin.math.sin(m).toFloat()
                    translate(mx, my) {
                        rotate((a0 + sweep / 2), pivot = Offset.Zero) {
                            // Sewn in: first one stitch, then the second (k 0..1).
                            val a = (k * 2f).coerceAtMost(1f) * 3.4f; val b = ((k * 2f) - 1f).coerceIn(0f, 1f) * 3.4f
                            if (a > 0f) drawLine(SQ.st, Offset(-3.4f, -3.4f), Offset(-3.4f + 2 * a, -3.4f + 2 * a), 2.4f, StrokeCap.Round)
                            if (b > 0f) drawLine(SQ.st, Offset(-3.4f, 3.4f), Offset(-3.4f + 2 * b, 3.4f - 2 * b), 2.4f, StrokeCap.Round)
                        }
                    }
                }
            }
            // Inside the ring, ears and tail may stand out above it.
            val clip = Path().apply { addOval(Rect(c - 44, c - 44, c + 44, c + 44)); addRect(Rect(-40f, -60f, 152f, 56f)) }
            // The ghost of a price rise floats in from the left, outside the ring.
            if (frame.gop > 0.02f) ghost(measurer, -62f + frame.gx + 12f, 58f, frame.gop, frame.gprice, frame.gcaught, ghostPrices)
            clipPath(clip) {
                // Squash, lean and hop of a moment, around the squirrel's feet (prototype T2).
                withTransform({
                    translate(frame.dx, frame.dy)
                    rotate(frame.rot, pivot = Offset(56f, 98f))
                    scale(frame.sx, frame.sy, pivot = Offset(56f, 98f))
                }) {
                    translate(4f, 2f) { withTransform({ scale(104f / 120f, 104f / 120f, pivot = Offset.Zero) }) { drawSquirrel(frame.pose, blink, frame.z) } }
                }
            }
        }
    }
}


// ---------------------------------------------------------------------------
// Moments (prototype MOMENTS + SQM): four short steps, ~1 s in all
// ---------------------------------------------------------------------------

/** One drawn state of the squirrel: a pose plus the squash, lean and props of a moment. */
data class SquirrelFrame(
    val pose: SquirrelPose,
    val sx: Float = 1f, val sy: Float = 1f, val dx: Float = 0f, val dy: Float = 0f, val rot: Float = 0f,
    val z: Float = 0f,
    /** Price-rise ghost: opacity, x offset, price flipped to the new one (0..1), caught (0..1). */
    val gop: Float = 0f, val gx: Float = -30f, val gprice: Float = 0f, val gcaught: Float = 0f,
    /** Ring: share of the period drawn as days left (Gehalt ist da fills it from 0), today's cross stitch (0..1). */
    val refill: Float = 1f, val stitch: Float = 0f,
    /** Evening light in the band (Tag ohne Ausgaben), 0..1; read through [BandDusk]. */
    val dusk: Float = 0f,
)

/** Between two frames: numbers ease, the drawn pose switches at the middle (prototype mix()). */
fun lerp(a: SquirrelFrame, b: SquirrelFrame, t: Float): SquirrelFrame {
    fun m(x: Float, y: Float) = x + (y - x) * t
    return SquirrelFrame(if (t < 0.5f) a.pose else b.pose, m(a.sx, b.sx), m(a.sy, b.sy), m(a.dx, b.dx), m(a.dy, b.dy), m(a.rot, b.rot), m(a.z, b.z), m(a.gop, b.gop), m(a.gx, b.gx), m(a.gprice, b.gprice), m(a.gcaught, b.gcaught), m(a.refill, b.refill), m(a.stitch, b.stitch), m(a.dusk, b.dusk))
}

class MomentStep(val ms: Int, val ease: androidx.compose.animation.core.Easing, val to: (SquirrelFrame) -> SquirrelFrame)

private val Out = androidx.compose.animation.core.CubicBezierEasing(0.23f, 1f, 0.32f, 1f)
private val Drawer = androidx.compose.animation.core.CubicBezierEasing(0.32f, 0.72f, 0f, 1f)
private val InOut = androidx.compose.animation.core.CubicBezierEasing(0.77f, 0f, 0.175f, 1f)

/** The five moments of the band. [from] is where it starts, the last step is where it rests. */
enum class SquirrelMoment(val from: SquirrelPose, val steps: List<MomentStep>, private val startRefill: Float = 1f) {
    /**
     * Gehalt ist da: hops out of the empty pocket into the payday pose while the
     * ring fills clockwise to a full new period (brief 17, moment 1).
     */
    GEHALT(SquirrelPose.LEER, listOf(
        MomentStep(220, Out) { it.copy(pose = SquirrelPose.LEER, sy = 1.04f, sx = 0.98f, dy = -2f) },
        MomentStep(260, Out) { it.copy(pose = SquirrelPose.GEHALT, sy = 0.94f, sx = 1.05f, dy = 2f, refill = 0.3f) },
        MomentStep(320, Drawer) { it.copy(pose = SquirrelPose.GEHALT, sy = 1f, sx = 1f, dy = 0f, refill = 0.9f) },
        MomentStep(240, InOut) { it.copy(pose = SquirrelPose.GEHALT, rot = 0f, refill = 1f) },
    ), startRefill = 0f),
    /**
     * Tag ohne Ausgaben (after 20:00): the band dims to evening, the squirrel yawns
     * and falls asleep, today's cross stitch is sewn into the ring, a "z" appears.
     */
    NO_SPEND(SquirrelPose.NORMAL, listOf(
        MomentStep(260, InOut) { it.copy(pose = SquirrelPose.NORMAL, dusk = 0.4f) },
        MomentStep(260, Out) { it.copy(pose = SquirrelPose.YAWN, sy = 1.05f, sx = 0.98f, dusk = 0.75f) },
        MomentStep(290, Drawer) { it.copy(pose = SquirrelPose.SLEEP, sy = 0.97f, sx = 1.02f, dusk = 1f, stitch = 0.6f) },
        MomentStep(280, Out) { it.copy(pose = SquirrelPose.SLEEP, sy = 0.98f, sx = 1f, z = 1f, stitch = 1f) },
    )),
    /** Preiserhöhung: the price-tag ghost floats in, the tag flips, the squirrel leans over and catches it. */
    PRICE(SquirrelPose.NORMAL, listOf(
        MomentStep(220, Out) { it.copy(pose = SquirrelPose.LOOK, gop = 1f, gx = 0f, gprice = 0f) },
        MomentStep(200, Out) { it.copy(pose = SquirrelPose.LOOK, gprice = 1f, rot = -3f) },
        MomentStep(260, Drawer) { it.copy(pose = SquirrelPose.LOOK, rot = -6f, dx = -3f, gcaught = 1f, sx = 1.03f, sy = 0.97f) },
        MomentStep(260, InOut) { it.copy(pose = SquirrelPose.NORMAL, rot = -2f, dx = 0f, sx = 1f, sy = 1f) },
    )),
    /** Knapp: looks down, leans in, hugs the last acorn. */
    KNAPP(SquirrelPose.NORMAL, listOf(
        MomentStep(220, Out) { it.copy(pose = SquirrelPose.NORMAL, dy = 1f) },
        MomentStep(260, Drawer) { it.copy(pose = SquirrelPose.KNAPP, rot = -4f, sy = 0.96f, sx = 1.02f) },
        MomentStep(280, Out) { it.copy(pose = SquirrelPose.KNAPP, rot = 0f, sy = 1.03f, sx = 0.99f) },
        MomentStep(240, InOut) { it.copy(pose = SquirrelPose.KNAPP, sy = 1f, sx = 1f, dy = 0f) },
    )),
    /** Leer: the pocket turns inside out and the moth lands on its head. */
    LEER(SquirrelPose.KNAPP, listOf(
        MomentStep(220, Out) { it.copy(pose = SquirrelPose.KNAPP, dy = 3f) },
        MomentStep(280, Drawer) { it.copy(pose = SquirrelPose.LEER, sy = 0.94f, sx = 1.04f, dy = 0f) },
        MomentStep(280, Out) { it.copy(pose = SquirrelPose.LEER, sy = 1.02f, sx = 0.99f) },
        MomentStep(240, InOut) { it.copy(pose = SquirrelPose.LEER, sy = 1f, sx = 1f) },
    ));

    /** Where the moment starts: [from], with the ring empty for Gehalt ist da. */
    fun startFrame(): SquirrelFrame = SquirrelFrame(from, refill = startRefill)
}

/** The frame the moment ends on (also what "Weniger Bewegung" shows straight away). */
fun SquirrelMoment.endFrame(): SquirrelFrame = steps.fold(startFrame()) { f, st -> st.to(f) }

/** Price-rise ghost with its price tag (prototype ghostSVG), at ring coordinates. */
private fun DrawScope.ghost(measurer: androidx.compose.ui.text.TextMeasurer, x: Float, y: Float, op: Float, gprice: Float, caught: Float, prices: Pair<String, String>) {
    translate(x, y) {
        withTransform({ scale(0.9f, 0.9f, pivot = Offset.Zero) }) {
            val body = "M-22 22 L-22 -8 A22 22 0 0 1 22 -8 L22 22 Q16 15 11 22 Q5 28 0 22 Q-5 15 -11 22 Q-16 28 -22 22 Z"
            drawPath(path(body), Color(0xFFE7A9C0), 0.92f * op)
            drawPath(path(body), Color(0xFFC57A98), op, style = Stroke(2.4f))
            val ink = Color(0xFF3B2230)
            drawCircle(ink, 2.8f, Offset(-7f, -6f), op); drawCircle(ink, 2.8f, Offset(7f, -6f), op)
            if (caught > 0.5f) drawOval(ink, Offset(-3.4f, 0.6f), Size(6.8f, 8.8f), op)
            else drawPath(path("M-5 3 Q0 7 5 3"), ink, op, style = Stroke(2f, cap = StrokeCap.Round))
            drawLine(Color(0xFF8D8475).copy(alpha = op), Offset(-14f, 4f), Offset(-28f, 14f), 1.6f)
            // The tag flips over (scaleY through 0) from the old price to the new one.
            val flip = maxOf(0.05f, kotlin.math.abs(gprice - 0.5f) * 2f)
            val newPrice = gprice > 0.5f
            translate(-48f, 20f) {
                rotate(-8f, pivot = Offset.Zero) {
                    withTransform({ scale(1f, flip, pivot = Offset.Zero) }) {
                        val tag = "M18 -10 L-24 -10 L-24 10 L18 10 L26 0 Z"
                        drawPath(path(tag), Color(0xFFFFF6E2), op); drawPath(path(tag), Color(0xFFB8922E), op, style = Stroke(1.8f))
                        drawCircle(Color(0xFFB8922E), 2f, Offset(18f, 0f), op)
                        // Measured so that one text pixel is one unit of this (already scaled) drawing.
                        val label = if (newPrice) prices.second else prices.first
                        val t = measurer.measure(label, androidx.compose.ui.text.TextStyle(color = if (newPrice) Color(0xFF9A5B00) else Color(0xFF6B6A66), fontSize = androidx.compose.ui.unit.TextUnit(11.5f / density / fontScale, androidx.compose.ui.unit.TextUnitType.Sp), fontWeight = androidx.compose.ui.text.font.FontWeight.ExtraBold), softWrap = false)
                        drawText(t, topLeft = Offset(-3f - t.size.width / 2f, -t.size.height / 2f), alpha = op)
                    }
                }
            }
        }
    }
}

/** The caught price-tag ghost on its own (Rückblick opener card "Abo erwischt"); [width] is the ghost with its tag. */
@Composable
fun PriceGhost(prices: Pair<String, String>, width: Dp, modifier: Modifier = Modifier) {
    val measurer = androidx.compose.ui.text.rememberTextMeasurer()
    Canvas(modifier.size(width, width * 0.62f)) {
        val s = size.width / 100f
        withTransform({ scale(s, s, pivot = Offset.Zero) }) { ghost(measurer, 76f, 32f, 1f, 1f, 1f, prices) }
    }
}
