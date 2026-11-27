package com.example.schedule

import android.graphics.Paint
import android.graphics.Path
import android.graphics.Typeface
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.sp

/** Готовая к рисованию строка: w, h - размеры в пикселях, draw рисует с началом координат в левом верхнем углу. */
class MxLine(val w: Float, val h: Float, val draw: (android.graphics.Canvas) -> Unit)

// ---------------------------- узлы ----------------------------
private sealed class MxNode
private class MxText(
    val s: String,
    val italic: Boolean = false,
    val serif: Boolean = true,
    val bold: Boolean = false,
    val op: Boolean = false,
    val scale: Float = 1f,
    val func: Boolean = false
) : MxNode()
private class MxSpace(val em: Float, val breakable: Boolean = false) : MxNode()
private class MxRow(val items: List<MxNode>) : MxNode()
private class MxFrac(val num: MxNode, val den: MxNode) : MxNode()
private class MxScript(val base: MxNode?, val sup: MxNode?, val sub: MxNode?) : MxNode()
private class MxSqrt(val body: MxNode, val index: MxNode?) : MxNode()
private class MxFence(val open: String, val close: String, val body: MxNode) : MxNode()
private class MxAccent(val body: MxNode, val vec: Boolean) : MxNode()
private class MxTable(val rows: List<List<MxNode>>, val align: String) : MxNode()
private class MxArrow(val kind: Int) : MxNode()   // 1 = ⟹, -1 = ⟸, 0 = ⟺
private object MxBreak : MxNode()

private val MX_SYMBOLS: Map<String, String> = mapOf(
    "cdot" to "·", "times" to "×", "div" to "÷", "pm" to "±", "mp" to "∓",
    "leq" to "≤", "le" to "≤", "leqslant" to "≤", "geq" to "≥", "ge" to "≥", "geqslant" to "≥",
    "neq" to "≠", "ne" to "≠", "approx" to "≈", "equiv" to "≡", "sim" to "∼", "propto" to "∝", "infty" to "∞",
    "to" to "→", "rightarrow" to "→", "leftarrow" to "←", "leftrightarrow" to "↔",
    "longrightarrow" to "→", "mapsto" to "↦",
    "ldots" to "…", "dots" to "…", "cdots" to "…",
    "degree" to "°", "circ" to "°", "angle" to "∠", "perp" to "⊥", "parallel" to "∥",
    "in" to "∈", "notin" to "∉", "cup" to "∪", "cap" to "∩", "subset" to "⊂", "subseteq" to "⊆",
    "emptyset" to "∅", "varnothing" to "∅", "forall" to "∀", "exists" to "∃",
    "therefore" to "∴", "because" to "∵",
    "sum" to "∑", "prod" to "∏", "int" to "∫", "iint" to "∬", "oint" to "∮",
    "partial" to "∂", "nabla" to "∇", "prime" to "′", "ell" to "ℓ", "hbar" to "ħ", "bullet" to "•",
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

private val MX_GREEK_LOWER = setOf(
    "alpha", "beta", "gamma", "delta", "epsilon", "varepsilon", "zeta", "eta", "theta",
    "vartheta", "iota", "kappa", "lambda", "mu", "nu", "xi", "pi", "rho", "sigma", "tau",
    "upsilon", "phi", "varphi", "chi", "psi", "omega", "ell", "hbar"
)

private val MX_OPS = setOf(
    "cdot", "times", "div", "pm", "mp", "leq", "le", "leqslant", "geq", "ge", "geqslant",
    "neq", "ne", "approx", "equiv", "sim", "propto", "to", "rightarrow", "leftarrow",
    "leftrightarrow", "longrightarrow", "mapsto", "in", "notin", "cup", "cap", "subset", "subseteq"
)

private val MX_BIG = setOf("sum", "prod", "int", "iint", "oint")

private val MX_FUNCS = setOf(
    "sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan", "sinh", "cosh",
    "tanh", "ln", "log", "lg", "exp", "lim", "min", "max", "sup", "inf", "det", "gcd",
    "mod", "dim", "ker", "arg", "deg"
)

private val MX_DROP = setOf(
    "hat", "tilde", "dot", "ddot", "widehat", "widetilde", "mathcal", "mathscr",
    "mathsf", "displaystyle", "textstyle", "scriptstyle", "limits", "nolimits",
    "big", "Big", "bigg", "Bigg", "bigl", "bigr", "Bigl", "Bigr",
    "boldsymbol", "mathbf", "bf", "label", "nonumber", "hline", "centering"
)

private const val MX_OP_CHARS = "=+−<>≈≠≤≥×·÷±∓→←⇒⇔∈∪∩⊂≡∼"
private val MX_TEXT_STOP = setOf(' ', '\t', '\r', '\n', '\\', '^', '_', '{', '}', '$', '&')

private fun mxAscii(c: Char): Boolean = c in 'A'..'Z' || c in 'a'..'z'

// ---------------------------- ПАРСЕР ----------------------------
private class MxParser(private val s: String, startMath: Boolean) {
    private var i = 0
    private var math = startMath

    fun parseAll(): MxRow = parseRow(inGroup = false, inFence = false)

    private fun parseRow(inGroup: Boolean, inFence: Boolean): MxRow {
        val out = ArrayList<MxNode>()
        while (i < s.length) {
            val c = s[i]
            if (inGroup && c == '}') break
            if (inFence && s.startsWith("\\right", i)) break
            val atom = parseAtom()
            if (atom != null) out.add(atom)
        }
        return MxRow(out)
    }

    private fun parseAtom(): MxNode? {
        val c = s[i]
        if (c == '^' || c == '_') return withScripts(null)
        val b = parseBase() ?: return null
        return withScripts(b)
    }

    private fun withScripts(base: MxNode?): MxNode? {
        var sup: MxNode? = null
        var sub: MxNode? = null
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
        return if (sup == null && sub == null) base else MxScript(base, sup, sub)
    }

    private fun scriptArg(): MxNode {
        skipSpaces()
        if (i >= s.length) return MxRow(emptyList())
        val c = s[i]
        if (c == '{') return group()
        if (c == '\\') return command() ?: MxRow(emptyList())
        if (c == '}') return MxRow(emptyList())
        i++
        return charNode(c)
    }

    private fun arg(): MxNode {
        skipSpaces()
        if (i >= s.length) return MxRow(emptyList())
        val c = s[i]
        if (c == '{') return group()
        if (c == '\\') return command() ?: MxRow(emptyList())
        if (c == '}') return MxRow(emptyList())
        i++
        return charNode(c)
    }

    private fun charNode(c: Char): MxNode = when {
        c.isDigit() -> MxText(c.toString())
        mxAscii(c) -> MxText(c.toString(), italic = true)
        c == '-' -> MxText("−", op = true)
        else -> MxText(c.toString())
    }

    private fun skipSpaces() {
        while (i < s.length && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r' || s[i] == '\n')) i++
    }

    private fun group(): MxNode {
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

    private fun parseBase(): MxNode? {
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
            return MxBreak
        }
        if (c == '&') {
            i++
            return MxSpace(0.5f)
        }
        if (c == ' ' || c == '\t' || c == '\r') {
            i++
            if (math) return null
            while (i < s.length && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r')) i++
            return MxSpace(0.28f, breakable = true)
        }
        return if (math) mathChars() else textWord()
    }

    private fun mathChars(): MxNode {
        val c = s[i]
        if (c.isDigit()) {
            val st = i
            while (i < s.length && (s[i].isDigit() ||
                    ((s[i] == '.' || s[i] == ',') && i + 1 < s.length && s[i + 1].isDigit()))
            ) i++
            return MxText(s.substring(st, i))
        }
        if (mxAscii(c)) {
            val st = i
            while (i < s.length && mxAscii(s[i])) i++
            return MxText(s.substring(st, i), italic = true)
        }
        if (c.isLetter()) {
            val st = i
            while (i < s.length && s[i].isLetter() && !mxAscii(s[i])) i++
            return MxText(s.substring(st, i))
        }
        i++
        return when (c) {
            '-' -> MxText("−", op = true)
            '*' -> MxText("·", op = true)
            '\'' -> MxText("′")
            else -> MxText(c.toString(), op = MX_OP_CHARS.indexOf(c) >= 0)
        }
    }

    private fun textWord(): MxNode {
        val st = i
        while (i < s.length && s[i] !in MX_TEXT_STOP) i++
        if (i == st) i++
        return MxText(s.substring(st, i), serif = false)
    }

    private fun delim(): String {
        skipSpaces()
        if (i >= s.length) return "."
        val c = s[i]
        i++
        if (c != '\\') return c.toString()
        if (i >= s.length) return "."
        val st = i
        while (i < s.length && mxAscii(s[i])) i++
        if (i > st) return MX_SYMBOLS[s.substring(st, i)] ?: "."
        val d = s[i]
        i++
        return when (d) {
            '{' -> "{"
            '}' -> "}"
            '|' -> "‖"
            else -> "."
        }
    }

    /** Разбивает тело окружения: по \\ (строки) или по & (ячейки), не заходя в {} и вложенные окружения. */
    private fun splitTop(body: String, byRow: Boolean): List<String> {
        val out = ArrayList<String>()
        var depth = 0
        var env = 0
        var st = 0
        var k = 0
        while (k < body.length) {
            val ch = body[k]
            if (ch == '\\') {
                if (body.startsWith("\\begin", k)) {
                    env++
                    k += 6
                    continue
                }
                if (body.startsWith("\\end", k)) {
                    env--
                    k += 4
                    continue
                }
                if (k + 1 < body.length && body[k + 1] == '\\') {
                    if (byRow && depth == 0 && env == 0) {
                        out.add(body.substring(st, k))
                        st = k + 2
                    }
                    k += 2
                    continue
                }
                k += 2
                continue
            }
            if (ch == '{') {
                depth++
            } else if (ch == '}') {
                depth--
            } else if (!byRow && ch == '&' && depth == 0 && env == 0) {
                out.add(body.substring(st, k))
                st = k + 1
            }
            k++
        }
        out.add(body.substring(st))
        return out
    }

    private fun environment(env: String): MxNode? {
        if (env == "array" || env == "tabular") rawGroup()
        val start = i
        val endTag = "\\end{" + env + "}"
        val end = s.indexOf(endTag, start)
        val body = s.substring(start, if (end >= 0) end else s.length)
        i = if (end >= 0) end + endTag.length else s.length
        val spec: Array<String>? = when (env) {
            "cases" -> arrayOf("{", "", "l")
            "aligned", "align", "align*", "alignat", "split", "eqnarray" -> arrayOf("", "", "rl")
            "gathered", "gather", "gather*", "array", "tabular", "matrix" -> arrayOf("", "", "c")
            "pmatrix" -> arrayOf("(", ")", "c")
            "bmatrix" -> arrayOf("[", "]", "c")
            "vmatrix" -> arrayOf("|", "|", "c")
            "Vmatrix" -> arrayOf("‖", "‖", "c")
            "Bmatrix" -> arrayOf("{", "}", "c")
            else -> null
        }
        if (spec == null) return MxParser(body, true).parseAll()
        val rows: List<List<MxNode>> = splitTop(body, true)
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .map { row -> splitTop(row, false).map { cell -> MxParser(cell.trim(), true).parseAll() } }
        if (rows.isEmpty()) return null
        val table = MxTable(rows, spec[2])
        return if (spec[0].isEmpty() && spec[1].isEmpty()) table else MxFence(spec[0], spec[1], table)
    }

    private fun command(): MxNode? {
        i++
        if (i >= s.length) return null
        val st = i
        while (i < s.length && mxAscii(s[i])) i++
        val name = s.substring(st, i)

        if (name.isEmpty()) {
            val ch = s[i]
            i++
            return when (ch) {
                '\\' -> MxBreak
                ',', ';', ':', ' ' -> MxSpace(0.2f)
                '!' -> null
                '(' -> { math = true; null }
                ')' -> { math = false; null }
                '[' -> { math = true; MxBreak }
                ']' -> { math = false; MxBreak }
                '{', '}', '%', '&', '#', '_', '$' -> MxText(ch.toString(), serif = math)
                '|' -> MxText("‖")
                else -> MxText(ch.toString())
            }
        }

        if (name in MX_DROP) return null
        if (name == "begin") return environment(rawGroup().trim())
        if (name == "end") {
            rawGroup()
            return null
        }
        when (name) {
            "implies", "Longrightarrow", "Rightarrow" -> return MxArrow(1)
            "impliedby", "Longleftarrow", "Leftarrow" -> return MxArrow(-1)
            "iff", "Longleftrightarrow", "Leftrightarrow" -> return MxArrow(0)
        }
        if (name == "frac" || name == "dfrac" || name == "tfrac") {
            val a = arg()
            val b = arg()
            return MxFrac(a, b)
        }
        if (name == "sqrt") {
            var idx: MxNode? = null
            skipSpaces()
            if (i < s.length && s[i] == '[') {
                val close = s.indexOf(']', i)
                if (close > i) {
                    idx = MxParser(s.substring(i + 1, close), math).parseAll()
                    i = close + 1
                }
            }
            return MxSqrt(arg(), idx)
        }
        if (name == "left") {
            val open = delim()
            val body = parseRow(inGroup = false, inFence = true)
            var close = "."
            if (s.startsWith("\\right", i)) {
                i += 6
                close = delim()
            }
            return MxFence(open, close, body)
        }
        if (name == "right") {
            val d = delim()
            return MxText(if (d == ".") "" else d)
        }
        if (name == "text" || name == "textrm" || name == "mbox" || name == "textnormal") {
            return MxText(rawGroup(), serif = false)
        }
        if (name == "mathrm" || name == "operatorname" || name == "rm") return MxText(rawGroup())
        if (name == "mathbb") {
            val g = rawGroup()
            return MxText(
                when (g) {
                    "R" -> "ℝ"
                    "N" -> "ℕ"
                    "Z" -> "ℤ"
                    "Q" -> "ℚ"
                    "C" -> "ℂ"
                    else -> g
                }
            )
        }
        if (name == "textbf") return MxText(rawGroup(), serif = false, bold = true)
        if (name == "textit" || name == "mathit") return MxText(rawGroup(), italic = true)
        if (name == "overline" || name == "bar" || name == "underline") return MxAccent(arg(), false)
        if (name == "vec" || name == "overrightarrow") return MxAccent(arg(), true)
        if (name == "quad") return MxSpace(1f)
        if (name == "qquad") return MxSpace(2f)
        if (name in MX_FUNCS) return MxText(name, func = true)

        val sym = MX_SYMBOLS[name]
        if (sym != null) {
            return MxText(
                sym,
                italic = math && name in MX_GREEK_LOWER,
                op = name in MX_OPS,
                scale = if (name in MX_BIG) 1.3f else 1f
            )
        }
        return MxText(name)
    }
}

// ---------------------------- РАСКЛАДКА ----------------------------
private class MxBox(
    val w: Float,
    val asc: Float,
    val desc: Float,
    val draw: (android.graphics.Canvas, Float, Float) -> Unit
)

private class MxLayout(private val base: Float, private val ink: Int) {
    private val paints = HashMap<Int, Paint>()
    private val empty = MxBox(0f, 0f, 0f) { _, _, _ -> }

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

    fun box(n: MxNode, size: Float): MxBox = when (n) {
        is MxText -> text(n, size)
        is MxSpace -> MxBox(n.em * size, 0f, 0f) { _, _, _ -> }
        is MxRow -> row(n.items, size, null)
        is MxFrac -> frac(n, size)
        is MxScript -> script(n, size)
        is MxSqrt -> sqrt(n, size)
        is MxFence -> fence(n, size)
        is MxAccent -> accent(n, size)
        is MxTable -> table(n, size)
        is MxArrow -> arrow(n, size)
        is MxBreak -> empty
    }

    private fun text(n: MxText, size: Float): MxBox {
        val sz = size * n.scale
        val p = paint(sz, n.italic, n.serif, n.bold)
        val w = p.measureText(n.s) + (if (n.italic) sz * 0.05f else 0f)
        val dy = (n.scale - 1f) * size * 0.28f
        return MxBox(w, sz * 0.80f - dy, sz * 0.22f + dy) { c, x, y -> c.drawText(n.s, x, y + dy, p) }
    }

    private fun isFunc(n: MxNode): Boolean {
        if (n is MxText) return n.func
        if (n is MxScript) {
            val b = n.base
            return b is MxText && b.func
        }
        return false
    }

    fun row(items: List<MxNode>, size: Float, first: MxNode?): MxBox {
        val boxes = ArrayList<MxBox>(items.size)
        val xs = FloatArray(items.size)
        var x = 0f
        var asc = 0f
        var desc = 0f
        var prev: MxNode? = first
        for ((k, node) in items.withIndex()) {
            val b = box(node, size)
            var pre = 0f
            var post = 0f
            val isOp = (node is MxText && node.op) || node is MxArrow
            if (isOp) {
                val pv = prev
                val unary = pv == null || pv is MxArrow ||
                    (pv is MxText && (pv.op || pv.s == "(" || pv.s == "[" || pv.s == "{" || pv.s == ";" || pv.s == ","))
                if (!unary || node is MxArrow) {
                    pre = size * 0.20f
                    post = size * 0.20f
                }
            }
            if (node is MxText && (node.s == ";" || node.s == ",")) post += size * 0.17f
            if (isFunc(node)) {
                val nx = items.getOrNull(k + 1)
                if (nx != null && !(nx is MxText && (nx.s == "(" || nx.s == "["))) post += size * 0.17f
            }
            x += pre
            xs[k] = x
            boxes.add(b)
            x += b.w + post
            if (b.asc > asc) asc = b.asc
            if (b.desc > desc) desc = b.desc
            prev = node
        }
        return MxBox(x, asc, desc) { c, ox, oy ->
            for (k in boxes.indices) boxes[k].draw(c, ox + xs[k], oy)
        }
    }

    private fun frac(n: MxFrac, size: Float): MxBox {
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
        return MxBox(w, asc, desc) { c, x, y ->
            val yBar = y - axis
            nb.draw(c, x + (w - nb.w) / 2f, yBar - th / 2f - gap - nb.desc)
            db.draw(c, x + (w - db.w) / 2f, yBar + th / 2f + gap + db.asc)
            c.drawLine(x + pad * 0.4f, yBar, x + w - pad * 0.4f, yBar, bp)
        }
    }

    private fun script(n: MxScript, size: Float): MxBox {
        val b0 = if (n.base != null) box(n.base, size)
        else MxBox(0f, size * 0.80f, size * 0.22f) { _, _, _ -> }
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
        return MxBox(w, asc, desc) { c, x, y ->
            b0.draw(c, x, y)
            if (sup != null) sup.draw(c, x + b0.w + gap, y - sShift)
            if (sub != null) sub.draw(c, x + b0.w + gap, y + subShift)
        }
    }

    private fun sqrt(n: MxSqrt, size: Float): MxBox {
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
        return MxBox(w, asc, desc) { c, x, y ->
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

    private fun drawDelim(
        c: android.graphics.Canvas, ch: String, x: Float, top: Float, bottom: Float, w: Float, th: Float
    ) {
        val pt = stroke(th, true)
        val mid = (top + bottom) / 2f
        val path = Path()
        when (ch) {
            "{", "}" -> {
                val left = ch == "{"
                val r = minOf(w * 0.9f, (bottom - top) / 4f)
                val cx = w / 2f
                fun px(d: Float): Float = if (left) x + d else x + w - d
                path.moveTo(px(w), top)
                path.quadTo(px(cx), top, px(cx), top + r)
                path.lineTo(px(cx), mid - r)
                path.quadTo(px(cx), mid, px(0f), mid)
                path.quadTo(px(cx), mid, px(cx), mid + r)
                path.lineTo(px(cx), bottom - r)
                path.quadTo(px(cx), bottom, px(w), bottom)
            }
            "(" -> {
                path.moveTo(x + w, top)
                path.quadTo(x - w * 0.2f, mid, x + w, bottom)
            }
            ")" -> {
                path.moveTo(x, top)
                path.quadTo(x + w * 1.2f, mid, x, bottom)
            }
            "[" -> {
                path.moveTo(x + w, top)
                path.lineTo(x + w * 0.2f, top)
                path.lineTo(x + w * 0.2f, bottom)
                path.lineTo(x + w, bottom)
            }
            "]" -> {
                path.moveTo(x, top)
                path.lineTo(x + w * 0.8f, top)
                path.lineTo(x + w * 0.8f, bottom)
                path.lineTo(x, bottom)
            }
            "|" -> {
                path.moveTo(x + w / 2f, top)
                path.lineTo(x + w / 2f, bottom)
            }
            "‖" -> {
                path.moveTo(x + w * 0.35f, top)
                path.lineTo(x + w * 0.35f, bottom)
                path.moveTo(x + w * 0.65f, top)
                path.lineTo(x + w * 0.65f, bottom)
            }
        }
        c.drawPath(path, pt)
    }

    private fun delimBox(ch: String, size: Float, bb: MxBox): MxBox {
        if (ch.isEmpty() || ch == ".") return MxBox(size * 0.02f, bb.asc, bb.desc) { _, _, _ -> }
        val h = bb.asc + bb.desc
        val p = paint(size, false, true, false)
        if (h <= size * 1.25f) {
            val gw = p.measureText(ch) + size * 0.02f
            return MxBox(gw, maxOf(bb.asc, size * 0.80f), maxOf(bb.desc, size * 0.22f)) { c, x, y ->
                c.drawText(ch, x, y, p)
            }
        }
        if ("{}()[]|‖".contains(ch)) {
            val w = if (ch == "{" || ch == "}") size * 0.40f else size * 0.30f
            return MxBox(w, bb.asc, bb.desc) { c, x, y ->
                drawDelim(c, ch, x, y - bb.asc, y + bb.desc, w, size * 0.06f)
            }
        }
        val gw = p.measureText(ch) + size * 0.02f
        val k = (h / size).coerceIn(1f, 4f)
        return MxBox(gw, bb.asc, bb.desc) { c, x, y ->
            val cy = y - (bb.asc - bb.desc) / 2f
            c.save()
            c.translate(x, cy)
            c.scale(1f, k)
            c.drawText(ch, 0f, size * 0.27f, p)
            c.restore()
        }
    }

    private fun fence(n: MxFence, size: Float): MxBox {
        val bb = box(n.body, size)
        val lb = delimBox(n.open, size, bb)
        val rb = delimBox(n.close, size, bb)
        val gap = size * 0.06f
        val w = lb.w + gap + bb.w + gap + rb.w
        val asc = maxOf(bb.asc, maxOf(lb.asc, rb.asc))
        val desc = maxOf(bb.desc, maxOf(lb.desc, rb.desc))
        return MxBox(w, asc, desc) { c, x, y ->
            lb.draw(c, x, y)
            bb.draw(c, x + lb.w + gap, y)
            rb.draw(c, x + lb.w + gap + bb.w + gap, y)
        }
    }

    private fun table(n: MxTable, size: Float): MxBox {
        val cells: List<List<MxBox>> = n.rows.map { r -> r.map { box(it, size) } }
        val cols = cells.maxOfOrNull { it.size } ?: 0
        if (cols == 0) return empty
        val colW = FloatArray(cols)
        for (r in cells) {
            for ((j, b) in r.withIndex()) if (b.w > colW[j]) colW[j] = b.w
        }
        val rowAsc = FloatArray(cells.size)
        val rowDesc = FloatArray(cells.size)
        for ((i, r) in cells.withIndex()) {
            var a = size * 0.80f
            var d = size * 0.22f
            for (b in r) {
                if (b.asc > a) a = b.asc
                if (b.desc > d) d = b.desc
            }
            rowAsc[i] = a
            rowDesc[i] = d
        }
        val gapY = size * 0.32f
        val colX = FloatArray(cols)
        var x = 0f
        for (j in 0 until cols) {
            colX[j] = x
            val gap = if (j >= cols - 1) 0f else if (n.align == "rl") (if (j % 2 == 0) 0f else size * 1.6f) else size
            x += colW[j] + gap
        }
        val tw = x
        var th = 0f
        for (i in cells.indices) th += rowAsc[i] + rowDesc[i] + (if (i < cells.size - 1) gapY else 0f)
        val axis = size * 0.30f
        val asc = th / 2f + axis
        val desc = maxOf(0f, th / 2f - axis)
        return MxBox(tw, asc, desc) { c, ox, oy ->
            var y = oy - asc
            for (i in cells.indices) {
                val baseline = y + rowAsc[i]
                for ((j, b) in cells[i].withIndex()) {
                    val dx = when (n.align) {
                        "l" -> 0f
                        "rl" -> if (j % 2 == 0) colW[j] - b.w else 0f
                        else -> (colW[j] - b.w) / 2f
                    }
                    b.draw(c, ox + colX[j] + dx, baseline)
                }
                y += rowAsc[i] + rowDesc[i] + gapY
            }
        }
    }

    private fun arrow(n: MxArrow, size: Float): MxBox {
        val w = size * 1.35f
        val th = maxOf(1f, size * 0.055f)
        val sp = stroke(th, true)
        return MxBox(w, size * 0.55f, size * 0.10f) { c, x, y ->
            val cy = y - size * 0.30f
            val off = size * 0.07f
            val head = size * 0.26f
            val pad = size * 0.04f
            val x0 = x + pad
            val x1 = x + w - pad
            val lx0 = if (n.kind <= 0) x0 + head * 0.6f else x0
            val lx1 = if (n.kind >= 0) x1 - head * 0.6f else x1
            c.drawLine(lx0, cy - off, lx1, cy - off, sp)
            c.drawLine(lx0, cy + off, lx1, cy + off, sp)
            if (n.kind >= 0) {
                val pr = Path()
                pr.moveTo(x1 - head, cy - head * 0.85f)
                pr.lineTo(x1, cy)
                pr.lineTo(x1 - head, cy + head * 0.85f)
                c.drawPath(pr, sp)
            }
            if (n.kind <= 0) {
                val pl = Path()
                pl.moveTo(x0 + head, cy - head * 0.85f)
                pl.lineTo(x0, cy)
                pl.lineTo(x0 + head, cy + head * 0.85f)
                c.drawPath(pl, sp)
            }
        }
    }

    private fun accent(n: MxAccent, size: Float): MxBox {
        val bb = box(n.body, size)
        val th = maxOf(1f, size * 0.05f)
        val gap = size * 0.10f
        val sp = stroke(th)
        val extra = if (n.vec) size * 0.22f else size * 0.14f
        return MxBox(bb.w, bb.asc + extra, bb.desc) { c, x, y ->
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

/** Текст с LaTeX -> строки с готовой отрисовкой (перенос по пробелам и знакам операций). */
fun mxLayout(src: String, base: Float, maxW: Float, ink: Int): List<MxLine> {
    val text = src.replace("\r", "")
    val hasDelims = text.contains("\\(") || text.contains("\\[") || text.indexOf('$') >= 0
    val nodes = ArrayList<MxNode>()
    if (hasDelims) {
        nodes.addAll(MxParser(text, false).parseAll().items)
    } else {
        val ls = text.split("\n")
        for ((idx, ln) in ls.withIndex()) {
            if (idx > 0) nodes.add(MxBreak)
            val mathy = ln.any { it == '\\' || it == '^' || it == '_' || it == '{' }
            nodes.addAll(MxParser(ln, mathy).parseAll().items)
        }
    }

    val lay = MxLayout(base, ink)
    val lines = ArrayList<MxLine>()
    var chunks = ArrayList<MxBox>()
    var curW = 0f
    var curAsc = base * 0.80f
    var curDesc = base * 0.22f
    var hint: MxNode? = null

    fun flush() {
        if (chunks.isEmpty()) return
        val cs = chunks
        val a = curAsc
        val d = curDesc
        val w = curW
        lines.add(MxLine(w, a + d + base * 0.28f) { c ->
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
            lines.add(MxLine(0f, base * 0.5f) { _ -> })
        }
    }

    fun place(items: List<MxNode>) {
        if (items.isEmpty()) return
        val b = lay.row(items, base, hint)
        hint = items[items.size - 1]
        if (chunks.isNotEmpty() && curW + b.w > maxW) flush()
        chunks.add(b)
        curW += b.w
        if (b.asc > curAsc) curAsc = b.asc
        if (b.desc > curDesc) curDesc = b.desc
    }

    var pending = ArrayList<MxNode>()
    for (node in nodes) {
        if (node is MxBreak) {
            place(pending)
            pending = ArrayList()
            if (chunks.isEmpty()) blank() else flush()
            hint = null
            continue
        }
        pending.add(node)
        val isOp = (node is MxText && node.op) || node is MxArrow
        val isSpace = node is MxSpace && node.breakable
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
fun MxFormulaLine(line: MxLine, availPx: Float) {
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

/** Готовый блок «текст с формулами» на всю ширину (для просмотра файла на телефоне). */
@Composable
fun MxFormulaText(text: String, baseSizeSp: Float, color: Color, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier) {
        val density = LocalDensity.current
        val availPx = with(density) { maxWidth.toPx() }
        val base = with(density) { baseSizeSp.sp.toPx() }
        val ink = color.toArgb()
        val lines = remember(text, availPx, base, ink) {
            try {
                mxLayout(text, base, availPx, ink)
            } catch (e: Throwable) {
                null
            }
        }
        Column {
            if (lines != null) {
                for (l in lines) MxFormulaLine(l, availPx)
            } else {
                BasicText(text, style = TextStyle(color = color, fontSize = baseSizeSp.sp))
            }
        }
    }
}
