package com.nightreign.relicchecker.ui.gamedata

import android.content.res.AssetManager
import android.os.SystemClock
import android.util.Log
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.nightreign.relicchecker.gamedata.GameDataFormatException
import com.nightreign.relicchecker.gamedata.GameDataHeader
import com.nightreign.relicchecker.gamedata.GameDataKey
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async

/** 某个数据集在页面上的加载状态。 */
@Stable
sealed interface GameDataState<out T> {
    data object Loading : GameDataState<Nothing>
    data class Ready<out T>(val value: T) : GameDataState<T>
    data class Failed(val error: Throwable) : GameDataState<Nothing>
}

/** Ready 时变换值，Loading / Failed 原样透传。 */
inline fun <T, R> GameDataState<T>.map(transform: (T) -> R): GameDataState<R> = when (this) {
    GameDataState.Loading -> GameDataState.Loading
    is GameDataState.Failed -> this
    is GameDataState.Ready -> GameDataState.Ready(transform(value))
}

/**
 * 合并两个数据集的状态（例如词条反查要同时用遗物物品表与另一份解析结果）：
 * 任一失败即失败，任一仍在加载即加载中，两者都就绪才就绪。
 */
fun <A, B> GameDataState<A>.zip(other: GameDataState<B>): GameDataState<Pair<A, B>> = when {
    this is GameDataState.Failed -> this
    other is GameDataState.Failed -> other
    this is GameDataState.Ready && other is GameDataState.Ready -> GameDataState.Ready(value to other.value)
    else -> GameDataState.Loading
}

/** 读取或解析某个数据集失败；消息里带文件名，页面原样展示。 */
class GameDataLoadException(val key: GameDataKey, cause: Throwable) : RuntimeException(
    when (cause) {
        // GameDataJson 抛出的格式错误已经写明文件名
        is GameDataFormatException -> cause.message
        else -> "读取 ${key.fileName} 失败：${cause.message ?: cause::class.java.simpleName}"
    },
    cause,
)

/**
 * 数据集的进程级缓存（与 NightreignApp 里的 CatalogCache 同一思路：解析一次，旋转、切底栏、
 * 离开再进入页面都不重读）。
 *
 * - 缓存键是 `GameDataKey + parserId`：同一个文件可以被不同页面按不同 DTO 各解析一份；
 * - 原始 JSON 文本不缓存，只缓存解析结果（buffs 约 3 MB，文本常驻不划算）；
 * - 解析在进程级作用域的 [Dispatchers.IO] 上进行：页面在解析中途离开组合，结果也会落进缓存，
 *   同一键的并发请求共享同一次解析；
 * - 失败也缓存（asset 缺失或格式错误是确定性的，重试没有意义），页面显示失败原因。
 */
internal object GameDataRepository {
    private const val LOG_TAG = "GameData"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val completed = ConcurrentHashMap<String, Result<Any>>()
    private val inFlight = ConcurrentHashMap<String, Deferred<Result<Any>>>()

    fun cacheId(key: GameDataKey, parserId: String): String = "${key.name}#$parserId"

    /** 已解析完成的结果；未请求或仍在解析时为 null。 */
    fun cached(key: GameDataKey, parserId: String): Result<Any>? = completed[cacheId(key, parserId)]

    /** 请求解析（已在进行或已完成则复用），返回可等待的结果。 */
    fun <T : Any> load(
        assets: AssetManager,
        key: GameDataKey,
        parserId: String,
        parse: (String) -> T,
    ): Deferred<Result<Any>> {
        val id = cacheId(key, parserId)
        return inFlight.computeIfAbsent(id) {
            scope.async {
                val started = SystemClock.elapsedRealtime()
                val result: Result<Any> = runCatching {
                    val text = assets.open(key.fileName).bufferedReader(Charsets.UTF_8).use { it.readText() }
                    parse(text)
                }.recoverCatching { error -> throw GameDataLoadException(key, error) }
                // 解析耗时：adb logcat -s GameData 查看，调 DTO 时用来对比
                Log.i(LOG_TAG, "$id ${if (result.isSuccess) "ok" else "failed"} in ${SystemClock.elapsedRealtime() - started} ms")
                completed[id] = result
                result
            }
        }
    }

    /** 非 Composable 场景（例如一次性合并多个数据集）用的挂起版本。 */
    suspend fun <T : Any> get(
        assets: AssetManager,
        key: GameDataKey,
        parserId: String,
        parse: (String) -> T,
    ): Result<T> {
        @Suppress("UNCHECKED_CAST")
        return load(assets, key, parserId, parse).await() as Result<T>
    }
}

/**
 * 在 Composable 里按需加载一个数据集。
 *
 * [parserId] 在全应用内必须唯一，并且与 [parse] 的返回类型一一对应（缓存按它取回结果后直接转型），
 * 约定写成 `"<页面>.<用途>.v<版本>"`，例如 `"bosses.page.v1"`；DTO 结构变了就把版本号加一。
 * [parse] 在后台线程执行，只应做纯解析（例如 `GameDataJson.decode` + 版本校验 + 建索引），不要碰 UI 状态。
 * 已经解析过的数据会同步返回 [GameDataState.Ready]，再次进入页面不会闪加载态。
 */
@Composable
fun <T : Any> rememberGameData(
    key: GameDataKey,
    parserId: String,
    parse: (String) -> T,
): GameDataState<T> {
    val assets = LocalContext.current.applicationContext.assets
    val latestParse by rememberUpdatedState(parse)
    var state by remember(key, parserId) {
        mutableStateOf(GameDataRepository.cached(key, parserId).toState<T>())
    }
    LaunchedEffect(key, parserId) {
        if (state is GameDataState.Loading) {
            val result = GameDataRepository.load(assets, key, parserId) { text -> latestParse(text) }.await()
            state = result.toState()
        }
    }
    return state
}

/** 只读某个数据集的顶层元数据（版本、游戏版本、数据版本），所有页面共用一份缓存。 */
@Composable
fun rememberGameDataHeader(key: GameDataKey): GameDataState<GameDataHeader> =
    rememberGameData(key, GameDataHeader.PARSER_ID) { text -> GameDataHeader.parse(key, text) }

@Suppress("UNCHECKED_CAST")
private fun <T> Result<Any>?.toState(): GameDataState<T> = when {
    this == null -> GameDataState.Loading
    isSuccess -> GameDataState.Ready(getOrThrow() as T)
    else -> GameDataState.Failed(exceptionOrNull()!!)
}
