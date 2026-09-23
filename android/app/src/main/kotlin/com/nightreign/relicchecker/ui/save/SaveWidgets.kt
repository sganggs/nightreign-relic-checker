package com.nightreign.relicchecker.ui.save

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.ui.NightPanel
import com.nightreign.relicchecker.ui.theme.NightColors

// 存档检查页自用的小组件（骨架 Components.kt 不改，这里写私有版本）。

@Composable
internal fun SavePrimaryButton(label: String, enabled: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.fillMaxWidth().height(50.dp),
        shape = RoundedCornerShape(13.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = NightColors.Purple,
            contentColor = NightColors.TextPrimary,
            disabledContainerColor = NightColors.FieldSoft,
            disabledContentColor = NightColors.TextMuted,
        ),
    ) { Text(label, fontWeight = FontWeight.SemiBold) }
}

@Composable
internal fun SaveSecondaryButton(
    label: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    accent: Color = NightColors.TextSecondary,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(11.dp)
    Box(
        modifier = modifier
            .heightIn(min = 48.dp)
            .clip(shape)
            .background(if (enabled) NightColors.FieldSoft else NightColors.Field)
            .border(1.dp, NightColors.Border, shape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label,
            style = MaterialTheme.typography.labelLarge,
            color = if (enabled) accent else NightColors.TextMuted,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
internal fun SaveProgressRow(label: String, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier.fillMaxWidth().padding(vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CircularProgressIndicator(modifier = Modifier.size(18.dp), color = NightColors.PurpleSoft, strokeWidth = 2.dp)
        Text(label, style = MaterialTheme.typography.bodySmall, color = NightColors.TextSecondary)
    }
}

@Composable
internal fun SaveEmptyState(title: String, detail: String, modifier: Modifier = Modifier, accent: Color = NightColors.Border) {
    NightPanel(modifier = modifier.fillMaxWidth(), borderColor = accent) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 22.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium, color = NightColors.TextPrimary, textAlign = TextAlign.Center)
            Text(detail, style = MaterialTheme.typography.bodySmall, color = NightColors.TextSecondary, textAlign = TextAlign.Center)
        }
    }
}

/** 一行带色边的提示条（校验和异常、全部合法之类）。 */
@Composable
internal fun SaveBanner(text: String, color: Color, modifier: Modifier = Modifier, leading: String? = null) {
    val shape = RoundedCornerShape(11.dp)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(color.copy(alpha = .08f))
            .border(1.dp, color.copy(alpha = .32f), shape)
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(9.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        leading?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = color, fontWeight = FontWeight.Bold) }
        Text(text, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = NightColors.TextPrimary)
    }
}
