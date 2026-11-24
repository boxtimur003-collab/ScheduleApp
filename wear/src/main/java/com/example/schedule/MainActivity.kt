@file:OptIn(ExperimentalFoundationApi::class)

package com.example.schedule

import android.graphics.Paint
import android.graphics.Path
import android.graphics.Typeface
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.Locale

private const val RANGE = 30
private val RU: Locale = Locale("ru")

private fun curMin(): Int {
    val t = LocalTime.now()
    return t.hour * 60 + t.minute
}

private fun toMin(s: String): Int {
    val h = s.substringBefore(":").toIntOrNull() ?: 0
    val m = s.substringAfter(":").toIntOrNull() ?: 0
    return h * 60 + m
}

enum class Overlay { NONE, MENU, DATES, FILES, FILE }

// =====================================================================
//                РЕНДЕР ФОРМУЛ (собственный Canvas-движок)
// =====================================================================
private typealias NCanvas = android.graphics.Canvas

private sealed class MNode
private class MText(
    val s: String,
    val italic: Boolean = false,
    val serif: Boolean = true,
    val bold: Boolean = false,
    val op: Boolean = false,
    val scale: Float = 1f
) : MNode()
private class MSpace(val em: Float, val breakable: Boolean = false) : MNode()
private class MRow(val items: List<MNode>) : MNode()
private class MFrac(val num: MNode, val den: MNode) : MNode()
private class MScript(val base: MNode?, val sup: MNode?, val sub: MNode?) : MNode()
private class MSqrt(val body: MNode, val index: MNode?) : MNode()
private class MFence(val open: String, val close: String, val body: MNode) : MNode()
private class MAccent(val body: MNode, val vec: Boolean) : MNode()
private object MBreak : MNode()

private val M_SYMBOLS: Map<String, String> = mapOf(
    "cdot" to "·", "times" to "×", "div" to "÷", "pm" to "±", "mp" to "∓",
    "leq" to "≤", "le" to "≤", "geq" to "≥", "ge" to "≥", "neq" to "≠", "ne" to "≠",
    "approx" to "≈", "equiv" to "≡", "sim" to "∼", "propto" to "∝", "infty" to "∞",
    "to" to "→", "rightarrow" to "→", "leftarrow" to "←", "Rightarrow" to "⇒",
    "Leftrightarrow" to "⇔", "leftrightarrow" to "↔",
    "ldots" to "…", "dots" to "…", "cdots" to "…",
    "degree" to "°", "circ" to "°", "angle" to "∠", "perp" to "⊥", "parallel" to "∥",
    "in" to "∈", "notin" to "∉", "cup" to "∪", "cap" to "∩", "subset" to "⊂", "subseteq" to "⊆",
    "emptyset" to "∅", "forall" to "∀", "exists" to "∃",
    "sum" to "∑", "prod" to "∏", "int" to "∫", "iint" to "∬", "oint" to "∮",
    "partial" to "∂", "nabla" to "∇", "prime" to "′", "ell" to "ℓ", "hbar" to "ħ",
    "langle" to "⟨", "rangle" to "⟩", "lfloor" to "⌊", "rfloor" to "⌋",
    "lceil" to "⌈", "rceil" to "⌉", "vert" to "|", "Vert" to "‖", "mid" to "|",
    "alpha" to "α", "beta" to "β", "gamma" to "γ", "delta" to "δ", "epsilon" to "ε",
    "varepsilon" to "ε", "zeta" to "ζ", "eta" to "η", "theta" to "θ", "vartheta" to "ϑ",
    "iota" to "ι", "kappa" to "κ", "lambda" to "λ", "mu" to "μ", "nu" to "ν", "xi" to "ξ",
    "pi" to "π", "rho" to "ρ", "sigma" to "σ", "tau" to "τ", "upsilon" to "υ",
    "phi" to "φ", "varphi" to "ϕ", "chi" to "χ", "psi" to "ψ", "omega" to "ω",
    "Gamma" to "Γ", "Delta" to "Δ", "Theta" to "Θ", "Lambda" to "Λ", "Xi" to "Ξ",
    "Pi" to "Π", "Sigma" to "Σ", "Phi" to "Φ", "Psi" to "Ψ", "Omega" to "Ω"
)

private val M_GREEK_LOWER = setOf(
    "alpha", "beta", "gamma", "delta", "epsilon", "varepsilon", "zeta", "eta", "theta",
    "vartheta", "iota", "kappa", "lambda", "mu", "nu", "xi", "pi", "rho", "sigma", "tau",
    "upsilon", "phi", "varphi", "chi", "psi", "omega", "ell", "hbar"
)

private val M_OPS = setOf(
    "cdot", "times", "div", "pm", "mp", "leq", "le", "geq", "ge", "neq", "ne", "approx",
    "equiv", "sim", "propto", "to", "rightarrow", "leftarrow", "Rightarrow", "Leftrightarrow",
    "leftrightarrow", "in", "notin", "cup", "cap", "subset", "subseteq"
)

private val M_BIG = setOf("sum", "prod", "int", "iint", "oint")

private val M_FUNCS = setOf(
    "sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan", "sinh", "cosh",
    "tanh", "ln", "log", "lg", "exp", "lim", "min", "max", "sup", "inf", "det", "gcd",
    "mod", "dim", "ker", "arg", "deg"
)

private val M_DROP = setOf(
    "hat", "tilde", "dot", "ddot", "widehat", "widetilde", "mathbb", "mathcal", "mathscr",
    "mathsf", "displaystyle", "textstyle", "scriptstyle", "limits", "nolimits",
    "big", "Big", "bigg", "Bigg", "bigl", "bigr", "Bigl", "Bigr",
    "boldsymbol", "mathbf", "bf", "label", "nonumber", "hline", "centering"
)

private const val M_OP_CHARS = "=+−<>≈≠≤≥×·÷±∓→←⇒⇔∈∪∩⊂≡∼"
private val M_TEXT_STOP = setOf(' ', '\t', '\r', '\n', '\\', '^', '_', '{', '}', '$', '&')

private fun isAscii(c: Char): Boolean = c in 'A'..'Z' || c in 'a'..'z'

// ---------------------------- ПАРСЕР ----------------------------
private class MParser(private val s: String, startMath: Boolean) {
    private var i = 0
    private var math = startMath

    fun parseAll(): MRow = parseRow(inGroup = false, inFence = false)

    private fun parseRow(inGroup: Boolean, inFence: Boolean): MRow {
        val out = ArrayList<MNode>()
        while (i < s.length) {
            val c = s[i]
            if (inGroup && c == '}') break
            if (inFence && s.startsWith("\\right", i)) break
            val atom = parseAtom()
            if (atom != null) out.add(atom)
        }
        return MRow(out)
    }

    private fun parseAtom(): MNode? {
        val c = s[i]
        if (c == '^' || c == '_') return withScripts(null)
        val b = parseBase() ?: return null
        return withScripts(b)
    }

    private fun withScripts(base: MNode?): MNode? {
        var sup: MNode? = null
        var sub: MNode? = null
        while (true) {
            if (math) {
                var j = i
                while (j < s.length && s[j] == ' ') j++
                if (j < s.length && (s[j] == '^' || s[j] == '_')) i = j
            }
            if (i < s.length && s[i] == '^') {
                i++
                sup = scriptArg()
            } else if (i < s.length && s[i] == '_') {
                i++
                sub = scriptArg()
            } else {
                break
            }
        }
        return if (sup == null && sub == null) base else MScript(base, sup, sub)
    }

    private fun scriptArg(): MNode {
        skipSpaces()
        if (i >= s.length) return MRow(emptyList())
        val c = s[i]
        if (c == '{') return group()
        if (c == '\\') return command() ?: MRow(emptyList())
        if (c == '}') return MRow(emptyList())
        i++
        return charNode(c)
    }

    private fun arg(): MNode {
        skipSpaces()
        if (i >= s.length) return MRow(emptyList())
        val c = s[i]
        if (c == '{') return group()
        if (c == '\\') return command() ?: MRow(emptyList())
        if (c == '}') return MRow(emptyList())
        i++
        return charNode(c)
    }

    private fun charNode(c: Char): MNode = when {
        c.isDigit() -> MText(c.toString())
        isAscii(c) -> MText(c.toString(), italic = true)
        c == '-' -> MText("−", op = true)
        else -> MText(c.toString())
    }

    private fun skipSpaces() {
        while (i < s.length && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r' || s[i] == '\n')) i++
    }

    private fun group(): MNode {
        i++
        val r = parseRow(inGroup = true, inFence = false)
        if (i < s.length && s[i] == '}') i++
        return r
    }

    private fun rawGroup(): String {
        skipSpaces()
        if (i >= s.length || s[i] != '{') return ""
        var depth = 0
        val st = i + 1
        var j = i
        while (j < s.length) {
            if (s[j] == '{') {
                depth++
            } else if (s[j] == '}') {
                depth--
                if (depth == 0) break
            }
            j++
        }
        val end = if (j < s.length) j else s.length
        val out = s.substring(st, end)
        i = if (j < s.length) j + 1 else s.length
        return out
    }

    private fun parseBase(): MNode? {
        val c = s[i]
        if (c == '\\') return command()
        if (c == '{') return group()
        if (c == '}') {
            i++
            return null
        }
        if (c == '$') {
            i++
            if (i < s.length && s[i] == '$') i++
            math = !math
            return null
        }
        if (c == '\n') {
            i++
            return MBreak
        }
        if (c == '&') {
            i++
            return MSpace(0.5f)
        }
        if (c == ' ' || c == '\t' || c == '\r') {
            i++
            if (math) return null
            while (i < s.length && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r')) i++
            return MSpace(0.28f, breakable = true)
        }
        return if (math) mathChars() else textWord()
    }

    private fun mathChars(): MNode {
        val c = s[i]
        if (c.isDigit()) {
            val st = i
            while (i < s.length && (s[i].isDigit() ||
                    ((s[i] == '.' || s[i] == ',') && i + 1 < s.length && s[i + 1].isDigit()))
            ) i++
            return MText(s.substring(st, i))
        }
        if (isAscii(c)) {
            val st = i
            while (i < s.length && isAscii(s[i])) i++
            return MText(s.substring(st, i), italic = true)
        }
        if (c.isLetter()) {
            val st = i
            while (i < s.length && s[i].isLetter() && !isAscii(s[i])) i++
            return MText(s.substring(st, i))
        }
        i++
        return when (c) {
            '-' -> MText("−", op = true)
            '*' -> MText("·", op = true)
            '\'' -> MText("′")
            else -> MText(c.toString(), op = M_OP_CHARS.indexOf(c) >= 0)
        }
    }

    private fun textWord(): MNode {
        val st = i
        while (i < s.length && s[i] !in M_TEXT_STOP) i++
        if (i == st) i++
        return MText(s.substring(st, i), serif = false)
    }

    private fun delim(): String {
        skipSpaces()
        if (i >= s.length) return "."
        val c = s[i]
        i++
        if (c != '\\') return c.toString()
        if (i >= s.length) return "."
        val st = i
        while (i < s.length && isAscii(s[i])) i++
        if (i > st) return M_SYMBOLS[s.substring(st, i)] ?: "."
        val d = s[i]
        i++
        return when (d) {
            '{' -> "{"
            '}' -> "}"
            '|' -> "‖"
            else -> "."
        }
    }

    private fun command(): MNode? {
        i++
        if (i >= s.length) return null
        val st = i
        while (i < s.length && isAscii(s[i])) i++
        val name = s.substring(st, i)

        if (name.isEmpty()) {
            val ch = s[i]
            i++
            return when (ch) {
                '\\' -> MBreak
                ',', ';', ':', ' ' -> MSpace(0.2f)
                '!' -> null
                '(' -> { math = true; null }
                ')' -> { math = false; null }
                '[' -> { math = true; MBreak }
                ']' -> { math = false; MBreak }
                '{', '}', '%', '&', '#', '_', '$' -> MText(ch.toString(), serif = math)
                '|' -> MText("‖")
                else -> MText(ch.toString())
            }
        }

        if (name in M_DROP) return null
        if (name == "begin" || name == "end") {
            val env = rawGroup()
            if (name == "begin" && (env == "array" || env == "tabular")) rawGroup()
            return null
        }
        if (name == "frac" || name == "dfrac" || name == "tfrac") {
            val a = arg()
            val b = arg()
            return MFrac(a, b)
        }
        if (name == "sqrt") {
            var idx: MNode? = null
            skipSpaces()
            if (i < s.length && s[i] == '[') {
                val close = s.indexOf(']', i)
                if (close > i) {
                    idx = MParser(s.substring(i + 1, close), math).parseAll()
                    i = close + 1
                }
            }
            return MSqrt(arg(), idx)
        }
        if (name == "left") {
            val open = delim()
            val body = parseRow(inGroup = false, inFence = true)
            var close = "."
            if (s.startsWith("\\right", i)) {
                i += 6
                close = delim()
            }
            return MFence(open, close, body)
        }
        if (name == "right") {
            val d = delim()
            return MText(if (d == ".") "" else d)
        }
        if (name == "text" || name == "textrm" || name == "mbox" || name == "textnormal") {
            return MText(rawGroup(), serif = false)
        }
        if (name == "mathrm" || name == "operatorname" || name == "rm") return MText(rawGroup())
        if (name == "textbf") return MText(rawGroup(), serif = false, bold = true)
        if (name == "textit" || name == "mathit") return MText(rawGroup(), italic = true)
        if (name == "overline" || name == "bar" || name == "underline") return MAccent(arg(), false)
        if (name == "vec" || name == "overrightarrow") return MAccent(arg(), true)
        if (name == "quad") return MSpace(1f)
        if (name == "qquad") return MSpace(2f)
        if (name in M_FUNCS) return MRow(listOf(MText(name), MSpace(0.17f)))

        val sym = M_SYMBOLS[name]
        if (sym != null) {
            return MText(
                sym,
                italic = math && name in M_GREEK_LOWER,
                op = name in M_OPS,
                scale = if (name in M_BIG) 1.3f else 1f
            )
        }
        return MText(name)
    }
}

// ---------------------------- РАСКЛАДКА ----------------------------
/** w - ширина, asc - высота над базовой линией, desc - глубина под ней. draw(canvas, x слева, y базовой линии). */
private class MBox(val w: Float, val asc: Float, val desc: Float, val draw: (NCanvas, Float, Float) -> Unit)

private class MLayout(private val base: Float, private val ink: Int) {
    private val paints = HashMap<Int, Paint>()
    private val empty = MBox(0f, 0f, 0f) { _, _, _ -> }

    fun paint(size: Float, italic: Boolean, serif: Boolean, bold: Boolean): Paint {
        val key = ((size * 10f).toInt() shl 3) or
            (if (italic) 1 else 0) or (if (serif) 2 else 0) or (if (bold) 4 else 0)
        return paints.getOrPut(key) {
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                textSize = size
                color = ink
                val st = when {
                    bold && italic -> Typeface.BOLD_ITALIC
                    bold -> Typeface.BOLD
                    italic -> Typeface.ITALIC
                    else -> Typeface.NORMAL
                }
                typeface = Typeface.create(if (serif) Typeface.SERIF else Typeface.DEFAULT, st)
            }
        }
    }

    private fun stroke(th: Float, round: Boolean = false): Paint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ink
            strokeWidth = th
            style = Paint.Style.STROKE
            if (round) {
                strokeJoin = Paint.Join.ROUND
                strokeCap = Paint.Cap.ROUND
            }
        }

    fun box(n: MNode, size: Float): MBox = when (n) {
        is MText -> text(n, size)
        is MSpace -> MBox(n.em * size, 0f, 0f) { _, _, _ -> }
        is MRow -> row(n.items, size, null)
        is MFrac -> frac(n, size)
        is MScript -> script(n, size)
        is MSqrt -> sqrt(n, size)
        is MFence -> fence(n, size)
        is MAccent -> accent(n, size)
        is MBreak -> empty
    }

    private fun text(n: MText, size: Float): MBox {
        val sz = size * n.scale
        val p = paint(sz, n.italic, n.serif, n.bold)
        val w = p.measureText(n.s) + (if (n.italic) sz * 0.05f else 0f)
        val dy = (n.scale - 1f) * size * 0.28f
        return MBox(w, sz * 0.80f - dy, sz * 0.22f + dy) { c, x, y -> c.drawText(n.s, x, y + dy, p) }
    }

    fun row(items: List<MNode>, size: Float, first: MNode?): MBox {
        val boxes = ArrayList<MBox>(items.size)
        val xs = FloatArray(items.size)
        var x = 0f
        var asc = 0f
        var desc = 0f
        var prev: MNode? = first
        for ((k, node) in items.withIndex()) {
            val b = box(node, size)
            var pre = 0f
            var post = 0f
            if (node is MText && node.op) {
                val pv = prev
                val unary = pv == null ||
                    (pv is MText && (pv.op || pv.s == "(" || pv.s == "[" || pv.s == "{"))
                if (!unary) {
                    pre = size * 0.20f
                    post = size * 0.20f
                }
            }
            x += pre
            xs[k] = x
            boxes.add(b)
            x += b.w + post
            if (b.asc > asc) asc = b.asc
            if (b.desc > desc) desc = b.desc
            prev = node
        }
        return MBox(x, asc, desc) { c, ox, oy ->
            for (k in boxes.indices) boxes[k].draw(c, ox + xs[k], oy)
        }
    }

    private fun frac(n: MFrac, size: Float): MBox {
        val cs = maxOf(size * 0.88f, base * 0.55f)
        val nb = box(n.num, cs)
        val db = box(n.den, cs)
        val th = maxOf(1f, size * 0.055f)
        val axis = size * 0.30f
        val gap = size * 0.13f
        val pad = size * 0.10f
        val w = maxOf(nb.w, db.w) + 2f * pad
        val asc = axis + th / 2f + gap + nb.desc + nb.asc
        val desc = maxOf(0f, db.desc + db.asc + gap + th / 2f - axis)
        val bp = stroke(th)
        return MBox(w, asc, desc) { c, x, y ->
            val yBar = y - axis
            nb.draw(c, x + (w - nb.w) / 2f, yBar - th / 2f - gap - nb.desc)
            db.draw(c, x + (w - db.w) / 2f, yBar + th / 2f + gap + db.asc)
            c.drawLine(x + pad * 0.4f, yBar, x + w - pad * 0.4f, yBar, bp)
        }
    }

    private fun script(n: MScript, size: Float): MBox {
        val b0 = if (n.base != null) box(n.base, size)
        else MBox(0f, size * 0.80f, size * 0.22f) { _, _, _ -> }
        val ss = maxOf(size * 0.7f, base * 0.5f)
        val sup = if (n.sup != null) box(n.sup, ss) else null
        val sub = if (n.sub != null) box(n.sub, ss) else null
        var supShift = if (sup != null) maxOf(size * 0.40f, b0.asc - size * 0.45f) else 0f
        val subShift = if (sub != null) maxOf(size * 0.20f, b0.desc - size * 0.05f) else 0f
        if (sup != null && sub != null) {
            val need = sup.desc + sub.asc + size * 0.12f
            if (supShift + subShift < need) supShift = need - subShift
        }
        val sShift = supShift
        val gap = size * 0.04f
        val sw = maxOf(sup?.w ?: 0f, sub?.w ?: 0f)
        val w = b0.w + gap + sw
        val asc = maxOf(b0.asc, if (sup != null) sShift + sup.asc else 0f)
        val desc = maxOf(b0.desc, if (sub != null) subShift + sub.desc else 0f)
        return MBox(w, asc, desc) { c, x, y ->
            b0.draw(c, x, y)
            if (sup != null) sup.draw(c, x + b0.w + gap, y - sShift)
            if (sub != null) sub.draw(c, x + b0.w + gap, y + subShift)
        }
    }

    private fun sqrt(n: MSqrt, size: Float): MBox {
        val bb = box(n.body, size)
        val ib = if (n.index != null) box(n.index, maxOf(size * 0.55f, base * 0.45f)) else null
        val th = maxOf(1f, size * 0.055f)
        val gap = size * 0.12f
        val rw = size * 0.60f
        val off = if (ib != null) maxOf(0f, ib.w - rw * 0.45f) else 0f
        val asc = bb.asc + gap + th
        val desc = bb.desc
        val h = asc + desc
        val w = off + rw + bb.w + size * 0.08f
        val sp = stroke(th, true)
        return MBox(w, asc, desc) { c, x, y ->
            val rx = x + off
            val topY = y - asc + th / 2f
            val tipY = y + desc
            val path = Path()
            path.moveTo(rx, tipY - h * 0.40f)
            path.lineTo(rx + rw * 0.22f, tipY - h * 0.46f)
            path.lineTo(rx + rw * 0.50f, tipY)
            path.lineTo(rx + rw, topY)
            path.lineTo(rx + rw + bb.w + size * 0.08f, topY)
            c.drawPath(path, sp)
            bb.draw(c, rx + rw, y)
            if (ib != null) ib.draw(c, x, tipY - h * 0.55f)
        }
    }

    private fun delimBox(ch: String, size: Float, bb: MBox): MBox {
        if (ch.isEmpty() || ch == ".") return MBox(size * 0.02f, bb.asc, bb.desc) { _, _, _ -> }
        val p = paint(size, false, true, false)
        val gw = p.measureText(ch) + size * 0.02f
        val h = bb.asc + bb.desc
        if (h <= size * 1.2f) {
            return MBox(gw, maxOf(bb.asc, size * 0.80f), maxOf(bb.desc, size * 0.22f)) { c, x, y ->
                c.drawText(ch, x, y, p)
            }
        }
        val k = (h / size).coerceIn(1f, 4f)
        return MBox(gw, bb.asc, bb.desc) { c, x, y ->
            val cy = y - (bb.asc - bb.desc) / 2f
            c.save()
            c.translate(x, cy)
            c.scale(1f, k)
            c.drawText(ch, 0f, size * 0.27f, p)
            c.restore()
        }
    }

    private fun fence(n: MFence, size: Float): MBox {
        val bb = box(n.body, size)
        val lb = delimBox(n.open, size, bb)
        val rb = delimBox(n.close, size, bb)
        val gap = size * 0.03f
        val w = lb.w + gap + bb.w + gap + rb.w
        val asc = maxOf(bb.asc, maxOf(lb.asc, rb.asc))
        val desc = maxOf(bb.desc, maxOf(lb.desc, rb.desc))
        return MBox(w, asc, desc) { c, x, y ->
            lb.draw(c, x, y)
            bb.draw(c, x + lb.w + gap, y)
            rb.draw(c, x + lb.w + gap + bb.w + gap, y)
        }
    }

    private fun accent(n: MAccent, size: Float): MBox {
        val bb = box(n.body, size)
        val th = maxOf(1f, size * 0.05f)
        val gap = size * 0.10f
        val sp = stroke(th)
        val extra = if (n.vec) size * 0.22f else size * 0.14f
        return MBox(bb.w, bb.asc + extra, bb.desc) { c, x, y ->
            bb.draw(c, x, y)
            val ly = y - bb.asc - gap
            c.drawLine(x, ly, x + bb.w, ly, sp)
            if (n.vec) {
                val ah = size * 0.10f
                c.drawLine(x + bb.w, ly, x + bb.w - ah * 1.6f, ly - ah, sp)
                c.drawLine(x + bb.w, ly, x + bb.w - ah * 1.6f, ly + ah, sp)
            }
        }
    }
}

private class MLine(val w: Float, val h: Float, val draw: (NCanvas) -> Unit)

/** Текст с LaTeX -> список строк с готовой отрисовкой (перенос по пробелам и знакам операций). */
private fun layoutFormula(src: String, base: Float, maxW: Float, ink: Int): List<MLine> {
    val text = src.replace("\r", "")
    val hasDelims = text.contains("\\(") || text.contains("\\[") || text.indexOf('$') >= 0
    val nodes = ArrayList<MNode>()
    if (hasDelims) {
        nodes.addAll(MParser(text, false).parseAll().items)
    } else {
        val ls = text.split("\n")
        for ((idx, ln) in ls.withIndex()) {
            if (idx > 0) nodes.add(MBreak)
            val mathy = ln.any { it == '\\' || it == '^' || it == '_' || it == '{' }
            nodes.addAll(MParser(ln, mathy).parseAll().items)
        }
    }

    val lay = MLayout(base, ink)
    val lines = ArrayList<MLine>()
    var chunks = ArrayList<MBox>()
    var curW = 0f
    var curAsc = base * 0.80f
    var curDesc = base * 0.22f
    var hint: MNode? = null

    fun flush() {
        if (chunks.isEmpty()) return
        val cs = chunks
        val a = curAsc
        val d = curDesc
        val w = curW
        lines.add(MLine(w, a + d) { c ->
            var x = 0f
            for (b in cs) {
                b.draw(c, x, a)
                x += b.w
            }
        })
        chunks = ArrayList()
        curW = 0f
        curAsc = base * 0.80f
        curDesc = base * 0.22f
    }

    fun blank() {
        if (lines.isNotEmpty() && lines[lines.size - 1].w > 0f) {
            lines.add(MLine(0f, base * 0.5f) { _ -> })
        }
    }

    fun place(items: List<MNode>) {
        if (items.isEmpty()) return
        val b = lay.row(items, base, hint)
        hint = items[items.size - 1]
        if (chunks.isNotEmpty() && curW + b.w > maxW) flush()
        chunks.add(b)
        curW += b.w
        if (b.asc > curAsc) curAsc = b.asc
        if (b.desc > curDesc) curDesc = b.desc
    }

    var pending = ArrayList<MNode>()
    for (node in nodes) {
        if (node is MBreak) {
            place(pending)
            pending = ArrayList()
            if (chunks.isEmpty()) blank() else flush()
            hint = null
            continue
        }
        pending.add(node)
        val isOp = node is MText && node.op
        val isSpace = node is MSpace && node.breakable
        if (isOp || isSpace) {
            place(pending)
            pending = ArrayList()
        }
    }
    place(pending)
    flush()
    while (lines.isNotEmpty() && lines[lines.size - 1].w <= 0f) lines.removeAt(lines.size - 1)
    return lines
}

@Composable
private fun FormulaLine(line: MLine, availPx: Float) {
    val density = LocalDensity.current
    if (line.w <= 0f) {
        Spacer(Modifier.height(with(density) { line.h.toDp() }))
        return
    }
    val scale = if (line.w > availPx) maxOf(availPx / line.w, 0.7f) else 1f
    val wPx = line.w * scale
    val scroll = wPx > availPx + 1f
    val wDp = with(density) { wPx.toDp() }
    val hDp = with(density) { (line.h * scale).toDp() }
    val state = rememberScrollState()
    Box(if (scroll) Modifier.fillMaxWidth().horizontalScroll(state) else Modifier) {
        Canvas(Modifier.size(wDp, hDp)) {
            val nc = drawContext.canvas.nativeCanvas
            nc.save()
            nc.scale(scale, scale)
            line.draw(nc)
            nc.restore()
        }
    }
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ScheduleRepository.init(this)
        FileStore.init(this)
        setContent { WearApp() }
    }
}

@Composable
fun WearApp() {
    val ctx = LocalContext.current
    val lessons by ScheduleRepository.lessons.collectAsState()
    val files by FileStore.files.collectAsState()
    var detail by remember { mutableStateOf<Lesson?>(null) }
    var overlay by remember { mutableStateOf(Overlay.NONE) }
    var openId by remember { mutableStateOf<String?>(null) }
    var nowMin by remember { mutableStateOf(curMin()) }
    val today = remember { LocalDate.now() }
    val pager = rememberPagerState(initialPage = RANGE) { RANGE * 2 + 1 }   // ±30 дней
    val scope = rememberCoroutineScope()

    // обновление шкалы времени раз в минуту
    LaunchedEffect(Unit) {
        while (true) {
            delay(60_000L)
            nowMin = curMin()
        }
    }

    BackHandler(enabled = detail != null || overlay != Overlay.NONE) {
        when (overlay) {
            Overlay.FILE -> overlay = Overlay.FILES
            Overlay.FILES, Overlay.DATES -> overlay = Overlay.MENU
            Overlay.MENU -> overlay = Overlay.NONE
            Overlay.NONE -> detail = null
        }
    }

    MaterialTheme {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            val d = detail
            if (d == null) {
                HorizontalPager(state = pager) { page ->
                    val date = today.plusDays((page - RANGE).toLong())
                    DayPage(
                        date, lessons, isToday = date == today, nowMin = nowMin,
                        onOpen = { detail = it }, onTitle = { overlay = Overlay.MENU }
                    )
                }
                // левый край: свайп слева направо открывает меню
                if (overlay == Overlay.NONE) {
                    Box(
                        Modifier.align(Alignment.CenterStart).fillMaxHeight().width(24.dp)
                            .pointerInput(Unit) {
                                var total = 0f
                                detectHorizontalDragGestures(
                                    onDragStart = { total = 0f },
                                    onDragEnd = { if (total > 40f) overlay = Overlay.MENU },
                                    onDragCancel = { total = 0f },
                                    onHorizontalDrag = { _, dx -> total += dx }
                                )
                            }
                    )
                }
                when (overlay) {
                    Overlay.MENU -> MenuPanel(
                        filesCount = files.size,
                        onDates = { overlay = Overlay.DATES },
                        onFiles = { overlay = Overlay.FILES }
                    )
                    Overlay.DATES -> DatesDrawer(today, pager.currentPage - RANGE) { i ->
                        overlay = Overlay.NONE
                        scope.launch { pager.animateScrollToPage(RANGE + i) }
                    }
                    Overlay.FILES -> FilesScreen(files) { f ->
                        openId = f.id
                        overlay = Overlay.FILE
                    }
                    Overlay.FILE -> {
                        val f = files.firstOrNull { it.id == openId }
                        if (f != null) {
                            FileViewer(f) {
                                FileStore.delete(ctx, f.id)
                                overlay = Overlay.FILES
                            }
                        } else {
                            FilesScreen(files) { x ->
                                openId = x.id
                                overlay = Overlay.FILE
                            }
                        }
                    }
                    Overlay.NONE -> {}
                }
            } else {
                DetailScreen(d) { detail = null }
            }
        }
    }
}

// ======================= МЕНЮ (2 кнопки) =======================
@Composable
fun MenuButton(icon: ImageVector, label: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(24.dp)).background(Pal.Card)
            .clickable(onClick = onClick).padding(horizontal = 18.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, null, tint = Pal.Lilac, modifier = Modifier.size(22.dp))
        Text(
            label, color = Pal.Text, fontSize = 16.sp, fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(start = 12.dp)
        )
    }
}

@Composable
fun MenuPanel(filesCount: Int, onDates: () -> Unit, onFiles: () -> Unit) {
    Box(
        Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.96f)).pointerInput(Unit) {},
        contentAlignment = Alignment.Center
    ) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 32.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            MenuButton(Icons.Filled.CalendarMonth, "Даты", onDates)
            MenuButton(Icons.Filled.Description, if (filesCount > 0) "Файлы ($filesCount)" else "Файлы", onFiles)
        }
    }
}

@Composable
fun DatesDrawer(today: LocalDate, current: Int, onPick: (Int) -> Unit) {
    val fmt = remember { DateTimeFormatter.ofPattern("EEE, d MMM", RU) }
    Box(
        Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.96f)).pointerInput(Unit) {}
    ) {
        ScalingLazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(top = 36.dp, bottom = 36.dp, start = 16.dp, end = 16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            item {
                Text(
                    "Выбор даты", color = Pal.Dim, fontSize = 13.sp,
                    textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()
                )
            }
            items((0..6).toList()) { i ->
                val d = today.plusDays(i.toLong())
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))
                        .background(if (i == current) Pal.Purple else Pal.Card)
                        .clickable { onPick(i) }
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        d.format(fmt), color = Pal.Text, fontSize = 15.sp,
                        fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f)
                    )
                    if (i == 0) Text("сегодня", color = Pal.Dim, fontSize = 11.sp)
                }
            }
        }
    }
}

// ======================= ФАЙЛЫ =======================
@Composable
fun FilesScreen(files: List<WearFile>, onOpen: (WearFile) -> Unit) {
    val list = remember(files) { files.reversed() }   // новые сверху
    Box(Modifier.fillMaxSize().background(Color.Black).pointerInput(Unit) {}) {
        ScalingLazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(top = 36.dp, bottom = 36.dp, start = 16.dp, end = 16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            item {
                Text(
                    "Файлы", color = Pal.Dim, fontSize = 13.sp,
                    textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()
                )
            }
            if (list.isEmpty()) {
                item {
                    Text(
                        "Файлов нет", color = Pal.Text, fontSize = 15.sp,
                        textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 8.dp)
                    )
                }
            }
            items(list) { f ->
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Pal.Card)
                        .clickable { onOpen(f) }
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        f.name, color = Pal.Text, fontSize = 15.sp, fontWeight = FontWeight.Bold,
                        maxLines = 1, modifier = Modifier.weight(1f)
                    )
                    Text(f.time, color = Pal.Dim, fontSize = 12.sp)
                }
            }
        }
    }
}

@Composable
fun FileViewer(f: WearFile, onDelete: () -> Unit) {
    val density = LocalDensity.current
    val cfg = LocalConfiguration.current
    val availPx = with(density) { (cfg.screenWidthDp.dp - 44.dp).toPx() }
    val baseSize = with(density) { 16.sp.toPx() }
    val ink = Pal.Text.toArgb()
    val lines = remember(f.text, availPx, baseSize) {
        try {
            layoutFormula(f.text, baseSize, availPx, ink)
        } catch (e: Throwable) {
            null
        }
    }
    Box(Modifier.fillMaxSize().background(Color.Black).pointerInput(Unit) {}) {
        ScalingLazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(top = 36.dp, bottom = 44.dp, start = 18.dp, end = 18.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            item {
                Text(
                    "${f.name} · ${f.time}", color = Pal.Dim, fontSize = 12.sp,
                    textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()
                )
            }
            if (lines != null) {
                items(lines) { line -> FormulaLine(line, availPx) }
            } else {
                items(f.text.split("\n")) { line ->
                    Text(
                        if (line.isEmpty()) " " else line,
                        color = Pal.Text, fontSize = 15.sp, modifier = Modifier.fillMaxWidth()
                    )
                }
            }
            item {
                Box(
                    Modifier.padding(top = 8.dp).clip(RoundedCornerShape(20.dp)).background(Pal.Card)
                        .clickable(onClick = onDelete)
                        .padding(horizontal = 24.dp, vertical = 8.dp)
                ) {
                    Text("Удалить", color = Color(0xFFFF6B6B), fontSize = 13.sp)
                }
            }
        }
    }
}

// ======================= ШКАЛА ВРЕМЕНИ =======================
@Composable
fun TimeScale(lessons: List<Lesson>, isToday: Boolean, nowMin: Int, modifier: Modifier) {
    val hourPaint = remember {
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.parseColor("#9B98AD")
            textAlign = Paint.Align.RIGHT
        }
    }
    val timePaint = remember {
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.RED
            textAlign = Paint.Align.RIGHT
            isFakeBoldText = true
        }
    }
    Canvas(modifier) {
        val startMin = 8 * 60
        val endMin = 18 * 60
        val total = (endMin - startMin).toFloat()
        val h = size.height
        fun y(min: Int): Float = (min - startMin) / total * h

        hourPaint.textSize = 9.sp.toPx()
        timePaint.textSize = 9.sp.toPx()
        val axisX = 17.dp.toPx()
        val axisColor = Color(0xFF3A3A44)

        drawLine(axisColor, Offset(axisX, 0f), Offset(axisX, h), strokeWidth = 1.dp.toPx())
        for (hr in 8..18 step 2) {
            val yy = y(hr * 60)
            drawLine(axisColor, Offset(axisX - 3.dp.toPx(), yy), Offset(axisX + 3.dp.toPx(), yy), strokeWidth = 1.dp.toPx())
            drawContext.canvas.nativeCanvas.drawText("%02d".format(hr), axisX - 5.dp.toPx(), yy + 3.dp.toPx(), hourPaint)
        }

        lessons.forEach { l ->
            if (l.isAllDay) return@forEach
            val s = toMin(l.start)
            val e = toMin(l.end)
            val cs = maxOf(s, startMin)
            val ce = minOf(e, endMin)
            if (ce <= cs) return@forEach
            val current = isToday && nowMin >= s && nowMin < e
            val col = if (current) Color(0xFF8A8A8A) else parseColor(l.color)
            val top = y(cs)
            val hh = (y(ce) - top).coerceAtLeast(2.dp.toPx())
            drawRoundRect(
                color = col,
                topLeft = Offset(axisX + 3.dp.toPx(), top),
                size = Size(10.dp.toPx(), hh),
                cornerRadius = CornerRadius(3.dp.toPx())
            )
        }

        if (isToday && nowMin in startMin..endMin) {
            val yy = y(nowMin)
            val tagW = 24.dp.toPx()
            drawRect(Color.Black, Offset(0f, yy - 6.dp.toPx()), Size(tagW, 12.dp.toPx()))
            drawContext.canvas.nativeCanvas.drawText(
                "%02d:%02d".format(nowMin / 60, nowMin % 60),
                tagW, yy + 3.dp.toPx(), timePaint
            )
            drawLine(Color.Red, Offset(tagW, yy), Offset(size.width, yy), strokeWidth = 1.5.dp.toPx())
        }
    }
}

@Composable
fun DayPage(
    date: LocalDate, all: List<Lesson>, isToday: Boolean, nowMin: Int,
    onOpen: (Lesson) -> Unit, onTitle: () -> Unit
) {
    val day = remember(all, date) {
        all.filter { it.occursOn(date) }
            .sortedWith(compareByDescending<Lesson> { it.isAllDay }.thenBy { it.start })
    }
    val title = date.format(DateTimeFormatter.ofPattern("EEE, d MMM", RU))
    Box(Modifier.fillMaxSize()) {
        if (day.isEmpty()) {
            Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Filled.EventAvailable, null, tint = Pal.Lilac, modifier = Modifier.size(44.dp))
                Spacer(Modifier.height(8.dp))
                Text("Занятий нет", color = Pal.Text, fontSize = 16.sp, textAlign = TextAlign.Center)
            }
        } else {
            ScalingLazyColumn(
                Modifier.fillMaxSize(),
                contentPadding = PaddingValues(top = 56.dp, bottom = 36.dp, start = 68.dp, end = 12.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) { items(day) { WearCard(it) { onOpen(it) } } }
        }
        TimeScale(
            lessons = day, isToday = isToday, nowMin = nowMin,
            modifier = Modifier.align(Alignment.CenterStart).padding(start = 24.dp)
                .width(40.dp).fillMaxHeight(0.56f)
        )
        Text(
            "‹   $title   ›", color = Pal.Text, fontSize = 14.sp, fontWeight = FontWeight.Medium,
            modifier = Modifier.align(Alignment.TopCenter).padding(top = 20.dp).clickable(onClick = onTitle)
        )
    }
}

@Composable
fun WearCard(l: Lesson, onClick: () -> Unit) {
    val col = parseColor(l.color)
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Pal.Card)
            .clickable(onClick = onClick).padding(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.width(4.dp).height(32.dp).clip(RoundedCornerShape(2.dp)).background(col))
        Column(Modifier.weight(1f).padding(start = 6.dp)) {
            Text(l.timeLabel(), color = Pal.Dim, fontSize = 11.sp, maxLines = 1)
            Text(l.title, color = Pal.Text, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1)
        }
        Box(
            Modifier.size(26.dp).clip(RoundedCornerShape(8.dp)).background(col.copy(alpha = 0.3f)),
            contentAlignment = Alignment.Center
        ) {
            if (l.emoji.isNotBlank()) Text(l.emoji, fontSize = 14.sp)
            else Icon(iconFor(l.icon), null, tint = col, modifier = Modifier.size(16.dp))
        }
    }
}

@Composable
fun DetailScreen(l: Lesson, onBack: () -> Unit) {
    val col = parseColor(l.color)
    Column(
        Modifier.fillMaxSize().padding(horizontal = 26.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Box(
            Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).background(col),
            contentAlignment = Alignment.Center
        ) {
            if (l.emoji.isNotBlank()) Text(l.emoji, fontSize = 24.sp)
            else Icon(iconFor(l.icon), null, tint = Color.White, modifier = Modifier.size(28.dp))
        }
        Spacer(Modifier.height(4.dp))
        Text(
            l.title, color = Pal.Text, fontSize = 20.sp, fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center, maxLines = 2
        )
        Spacer(Modifier.height(6.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Schedule, null, tint = Pal.Dim, modifier = Modifier.size(16.dp))
            Text("  ${l.timeLabel()}", color = Pal.Text, fontSize = 14.sp)
        }
        if (l.room.isNotBlank()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.LocationOn, null, tint = Pal.Dim, modifier = Modifier.size(16.dp))
                Text("  ${l.room}", color = Pal.Text, fontSize = 14.sp, maxLines = 1)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Repeat, null, tint = col, modifier = Modifier.size(16.dp))
            Text("  ${recurrenceStatus(l.recurrence)}", color = col, fontSize = 14.sp)
        }
        Spacer(Modifier.height(8.dp))
        Box(
            Modifier.clip(RoundedCornerShape(20.dp)).background(Pal.Card).clickable(onClick = onBack)
                .padding(horizontal = 28.dp, vertical = 6.dp)
        ) {
            Text("Назад", color = Pal.Text, fontSize = 13.sp)
        }
    }
}
