package com.nightreign.relicchecker.ui.bosses

import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.layout
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * 首领数据页顶部工具条的排法，按整页（外壳顶栏以上到底栏以上的那一块）的可用高度 / 宽度选。
 *
 * 各块高度（dp）：外壳顶栏 14 + 52 + 12 = 78，带状态小标签时再加 10 + 24 = 112；
 * 完整工具条 = 搜索 46 + 设置行 48 + 分组药丸 48 + 状态行与说明各 16 起（深夜 / 打开隐藏实体时会折成两行）
 * + 间距与分隔线 ≈ 191–225；只吸顶搜索与设置 ≈ 101；二者并成一行 ≈ 53。
 *
 * - [FULL]：竖屏手机、平板。全部吸顶（原排法）。页面高 ≥ 600 时列表至少还剩约 260。
 * - [COMPACT_TWO_ROWS]：矮而窄（分屏、小屏手机）。只把搜索框与设置行吸顶；外壳不放状态小标签，
 *   状态小标签、分组药丸、状态行与说明挪进列表第 0 项，随列表滚走（分组小标题照常吸顶）。
 * - [COMPACT_ONE_ROW]：矮而宽（横屏手机）。搜索框与设置行并成一行吸顶，其余同上。
 *   以 Medium Phone 横屏为例：页面 ≈ 411 − 状态栏 24 − 底栏 64 − 手势条 24 = 299，
 *   顶栏 78 + 吸顶 53 之后列表还有约 168；原排法（112 + 191 起）只剩 0–5，卡片与底部说明都够不着。
 *
 * 系统键盘：edge-to-edge 下（Android 11 起）窗口不随键盘缩小，排法只随旋转 / 分屏 / 窗口大小变化，
 * 打字时不跳版；更老的系统若随键盘缩小窗口，会临时换成紧凑排法，列表同样留得出高度。
 */
internal enum class BossToolbarLayout {
    FULL,
    COMPACT_TWO_ROWS,
    COMPACT_ONE_ROW,
    ;

    /** 紧凑排法：分组药丸与状态行在列表第 0 项里，外壳不放状态小标签。 */
    val compact: Boolean get() = this != FULL

    companion object {
        /** 页面高度低于它就改用紧凑排法。 */
        val CompactBelowHeight: Dp = 600.dp

        /** 紧凑排法下页面至少这么宽，才把搜索框与设置行并成一行（搜索框约占 2/5，设置行可横滑）。 */
        val OneRowMinWidth: Dp = 560.dp

        fun of(pageHeight: Dp, pageWidth: Dp): BossToolbarLayout = when {
            pageHeight >= CompactBelowHeight -> FULL
            pageWidth >= OneRowMinWidth -> COMPACT_ONE_ROW
            else -> COMPACT_TWO_ROWS
        }
    }
}

/**
 * 让列表条目左右各伸出 [amount]，抵掉 LazyColumn 的左右 contentPadding：
 * 横滑的药丸行贴着屏幕边缘滚动（与吸顶工具条里的同一行一致），条目内部再自己留 [amount] 的白。
 * LazyColumn 只按自身边界裁剪，伸进留白区的部分照常显示、照常响应点击。
 */
internal fun Modifier.bleedHorizontally(amount: Dp): Modifier = layout { measurable, constraints ->
    val extra = amount.roundToPx() * 2
    val placeable = measurable.measure(
        constraints.copy(
            minWidth = constraints.minWidth + extra,
            maxWidth = if (constraints.hasBoundedWidth) constraints.maxWidth + extra else Constraints.Infinity,
        ),
    )
    val width = (placeable.width - extra).coerceIn(constraints.minWidth, constraints.maxWidth)
    layout(width, placeable.height) { placeable.place(-extra / 2, 0) }
}
