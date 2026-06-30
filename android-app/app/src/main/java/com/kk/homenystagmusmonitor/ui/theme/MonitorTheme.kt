package com.kk.homenystagmusmonitor.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

private val MonitorColorScheme = lightColorScheme(
    primary = Color(0xFF1E5FAE),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFD7E7FF),
    onPrimaryContainer = Color(0xFF001C3A),
    secondary = Color(0xFF3A6D8C),
    onSecondary = Color(0xFFFFFFFF),
    secondaryContainer = Color(0xFFD0E9FA),
    onSecondaryContainer = Color(0xFF001E2D),
    tertiary = Color(0xFF00696D),
    onTertiary = Color(0xFFFFFFFF),
    surface = Color(0xFFF6F9FE),
    onSurface = Color(0xFF161C24),
    surfaceContainerLow = Color(0xFFFFFFFF),
    surfaceContainerHighest = Color(0xFFE8EEF7),
    outline = Color(0xFF728093)
)

private val MonitorShapes = Shapes(
    small = androidx.compose.foundation.shape.RoundedCornerShape(10.dp),
    medium = androidx.compose.foundation.shape.RoundedCornerShape(16.dp),
    large = androidx.compose.foundation.shape.RoundedCornerShape(22.dp)
)

@Composable
fun MonitorTheme(
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = MonitorColorScheme,
        typography = Typography(),
        shapes = MonitorShapes,
        content = content
    )
}
