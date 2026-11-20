package com.example.schedule

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector

object Pal {
    val Bg = Color(0xFF14131C)
    val Card = Color(0xFF1F1E2B)
    val Purple = Color(0xFF7C5CFF)
    val Lilac = Color(0xFFA78BFA)
    val Blue = Color(0xFF4D8DFF)
    val Green = Color(0xFF4CC36B)
    val Yellow = Color(0xFFF2B72E)
    val Text = Color(0xFFF2F0FA)
    val Dim = Color(0xFF9B98AD)
}

val ICON_KEYS = listOf("math", "physics", "it", "history", "lit", "bio", "chem", "other")

fun iconFor(k: String): ImageVector = when (k) {
    "math" -> Icons.Filled.Functions
    "physics" -> Icons.Filled.Bolt
    "it" -> Icons.Filled.Computer
    "history" -> Icons.Filled.AccountBalance
    "lit" -> Icons.Filled.MenuBook
    "bio" -> Icons.Filled.Eco
    "chem" -> Icons.Filled.Science
    else -> Icons.Filled.MoreHoriz
}

fun colorFor(k: String): Color = when (k) {
    "math" -> Pal.Purple
    "physics" -> Pal.Blue
    "it" -> Pal.Green
    "history" -> Pal.Yellow
    "lit" -> Pal.Yellow
    "bio" -> Pal.Green
    "chem" -> Pal.Blue
    else -> Pal.Dim
}
