package com.wimg.app.ui.screens

// Old category bottom sheet, kept only for SearchScreen until search is
// redesigned (phase 5). Umsätze uses CategoryPanel instead. Delete afterwards.

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wimg.app.bridge.LibWimg
import com.wimg.app.models.Transaction
import com.wimg.app.models.WimgCategory
import com.wimg.app.ui.components.formatAmountShort
import com.wimg.app.ui.theme.WimgColors
import com.wimg.app.ui.theme.WimgShapes
import com.wimg.app.ui.theme.wimgCard
import kotlin.math.abs
import com.wimg.app.i18n.L

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CategoryEditorSheet(transaction: Transaction, onDismiss: () -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)

    val categories = listOf(
        WimgCategory.GROCERIES, WimgCategory.DINING, WimgCategory.TRANSPORT,
        WimgCategory.HOUSING, WimgCategory.UTILITIES, WimgCategory.ENTERTAINMENT,
        WimgCategory.SHOPPING, WimgCategory.HEALTH, WimgCategory.INSURANCE,
        WimgCategory.SUBSCRIPTIONS, WimgCategory.TRAVEL, WimgCategory.EDUCATION,
        WimgCategory.CASH, WimgCategory.TRANSFER, WimgCategory.OTHER,
    )

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surface,
    ) {
        Column(
            modifier = Modifier
                .fillMaxHeight(0.85f)
                .padding(horizontal = 16.dp, vertical = 8.dp)
                .verticalScroll(rememberScrollState()),
        ) {
            Text(
                transaction.description,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(bottom = 4.dp),
            )
            Text(
                formatAmountShort(transaction.amount),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Black,
                color = if (transaction.isIncome) WimgCategory.INCOME.color else MaterialTheme.colorScheme.onSurface,
            )
            Spacer(Modifier.height(16.dp))

            if (transaction.isIncome) {
                CategoryOption(WimgCategory.INCOME, transaction.category == WimgCategory.INCOME.id) {
                    LibWimg.setCategory(transaction.id, WimgCategory.INCOME.id)
                    onDismiss()
                }
            }
            categories.forEach { cat ->
                CategoryOption(cat, transaction.category == cat.id) {
                    LibWimg.setCategory(transaction.id, cat.id)
                    onDismiss()
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
internal fun CategoryOption(category: WimgCategory, selected: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(category.color.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                category.icon,
                contentDescription = null,
                tint = category.color,
                modifier = Modifier.size(16.dp),
            )
        }
        Spacer(Modifier.width(12.dp))
        Text(
            category.label,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.weight(1f),
        )
        if (selected) {
            Text("✓", fontWeight = FontWeight.Bold)
        }
    }
}
