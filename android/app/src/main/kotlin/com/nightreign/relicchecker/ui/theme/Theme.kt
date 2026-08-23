package com.nightreign.relicchecker.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

@Immutable
object NightColors {
    val BackgroundDeep = Color(0xFF07060C)
    val Background = Color(0xFF09080F)
    val Elevated = Color(0xFF12101B)
    val Card = Color(0xFF15121F)
    val CardHover = Color(0xFF1A1627)
    val Field = Color(0xFF0F0D17)
    val FieldSoft = Color(0xFF191522)
    val Border = Color(0xFF2B2639)
    val BorderStrong = Color(0xFF3A3450)
    val TextPrimary = Color(0xFFF4F1FB)
    val TextSecondary = Color(0xFFAAA3B8)
    val TextMuted = Color(0xFF736D80)
    val PurpleDeep = Color(0xFF7145D8)
    val Purple = Color(0xFF8459E8)
    val PurpleSoft = Color(0xFFB79AFF)
    val Green = Color(0xFF55D6A5)
    val Amber = Color(0xFFEEC16D)
    val Red = Color(0xFFED6C7D)
}

private val NightScheme = darkColorScheme(
    primary = NightColors.Purple,
    onPrimary = NightColors.TextPrimary,
    primaryContainer = Color(0xFF271D46),
    onPrimaryContainer = NightColors.PurpleSoft,
    secondary = NightColors.PurpleSoft,
    onSecondary = NightColors.BackgroundDeep,
    secondaryContainer = NightColors.FieldSoft,
    onSecondaryContainer = NightColors.TextPrimary,
    tertiary = NightColors.Green,
    onTertiary = NightColors.BackgroundDeep,
    tertiaryContainer = Color(0xFF10281F),
    onTertiaryContainer = NightColors.Green,
    error = NightColors.Red,
    onError = NightColors.BackgroundDeep,
    errorContainer = Color(0xFF32151D),
    onErrorContainer = NightColors.Red,
    background = NightColors.Background,
    onBackground = NightColors.TextPrimary,
    surface = NightColors.Background,
    onSurface = NightColors.TextPrimary,
    surfaceVariant = NightColors.Card,
    onSurfaceVariant = NightColors.TextSecondary,
    outline = NightColors.Border,
    outlineVariant = NightColors.BorderStrong,
    scrim = NightColors.BackgroundDeep,
)

private val NightTypography = Typography(
    headlineSmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 20.sp,
        lineHeight = 26.sp,
    ),
    titleLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 18.sp,
        lineHeight = 24.sp,
    ),
    titleMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 16.sp,
        lineHeight = 22.sp,
    ),
    bodyLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        lineHeight = 20.sp,
        letterSpacing = 0.15.sp,
    ),
    bodyMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 13.sp,
        lineHeight = 18.sp,
        letterSpacing = 0.1.sp,
    ),
    bodySmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.2.sp,
    ),
    labelLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Medium,
        fontSize = 13.sp,
        lineHeight = 18.sp,
        letterSpacing = 0.4.sp,
    ),
    labelMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Medium,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.2.sp,
    ),
    labelSmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Medium,
        fontSize = 11.sp,
        lineHeight = 14.sp,
        letterSpacing = 0.6.sp,
    ),
)

@Composable
fun NightreignTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = NightScheme,
        typography = NightTypography,
        content = content,
    )
}
