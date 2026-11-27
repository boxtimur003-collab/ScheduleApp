#!/data/data/com.termux/files/usr/bin/bash
set +H
cd "${1:-$HOME/ScheduleApp}" || { echo 'Папка проекта не найдена'; exit 1; }

AOS=$(find app -name MainActivity.kt -not -path '*/build/*' 2>/dev/null | head -1)
WOS=$(find wear -name MainActivity.kt -not -path '*/build/*' 2>/dev/null | head -1)
WF=$(find wear -name ScheduleWatchFaceService.kt -not -path '*/build/*' 2>/dev/null | head -1)
if [ -z "$AOS" ] || [ -z "$WOS" ] || [ -z "$WF" ]; then
  echo 'Файлы проекта не найдены (нужен циферблат из прошлых скриптов). Запусти из корня проекта'; exit 1
fi
ADIR=$(dirname "$AOS"); WDIR=$(dirname "$WOS")
APKG=$(grep -m1 '^package' "$AOS" | tr -d '\r' | sed 's/^package[[:space:]]*//; s/[[:space:]]*$//')
WPKG=$(grep -m1 '^package' "$WOS" | tr -d '\r' | sed 's/^package[[:space:]]*//; s/[[:space:]]*$//')
[ -z "$APKG" ] && APKG="com.example.schedule"
[ -z "$WPKG" ] && WPKG="$APKG"
EXTRAS=$(find app -name Extras.kt -not -path '*/build/*' 2>/dev/null | head -1)
[ -z "$EXTRAS" ] && EXTRAS="$ADIR/Extras.kt"
echo "APP: DIR=$ADIR PKG=$APKG"
echo "WEAR: DIR=$WDIR PKG=$WPKG"

BAK="$HOME/.schedule_bak/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BAK"
cp "$WOS" "$BAK/wear_MainActivity.kt"
cp "$WF" "$BAK/wear_ScheduleWatchFaceService.kt"
[ -f "$EXTRAS" ] && cp "$EXTRAS" "$BAK/app_Extras.kt"
echo "Резервные копии: $BAK"

# =====================================================================
#  ОБЩИЙ ДВИЖОК ФОРМУЛ (телефон + часы): MathEngine.kt
# =====================================================================
cat << 'KT_EOF' > "$ADIR/MathEngine.kt"
package PKG__

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
KT_EOF
cp "$ADIR/MathEngine.kt" "$WDIR/MathEngine.kt"

# =====================================================================
#  ТЕЛЕФОН: Extras.kt («Мои файлы»: Смотреть / Редактировать)
# =====================================================================
cat << 'KT_EOF' > "$EXTRAS"
package PKG__

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalTime
import java.time.format.DateTimeFormatter

// ---------------------- история отправленных файлов (SharedPreferences) ----------------------
data class SentFile(val id: String, val name: String, val text: String, val time: String)

object SentStore {
    private fun sp(ctx: Context) = ctx.getSharedPreferences("sent_files", Context.MODE_PRIVATE)

    fun load(ctx: Context): List<SentFile> = try {
        val a = JSONArray(sp(ctx).getString("json", "[]"))
        (0 until a.length()).map {
            val o = a.getJSONObject(it)
            SentFile(o.getString("id"), o.optString("name", "Файл"), o.optString("text", ""), o.optString("time", ""))
        }
    } catch (e: Exception) {
        emptyList()
    }

    private fun save(ctx: Context, list: List<SentFile>) {
        val a = JSONArray()
        list.forEach {
            a.put(JSONObject().put("id", it.id).put("name", it.name).put("text", it.text).put("time", it.time))
        }
        sp(ctx).edit().putString("json", a.toString()).apply()
    }

    fun toJson(f: SentFile): String =
        JSONObject().put("id", f.id).put("name", f.name).put("text", f.text).put("time", f.time).toString()

    @Synchronized
    fun upsert(ctx: Context, id: String, name: String, text: String, time: String): SentFile {
        val list = load(ctx).toMutableList()
        val nid = id.ifBlank { System.currentTimeMillis().toString() }
        val t = time.ifBlank { LocalTime.now().format(DateTimeFormatter.ofPattern("HH:mm")) }
        val i = list.indexOfFirst { it.id == nid }
        val f = if (i >= 0) {
            list[i].copy(name = name.ifBlank { list[i].name }, text = text, time = t)
        } else {
            val n = sp(ctx).getInt("counter", 0) + 1
            sp(ctx).edit().putInt("counter", n).apply()
            SentFile(nid, name.ifBlank { "Файл $n" }, text, t)
        }
        if (i >= 0) list[i] = f else list.add(f)
        save(ctx, list)
        return f
    }

    @Synchronized
    fun delete(ctx: Context, id: String) {
        save(ctx, load(ctx).filter { it.id != id })
    }
}

// ---------------------- разрешение на уведомления ----------------------
@Composable
fun NotifPermission() {
    val ctx = LocalContext.current
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    LaunchedEffect(Unit) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
}

// ---------------------- «Напоминание» в EditScreen ----------------------
@Composable
fun NotifyRow(value: Int, onChange: (Int) -> Unit) {
    val c = C
    var menu by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(c.card)
                .clickable { menu = true }.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Filled.Notifications, null, tint = c.sub)
            Text("Напоминание", fontSize = 16.sp, color = c.text, modifier = Modifier.weight(1f).padding(start = 12.dp))
            Text(notifyLabel(value), color = c.accent, fontSize = 15.sp)
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            NOTIFY_OPTIONS.forEach { (k, v) ->
                DropdownMenuItem(text = { Text(v) }, onClick = { onChange(k); menu = false })
            }
        }
    }
}

// ---------------------- «Мои файлы» ----------------------
@Composable
fun MyFilesHost(onClose: () -> Unit) {
    val c = C
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var files by remember { mutableStateOf(SentStore.load(ctx)) }
    var choosing by remember { mutableStateOf<SentFile?>(null) }
    var viewing by remember { mutableStateOf<SentFile?>(null) }
    var editing by remember { mutableStateOf<SentFile?>(null) }
    BackHandler {
        if (editing != null) {
            editing = null
        } else if (viewing != null) {
            viewing = null
        } else {
            onClose()
        }
    }

    fun toast(r: Int) {
        val msg = when {
            r > 0 -> "Отправлено на часы"
            r == -2 -> "Текст слишком большой"
            else -> "Сохранено на телефоне, часы не найдены"
        }
        Toast.makeText(ctx, msg, Toast.LENGTH_SHORT).show()
    }

    val ed = editing
    val vw = viewing
    Column(Modifier.fillMaxSize().background(c.bg).pointerInput(Unit) {}) {
        if (ed == null && vw == null) {
            // ---------- список ----------
            Row(
                Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onClose) { Icon(Icons.Filled.ArrowBack, null, tint = c.text) }
                Text("Мои файлы", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = c.text)
            }
            if (files.isEmpty()) {
                Text("Отправленных файлов пока нет", color = c.sub, modifier = Modifier.padding(16.dp))
            }
            LazyColumn(
                Modifier.weight(1f).fillMaxWidth(),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp)
            ) {
                items(files.reversed(), key = { it.id }) { f ->
                    Row(
                        Modifier.fillMaxWidth().padding(vertical = 4.dp).clip(RoundedCornerShape(12.dp))
                            .background(c.card).clickable { choosing = f }.padding(start = 14.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(Modifier.weight(1f).padding(vertical = 10.dp)) {
                            Text(f.name, fontSize = 16.sp, fontWeight = FontWeight.Medium, color = c.text)
                            Text(
                                f.text.lineSequence().firstOrNull().orEmpty(),
                                fontSize = 13.sp, color = c.sub, maxLines = 1, overflow = TextOverflow.Ellipsis
                            )
                        }
                        Text(f.time, fontSize = 13.sp, color = c.sub)
                        IconButton(onClick = {
                            SentStore.delete(ctx, f.id)
                            files = SentStore.load(ctx)
                            scope.launch { DataSyncService.sendFileDelete(ctx, f.id) }
                        }) { Icon(Icons.Filled.Delete, null, tint = Color(0xFFE53935)) }
                    }
                }
            }
        } else if (vw != null) {
            // ---------- просмотр (формулы отрисованы) ----------
            Row(
                Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = { viewing = null }) { Icon(Icons.Filled.ArrowBack, null, tint = c.text) }
                Text(
                    vw.name, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = c.text,
                    modifier = Modifier.weight(1f)
                )
                IconButton(onClick = { editing = vw; viewing = null }) {
                    Icon(Icons.Filled.Edit, null, tint = c.accent)
                }
            }
            Column(
                Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp)
            ) {
                MxFormulaText(vw.text, 20f, c.text, Modifier.fillMaxWidth())
                Spacer(Modifier.height(32.dp))
            }
        } else if (ed != null) {
            // ---------- редактирование (обычный текст) ----------
            var text by remember(ed.id) { mutableStateOf(ed.text) }
            Row(
                Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = { editing = null }) { Icon(Icons.Filled.Close, null, tint = c.text) }
                Text(
                    ed.name, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = c.text,
                    modifier = Modifier.weight(1f)
                )
                IconButton(onClick = {
                    SentStore.delete(ctx, ed.id)
                    files = SentStore.load(ctx)
                    editing = null
                    scope.launch { DataSyncService.sendFileDelete(ctx, ed.id) }
                }) { Icon(Icons.Filled.Delete, null, tint = Color(0xFFE53935)) }
            }
            OutlinedTextField(
                value = text, onValueChange = { text = it },
                label = { Text("Текст или формулы") },
                modifier = Modifier.weight(1f).fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)
            )
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                TextButton(onClick = { editing = null }) { Text("Отмена", fontSize = 16.sp) }
                TextButton(onClick = {
                    if (text.isNotBlank()) {
                        val time = LocalTime.now().format(DateTimeFormatter.ofPattern("HH:mm"))
                        val saved = SentStore.upsert(ctx, ed.id, ed.name, text, time)
                        files = SentStore.load(ctx)
                        editing = null
                        scope.launch { toast(DataSyncService.sendFile(ctx, SentStore.toJson(saved))) }
                    }
                }) { Text("Сохранить и отправить", fontSize = 16.sp, fontWeight = FontWeight.Bold) }
            }
        }
    }

    choosing?.let { f ->
        AlertDialog(
            onDismissRequest = { choosing = null },
            title = { Text(f.name) },
            text = {
                Text(
                    f.text.lineSequence().firstOrNull().orEmpty(),
                    maxLines = 2, overflow = TextOverflow.Ellipsis
                )
            },
            confirmButton = {
                Column(horizontalAlignment = Alignment.End) {
                    TextButton(onClick = { viewing = f; choosing = null }) { Text("Смотреть") }
                    TextButton(onClick = { editing = f; choosing = null }) { Text("Редактировать") }
                    TextButton(onClick = { choosing = null }) { Text("Отмена") }
                }
            }
        )
    }
}
KT_EOF

# =====================================================================
#  ЧАСЫ: WearPin.kt (кнопка «показать на циферблате»)
# =====================================================================
cat << 'KT_EOF' > "$WDIR/WearPin.kt"
package PKG__

import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Watch
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.wear.compose.material.Icon

/** Закрепляет файл на циферблате и возвращает на экран часов. Нужен выбранный циферблат «Расписание». */
fun pinToFace(ctx: Context, f: WearFile) {
    ctx.getSharedPreferences("files", Context.MODE_PRIVATE).edit().putString("pinned", f.id).apply()
    Toast.makeText(ctx, "Файл на циферблате «Расписание»", Toast.LENGTH_SHORT).show()
    try {
        ctx.startActivity(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    } catch (e: Exception) {
    }
}

@Composable
fun PinButton(f: WearFile) {
    val ctx = LocalContext.current
    Box(
        Modifier.padding(start = 8.dp).size(28.dp).clip(CircleShape)
            .background(Color(0x667C5CFF)).clickable { pinToFace(ctx, f) },
        contentAlignment = Alignment.Center
    ) {
        Icon(Icons.Filled.Watch, "На циферблат", tint = Color.White, modifier = Modifier.size(16.dp))
    }
}
KT_EOF

# =====================================================================
#  ЧАСЫ: патчи MainActivity.kt (старый движок -> новый, кнопка закрепления)
# =====================================================================
S=$(grep -n '^private typealias NCanvas' "$WOS" | head -1 | cut -d: -f1)
E=$(grep -n '^class MainActivity : ComponentActivity() {' "$WOS" | head -1 | cut -d: -f1)
if [ -n "$S" ] && [ -n "$E" ] && [ "$E" -gt "$S" ] && [ $((E - S)) -ge 200 ] && [ $((E - S)) -le 1100 ]; then
  sed -i "${S},$((E - 1))d" "$WOS"
  echo "Часы: старый движок формул удалён ($((E - S)) строк)"
else
  echo '!! Часы: блок старого движка не найден или нестандартный; он остаётся (конфликтов нет, имена разные)'
fi
sed -i 's/layoutFormula(f\.text/mxLayout(f.text/' "$WOS"
sed -i 's/FormulaLine(line, availPx)/MxFormulaLine(line, availPx)/' "$WOS"
# защита от двойной замены MxMxFormulaLine
sed -i 's/MxMxFormulaLine/MxFormulaLine/g' "$WOS"

if ! grep -q 'PinButton(f)' "$WOS"; then
  sed -i '/Text(f\.time, color = Pal\.Dim, fontSize = 12\.sp)/a\
                    PinButton(f)' "$WOS"
fi

# =====================================================================
#  ЧАСЫ: циферблат (секундная линия по кругу + закреплённый файл)
# =====================================================================
cat << 'KT_EOF' > "$WF"
package PKG__

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.os.BatteryManager
import android.view.SurfaceHolder
import androidx.wear.watchface.CanvasType
import androidx.wear.watchface.ComplicationSlot
import androidx.wear.watchface.ComplicationSlotsManager
import androidx.wear.watchface.DrawMode
import androidx.wear.watchface.Renderer
import androidx.wear.watchface.TapEvent
import androidx.wear.watchface.TapType
import androidx.wear.watchface.WatchFace
import androidx.wear.watchface.WatchFaceService
import androidx.wear.watchface.WatchFaceType
import androidx.wear.watchface.WatchState
import androidx.wear.watchface.style.CurrentUserStyleRepository
import org.json.JSONArray
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/** С какого экрана открыть приложение: циферблат передаёт extra "open" = files | dates. */
fun initialOverlay(ctx: Context): Overlay {
    var c: Context? = ctx
    while (c is ContextWrapper) {
        if (c is Activity) {
            return when (c.intent?.getStringExtra("open")) {
                "files" -> Overlay.FILES
                "dates" -> Overlay.DATES
                else -> Overlay.NONE
            }
        }
        c = c.baseContext
    }
    return Overlay.NONE
}

private val WF_PURPLE = 0xFF7C5CFF.toInt()
private val WF_LILAC = 0xFFA78BFA.toInt()
private val WF_GREEN = 0xFF4CC36B.toInt()
private val WF_DIM = 0xFFB8B2D6.toInt()
private val WF_SOFT = 0xFFE6E0FF.toInt()
private val WF_CARD = 0xFF17161F.toInt()
private val WF_PILL = 0xFF14131C.toInt()
private val WF_RING = 0xFF2A2740.toInt()
private val WF_BTN = 0xFF1B1A22.toInt()
private val WF_DOT = 0xFF3A3A44.toInt()
private val WF_COLON = 0xFF8C88A8.toInt()

private class PinnedFile(val id: String, val name: String, val text: String)

class ScheduleWatchFaceService : WatchFaceService() {
    override suspend fun createWatchFace(
        surfaceHolder: SurfaceHolder,
        watchState: WatchState,
        complicationSlotsManager: ComplicationSlotsManager,
        currentUserStyleRepository: CurrentUserStyleRepository
    ): WatchFace {
        val renderer = ScheduleRenderer(applicationContext, surfaceHolder, currentUserStyleRepository, watchState)
        val face = WatchFace(WatchFaceType.DIGITAL, renderer)
        face.setTapListener(object : WatchFace.TapListener {
            override fun onTapEvent(tapType: Int, tapEvent: TapEvent, complicationSlot: ComplicationSlot?) {
                if (tapType == TapType.UP) renderer.onTap(tapEvent.xPos.toFloat(), tapEvent.yPos.toFloat())
            }
        })
        return face
    }
}

private class ScheduleRenderer(
    private val ctx: Context,
    surfaceHolder: SurfaceHolder,
    currentUserStyleRepository: CurrentUserStyleRepository,
    watchState: WatchState
) : Renderer.CanvasRenderer2<ScheduleRenderer.Assets>(
    surfaceHolder, currentUserStyleRepository, watchState,
    CanvasType.HARDWARE, 100L, false
) {
    class Assets : Renderer.SharedAssets {
        override fun onDestroy() {}
    }

    private class Hit(val r: RectF, val target: String)

    /** current - идёт сейчас; next - ближайшее после него; between - перерыв между занятиями. */
    private class Status(val current: Lesson?, val next: Lesson?, val between: Boolean)

    private val prefs: SharedPreferences = ctx.getSharedPreferences("schedule", Context.MODE_PRIVATE)
    private val filePrefs: SharedPreferences = ctx.getSharedPreferences("files", Context.MODE_PRIVATE)

    @Volatile
    private var lessons: List<Lesson> = loadLessons()

    @Volatile
    private var pinned: PinnedFile? = loadPinned()

    private var pinKey = ""
    private var pinPages: List<List<MxLine>> = emptyList()
    private var pinPage = 0

    // слушатели хранятся в полях: SharedPreferences держит их только слабой ссылкой
    private val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key == "json") {
            lessons = loadLessons()
            invalidate()
        }
    }
    private val fileListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key == "json" || key == "pinned") {
            pinned = loadPinned()
            pinKey = ""
            invalidate()
        }
    }

    private val p = Paint(Paint.ANTI_ALIAS_FLAG)
    private val normalFace: Typeface = Typeface.create("sans-serif", Typeface.NORMAL)
    private val boldFace: Typeface = Typeface.create("sans-serif", Typeface.BOLD)
    private val heavyFace: Typeface = Typeface.create("sans-serif-black", Typeface.NORMAL)
    private val dateFmt = DateTimeFormatter.ofPattern("EEE, d MMM", Locale("ru"))
    private val hits = ArrayList<Hit>()
    private var originX = 0f
    private var originY = 0f

    init {
        prefs.registerOnSharedPreferenceChangeListener(listener)
        filePrefs.registerOnSharedPreferenceChangeListener(fileListener)
    }

    private fun loadLessons(): List<Lesson> =
        LessonJson.fromJson(prefs.getString("json", "[]") ?: "[]")

    private fun loadPinned(): PinnedFile? {
        val id = filePrefs.getString("pinned", null) ?: return null
        return try {
            val a = JSONArray(filePrefs.getString("json", "[]") ?: "[]")
            var res: PinnedFile? = null
            for (k in 0 until a.length()) {
                val o = a.getJSONObject(k)
                if (o.optString("id") == id) {
                    res = PinnedFile(id, o.optString("name", "Файл"), o.optString("text", ""))
                    break
                }
            }
            res
        } catch (e: Exception) {
            null
        }
    }

    override suspend fun createSharedAssets(): Assets = Assets()

    override fun render(canvas: Canvas, bounds: Rect, zonedDateTime: ZonedDateTime, sharedAssets: Assets) {
        hits.clear()
        originX = bounds.left.toFloat()
        originY = bounds.top.toFloat()
        val s = bounds.width().toFloat()
        canvas.drawColor(Color.BLACK)
        canvas.save()
        canvas.translate(originX, originY)
        val pf = pinned
        if (renderParameters.drawMode == DrawMode.AMBIENT) drawAmbient(canvas, s, zonedDateTime)
        else if (pf != null) drawPinned(canvas, s, zonedDateTime, pf)
        else drawInteractive(canvas, s, zonedDateTime)
        canvas.restore()
    }

    override fun renderHighlightLayer(canvas: Canvas, bounds: Rect, zonedDateTime: ZonedDateTime, sharedAssets: Assets) {
        canvas.drawColor(Color.TRANSPARENT)
    }

    // ---------------- нажатия ----------------
    fun onTap(x: Float, y: Float) {
        val lx = x - originX
        val ly = y - originY
        val target = hits.firstOrNull { it.r.contains(lx, ly) }?.target ?: "app"
        when (target) {
            "unpin" -> filePrefs.edit().remove("pinned").apply()
            "next" -> {
                if (pinPage < pinPages.size - 1) pinPage++
                invalidate()
            }
            "prev" -> {
                if (pinPage > 0) pinPage--
                invalidate()
            }
            else -> open(target)
        }
    }

    private fun open(target: String) {
        val i = Intent(ctx, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            .putExtra("open", target)
        try {
            PendingIntent.getActivity(
                ctx, target.hashCode(), i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            ).send()
        } catch (e: Exception) {
            try {
                ctx.startActivity(i)
            } catch (e2: Exception) {
            }
        }
    }

    // ---------------- помощники рисования ----------------
    private fun fill(color: Int) {
        p.reset(); p.isAntiAlias = true
        p.style = Paint.Style.FILL; p.color = color
    }

    private fun stroke(color: Int, w: Float) {
        p.reset(); p.isAntiAlias = true
        p.style = Paint.Style.STROKE; p.color = color; p.strokeWidth = w
        p.strokeCap = Paint.Cap.ROUND; p.strokeJoin = Paint.Join.ROUND
    }

    private fun measure(str: String, size: Float, face: Typeface): Float {
        p.reset(); p.textSize = size; p.typeface = face
        return p.measureText(str)
    }

    private fun txt(
        c: Canvas, str: String, x: Float, y: Float, size: Float, color: Int, face: Typeface,
        align: Paint.Align = Paint.Align.LEFT, maxW: Float = 0f
    ) {
        p.reset(); p.isAntiAlias = true; p.style = Paint.Style.FILL
        p.color = color; p.textSize = size; p.typeface = face; p.textAlign = align
        var out = str
        if (maxW > 0f && p.measureText(out) > maxW) {
            var n = out.length
            while (n > 1 && p.measureText(out, 0, n) + p.measureText("…") > maxW) n--
            out = out.substring(0, n) + "…"
        }
        c.drawText(out, x, y, p)
    }

    private fun withAlpha(col: Int, a: Int): Int = Color.argb(a, Color.red(col), Color.green(col), Color.blue(col))

    private fun colorInt(hex: String): Int = try {
        Color.parseColor(hex)
    } catch (e: Exception) {
        WF_PURPLE
    }

    private fun hm(s: String): Int =
        (s.substringBefore(":").toIntOrNull() ?: 0) * 60 + (s.substringAfter(":").toIntOrNull() ?: 0)

    private fun battery(): Int = try {
        (ctx.getSystemService(Context.BATTERY_SERVICE) as BatteryManager)
            .getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
    } catch (e: Exception) {
        -1
    }

    private fun lw(n: Int): String {
        val a = n % 100
        val b = n % 10
        return if (a in 11..14) "уроков" else when (b) {
            1 -> "урок"
            in 2..4 -> "урока"
            else -> "уроков"
        }
    }

    // ---------------- логика «сейчас / следующее» ----------------
    private fun status(all: List<Lesson>, nowMin: Int): Status {
        val timed = all.filter { !it.isAllDay }.sortedBy { hm(it.start) }
        val cur = timed.firstOrNull { hm(it.start) <= nowMin && nowMin < hm(it.end) }
        val nxt = timed.firstOrNull { it !== cur && hm(it.start) > nowMin }
        val past = timed.any { hm(it.end) <= nowMin }
        return Status(cur, nxt, cur == null && nxt != null && past)
    }

    /** Сколько минут (с округлением вверх) осталось до момента target (в минутах от полуночи). */
    private fun minsUntil(target: Int, nowMin: Int, sec: Int): Int =
        (((target - nowMin) * 60 - sec) + 59) / 60

    private fun dur(m: Int): String {
        val v = if (m < 1) 1 else m
        return if (v < 60) {
            "$v мин"
        } else {
            val h = v / 60
            val r = v % 60
            if (r == 0) "$h ч" else "$h ч $r мин"
        }
    }

    // ---------------- бегущая линия по кругу вместо секундной стрелки ----------------
    private fun drawRing(c: Canvas, s: Float, t: ZonedDateTime) {
        val sw = s * 0.012f
        val inset = sw / 2f + s * 0.008f
        val oval = RectF(inset, inset, s - inset, s - inset)
        stroke(WF_RING, sw)
        c.drawOval(oval, p)
        val frac = (t.second + t.nano / 1_000_000_000f) / 60f
        val sweep = 360f * frac
        if (sweep > 0.5f) {
            stroke(WF_PURPLE, sw)
            c.drawArc(oval, 270f, sweep, false, p)
        }
        val rr = (s - 2f * inset) / 2f
        val ang = Math.toRadians((270f + sweep).toDouble())
        val hx = s / 2f + rr * cos(ang).toFloat()
        val hy = s / 2f + rr * sin(ang).toFloat()
        fill(Color.WHITE)
        c.drawCircle(hx, hy, sw * 0.9f, p)
    }

    // ---------------- ambient ----------------
    private fun drawAmbient(c: Canvas, s: Float, t: ZonedDateTime) {
        val nowMin = t.hour * 60 + t.minute
        val st = status(lessons.filter { it.occursOn(t.toLocalDate()) }, nowMin)
        txt(c, "%02d:%02d".format(t.hour, t.minute), s / 2f, s * 0.56f, s * 0.26f, 0xFFD0D0D0.toInt(), normalFace, Paint.Align.CENTER)
        txt(
            c, t.format(dateFmt).replaceFirstChar { it.uppercase() },
            s / 2f, s * 0.67f, s * 0.06f, 0xFF808080.toInt(), normalFace, Paint.Align.CENTER
        )
        val cur = st.current
        val nxt = st.next
        val line = when {
            cur != null -> "Сейчас: " + cur.title
            nxt != null -> nxt.title + " через " + dur(minsUntil(hm(nxt.start), nowMin, 0))
            else -> ""
        }
        if (line.isNotEmpty()) {
            txt(c, line, s / 2f, s * 0.76f, s * 0.045f, 0xFF707070.toInt(), normalFace, Paint.Align.CENTER, maxW = s * 0.78f)
        }
    }

    // ---------------- закреплённый файл ----------------
    private fun ensurePages(pf: PinnedFile, s: Float, aw: Float, ah: Float) {
        val key = pf.id + "|" + pf.text.hashCode() + "|" + s.toInt()
        if (key == pinKey) return
        pinKey = key
        pinPage = 0
        val lines = try {
            mxLayout(pf.text, s * 0.048f, aw, Color.WHITE)
        } catch (e: Throwable) {
            emptyList()
        }
        val pages = ArrayList<List<MxLine>>()
        var cur = ArrayList<MxLine>()
        var h = 0f
        for (l in lines) {
            if (cur.isEmpty() && l.w <= 0f) continue
            if (cur.isNotEmpty() && h + l.h > ah) {
                pages.add(cur)
                cur = ArrayList()
                h = 0f
            }
            cur.add(l)
            h += l.h
        }
        if (cur.isNotEmpty()) pages.add(cur)
        pinPages = pages
    }

    private fun drawPinned(c: Canvas, s: Float, t: ZonedDateTime, pf: PinnedFile) {
        drawRing(c, s, t)

        // кнопка «Открепить»
        val btn = RectF(s * 0.31f, s * 0.04f, s * 0.69f, s * 0.112f)
        fill(WF_PILL)
        c.drawRoundRect(btn, s * 0.036f, s * 0.036f, p)
        stroke(WF_PURPLE, s * 0.004f)
        c.drawRoundRect(btn, s * 0.036f, s * 0.036f, p)
        txt(c, "×  Открепить", s / 2f, s * 0.091f, s * 0.042f, WF_SOFT, boldFace, Paint.Align.CENTER)
        hits.add(Hit(RectF(s * 0.25f, 0f, s * 0.75f, s * 0.14f), "unpin"))

        // время
        txt(c, "%02d:%02d".format(t.hour, t.minute), s / 2f, s * 0.178f, s * 0.062f, WF_SOFT, boldFace, Paint.Align.CENTER)

        // содержимое файла
        val ax = s * 0.15f
        val ay = s * 0.205f
        val aw = s * 0.70f
        val ah = s * 0.635f
        ensurePages(pf, s, aw, ah)
        val pages = pinPages
        if (pages.isEmpty()) {
            txt(c, "Не удалось показать файл", s / 2f, s * 0.5f, s * 0.045f, WF_DIM, normalFace, Paint.Align.CENTER, maxW = aw)
            hits.add(Hit(RectF(0f, ay, s, s * 0.9f), "app"))
            return
        }
        if (pinPage > pages.size - 1) pinPage = pages.size - 1
        c.save()
        c.clipRect(ax - s * 0.02f, ay, ax + aw + s * 0.02f, ay + ah + s * 0.02f)
        var y = ay
        for (l in pages[pinPage]) {
            c.save()
            c.translate(ax, y)
            l.draw(c)
            c.restore()
            y += l.h
        }
        c.restore()

        if (pages.size > 1) {
            hits.add(Hit(RectF(0f, ay, s, ay + ah * 0.45f), "prev"))
            hits.add(Hit(RectF(0f, ay + ah * 0.45f, s, s * 0.90f), "next"))
            val n = minOf(pages.size, 7)
            val startX = s / 2f - (n - 1) * s * 0.015f
            for (k in 0 until n) {
                fill(if (k == pinPage) WF_PURPLE else WF_DOT)
                c.drawCircle(startX + k * s * 0.03f, s * 0.955f, if (k == pinPage) s * 0.012f else s * 0.009f, p)
            }
        } else {
            hits.add(Hit(RectF(0f, ay, s, s * 0.9f), "app"))
        }
    }

    // ---------------- интерактивный режим ----------------
    private fun drawInteractive(c: Canvas, s: Float, t: ZonedDateTime) {
        val nowMin = t.hour * 60 + t.minute
        val today = t.toLocalDate()
        val all = lessons.filter { it.occursOn(today) }
        val st = status(all, nowMin)

        // свечение справа сверху
        p.reset(); p.isAntiAlias = true
        p.shader = RadialGradient(s * 0.78f, s * 0.36f, s * 0.36f, 0x557C5CFF, 0x00000000, Shader.TileMode.CLAMP)
        c.drawCircle(s * 0.78f, s * 0.36f, s * 0.36f, p)

        drawRing(c, s, t)

        // иконка календаря и дата
        fill(WF_LILAC)
        c.drawRoundRect(RectF(s * 0.465f, s * 0.055f, s * 0.535f, s * 0.115f), s * 0.014f, s * 0.014f, p)
        fill(WF_PURPLE)
        c.drawRoundRect(RectF(s * 0.465f, s * 0.055f, s * 0.535f, s * 0.075f), s * 0.014f, s * 0.014f, p)
        txt(
            c, t.format(dateFmt).replaceFirstChar { it.uppercase() },
            s / 2f, s * 0.168f, s * 0.062f, WF_SOFT, boldFace, Paint.Align.CENTER
        )

        // время
        var ts = s * 0.20f
        val hs = "%02d".format(t.hour)
        val ms = "%02d".format(t.minute)
        var wh = measure(hs, ts, heavyFace)
        var wc = measure(":", ts, heavyFace)
        var wm = measure(ms, ts, heavyFace)
        val maxTotal = s * 0.50f
        if (wh + wc + wm > maxTotal) {
            val k = maxTotal / (wh + wc + wm)
            ts *= k; wh *= k; wc *= k; wm *= k
        }
        val x0 = s * 0.15f
        val ty = s * 0.335f
        txt(c, hs, x0, ty, ts, Color.WHITE, heavyFace)
        txt(c, ":", x0 + wh, ty, ts, WF_COLON, heavyFace)
        txt(c, ms, x0 + wh + wc, ty, ts, WF_PURPLE, heavyFace)

        drawIllustration(c, s)

        // батарея
        val bat = battery()
        if (bat >= 0) {
            stroke(WF_DIM, s * 0.004f)
            c.drawRoundRect(RectF(s * 0.685f, s * 0.188f, s * 0.725f, s * 0.214f), s * 0.006f, s * 0.006f, p)
            fill(WF_DIM)
            c.drawRect(RectF(s * 0.69f, s * 0.193f, s * 0.69f + s * 0.03f * (bat / 100f), s * 0.209f), p)
            txt(c, "$bat%", s * 0.84f, s * 0.214f, s * 0.04f, WF_DIM, normalFace, Paint.Align.RIGHT)
        }

        // плашка «Сегодня • N уроков»
        val pillTxt = "Сегодня • " + (if (all.isEmpty()) "занятий нет" else "${all.size} ${lw(all.size)}")
        val pw = measure(pillTxt, s * 0.045f, normalFace)
        val pl = s * 0.15f
        val pr = pl + s * 0.055f + pw + s * 0.035f
        val pillRect = RectF(pl, s * 0.36f, pr, s * 0.425f)
        fill(WF_PILL)
        c.drawRoundRect(pillRect, s * 0.0325f, s * 0.0325f, p)
        stroke(WF_RING, s * 0.003f)
        c.drawRoundRect(pillRect, s * 0.0325f, s * 0.0325f, p)
        fill(WF_PURPLE)
        c.drawCircle(pl + s * 0.03f, s * 0.3925f, s * 0.01f, p)
        txt(c, pillTxt, pl + s * 0.055f, s * 0.407f, s * 0.045f, WF_SOFT, normalFace)
        hits.add(Hit(pillRect, "app"))

        // что сейчас и что дальше
        drawStatus(c, s, st, nowMin, t.second, all.isEmpty())

        // стрелки: слева «Файлы», справа «Даты»
        drawArrow(c, s, s * 0.075f, s * 0.52f, -1)
        drawArrow(c, s, s * 0.925f, s * 0.52f, 1)
        hits.add(Hit(RectF(0f, s * 0.40f, s * 0.16f, s * 0.64f), "files"))
        hits.add(Hit(RectF(s * 0.84f, s * 0.40f, s, s * 0.64f), "dates"))

        // точки-индикаторы
        fill(WF_PURPLE)
        c.drawCircle(s * 0.47f, s * 0.955f, s * 0.012f, p)
        fill(WF_DOT)
        c.drawCircle(s * 0.50f, s * 0.955f, s * 0.010f, p)
        c.drawCircle(s * 0.53f, s * 0.955f, s * 0.010f, p)
    }

    private fun drawStatus(c: Canvas, s: Float, st: Status, nowMin: Int, sec: Int, noLessons: Boolean) {
        val cur = st.current
        val nxt = st.next
        val cardH = s * 0.145f
        val top1 = s * 0.478f
        val top2 = s * 0.678f
        when {
            cur != null -> {
                val left = dur(minsUntil(hm(cur.end), nowMin, sec))
                header(c, s, s * 0.468f, "СЕЙЧАС", WF_GREEN, "ещё $left")
                drawCard(c, s, cur, top1, cardH)
                if (nxt != null) {
                    val gap = dur(minsUntil(hm(nxt.start), nowMin, sec))
                    header(c, s, s * 0.668f, "СЛЕДУЮЩИЙ", WF_LILAC, "через $gap")
                    drawCard(c, s, nxt, top2, cardH)
                } else {
                    txt(c, "Дальше занятий нет", s / 2f, s * 0.77f, s * 0.048f, WF_DIM, normalFace, Paint.Align.CENTER, maxW = s * 0.7f)
                }
            }
            nxt != null -> {
                header(c, s, s * 0.468f, "СЛЕДУЮЩЕЕ", WF_LILAC, "")
                drawCard(c, s, nxt, top1, cardH)
                val gap = dur(minsUntil(hm(nxt.start), nowMin, sec))
                txt(c, "через $gap", s / 2f, s * 0.745f, s * 0.085f, Color.WHITE, boldFace, Paint.Align.CENTER, maxW = s * 0.7f)
                txt(
                    c, if (st.between) "идёт перерыв" else "занятия ещё не начались",
                    s / 2f, s * 0.805f, s * 0.04f, WF_DIM, normalFace, Paint.Align.CENTER
                )
            }
            else -> {
                txt(
                    c, if (noLessons) "Сегодня занятий нет" else "Занятия закончились",
                    s / 2f, s * 0.64f, s * 0.058f, Color.WHITE, boldFace, Paint.Align.CENTER, maxW = s * 0.7f
                )
            }
        }
    }

    private fun header(c: Canvas, s: Float, y: Float, label: String, color: Int, right: String) {
        val left = s * 0.16f
        val rightX = s * 0.84f
        val rw = if (right.isNotEmpty()) measure(right, s * 0.04f, boldFace) else 0f
        txt(c, label, left, y, s * 0.034f, color, boldFace, maxW = (rightX - left) - rw - s * 0.02f)
        if (right.isNotEmpty()) {
            txt(c, right, rightX, y, s * 0.04f, Color.WHITE, boldFace, Paint.Align.RIGHT)
        }
    }

    private fun drawCard(c: Canvas, s: Float, l: Lesson, top: Float, h: Float) {
        val cy = top + h / 2f
        val dy = abs(cy - s / 2f)
        val half = sqrt(maxOf(0f, (s / 2f) * (s / 2f) - dy * dy))
        val pad = s * 0.035f
        // карточки не заходят под кнопки-стрелки по бокам
        val left = maxOf(s / 2f - half + pad, s * 0.15f)
        val right = minOf(s / 2f + half - pad, s * 0.85f)
        val rect = RectF(left, top, right, top + h)
        val col = colorInt(l.color)

        fill(WF_CARD)
        c.drawRoundRect(rect, s * 0.05f, s * 0.05f, p)
        fill(col)
        c.drawRoundRect(RectF(left, top, left + s * 0.022f, top + h), s * 0.011f, s * 0.011f, p)

        val tx = left + s * 0.06f
        val iconSz = s * 0.095f
        val iconL = right - s * 0.04f - iconSz
        val maxW = iconL - tx - s * 0.02f
        txt(c, l.timeLabel(), tx, top + h * 0.30f, s * 0.042f, WF_DIM, normalFace, maxW = maxW)
        txt(c, l.title, tx, top + h * 0.62f, s * 0.056f, Color.WHITE, boldFace, maxW = maxW)
        val room = roomLabel(l.room)
        if (room.isNotBlank()) {
            stroke(WF_LILAC, s * 0.006f)
            c.drawCircle(tx + s * 0.012f, top + h * 0.86f - s * 0.012f, s * 0.011f, p)
            txt(c, room, tx + s * 0.035f, top + h * 0.90f, s * 0.038f, WF_DIM, normalFace, maxW = maxW - s * 0.035f)
        }

        val ir = RectF(iconL, cy - iconSz / 2f, iconL + iconSz, cy + iconSz / 2f)
        fill(withAlpha(col, 90))
        c.drawRoundRect(ir, s * 0.025f, s * 0.025f, p)
        val glyph = if (l.emoji.isNotBlank()) l.emoji else l.title.take(1).uppercase()
        txt(c, glyph, ir.centerX(), ir.centerY() + s * 0.02f, s * 0.055f, Color.WHITE, boldFace, Paint.Align.CENTER)

        hits.add(Hit(rect, "app"))
    }

    private fun drawArrow(c: Canvas, s: Float, cx: Float, cy: Float, dir: Int) {
        fill(WF_BTN)
        c.drawCircle(cx, cy, s * 0.043f, p)
        stroke(Color.WHITE, s * 0.009f)
        val path = Path()
        val d = dir.toFloat()
        path.moveTo(cx + d * s * 0.010f, cy - s * 0.020f)
        path.lineTo(cx - d * s * 0.010f, cy)
        path.lineTo(cx + d * s * 0.010f, cy + s * 0.020f)
        c.drawPath(path, p)
    }

    private fun drawIllustration(c: Canvas, s: Float) {
        // календарь
        fill(0xFFD8D0FF.toInt())
        c.drawRoundRect(RectF(s * 0.66f, s * 0.25f, s * 0.87f, s * 0.41f), s * 0.025f, s * 0.025f, p)
        fill(WF_PURPLE)
        c.drawRoundRect(RectF(s * 0.66f, s * 0.25f, s * 0.87f, s * 0.285f), s * 0.025f, s * 0.025f, p)
        fill(0xFFB8B0F0.toInt())
        c.drawRoundRect(RectF(s * 0.70f, s * 0.225f, s * 0.715f, s * 0.265f), s * 0.007f, s * 0.007f, p)
        c.drawRoundRect(RectF(s * 0.815f, s * 0.225f, s * 0.83f, s * 0.265f), s * 0.007f, s * 0.007f, p)
        fill(WF_PURPLE)
        for (row in 0..1) {
            for (col in 0..2) {
                val x = s * (0.685f + col * 0.047f)
                val y = s * (0.30f + row * 0.04f)
                c.drawRoundRect(RectF(x, y, x + s * 0.035f, y + s * 0.03f), s * 0.006f, s * 0.006f, p)
            }
        }
        // часы
        fill(0xFF1E1B33.toInt())
        c.drawCircle(s * 0.85f, s * 0.405f, s * 0.045f, p)
        stroke(Color.WHITE, s * 0.006f)
        c.drawCircle(s * 0.85f, s * 0.405f, s * 0.045f, p)
        val hands = Path()
        hands.moveTo(s * 0.85f, s * 0.38f)
        hands.lineTo(s * 0.85f, s * 0.405f)
        hands.lineTo(s * 0.868f, s * 0.415f)
        c.drawPath(hands, p)
    }
}
KT_EOF

# =====================================================================
#  Подстановка пакета
# =====================================================================
sed -i "s/PKG__/${APKG}/g" "$ADIR/MathEngine.kt" "$EXTRAS"
sed -i "s/PKG__/${WPKG}/g" "$WDIR/MathEngine.kt" "$WDIR/WearPin.kt" "$WF"

# =====================================================================
#  Проверка
# =====================================================================
chk() { grep -q "$1" "$2" || echo "!! $3"; }
chk 'fun mxLayout'            "$ADIR/MathEngine.kt"  'телефон: нет mxLayout'
chk 'fun mxLayout'            "$WDIR/MathEngine.kt"  'часы: нет mxLayout'
chk 'mxLayout(f.text'         "$WOS"                 'часы: FileViewer не переведён на mxLayout (нет строки layoutFormula(f.text...)'
chk 'MxFormulaLine(line'      "$WOS"                 'часы: FileViewer не переведён на MxFormulaLine'
chk 'PinButton(f)'            "$WOS"                 'часы: в списке файлов не добавлена кнопка закрепления (нет строки Text(f.time, ...))'
chk 'fun MyFilesHost'         "$EXTRAS"              'телефон: нет MyFilesHost'
chk 'fun drawPinned'          "$WF"                  'часы: не записан циферблат'
chk 'fun initialOverlay'      "$WF"                  'часы: нет initialOverlay'
if grep -q 'layoutFormula(f' "$WOS"; then echo '!! часы: остался вызов layoutFormula'; fi

echo
echo 'Готово.'
echo '1) git add . && git commit -m "Math engine (cases), pin file to watch face, seconds ring, view/edit files" && git push'
echo '2) После сборки поставь app-release.apk на телефон и wear-release.apk на часы (поверх).'
echo '3) На часах: Файлы -> кнопка с иконкой часов справа от файла -> файл откроется на циферблате.'
echo '   Нажатие в верхней/нижней части текста листает страницы, "× Открепить" сверху возвращает обычный циферблат.'
echo '   Для этого должен быть выбран циферблат "Расписание" (долгое нажатие на циферблат).'
echo '4) На телефоне: Меню -> Мои файлы -> нажать на файл -> "Смотреть" (с формулами) или "Редактировать".'
echo "Резервные копии: $BAK"
