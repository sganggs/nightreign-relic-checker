package com.nightreign.relicchecker.ui.save

import android.app.Activity
import android.content.ClipData
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.FileProvider
import com.nightreign.relicchecker.gamedata.save.AuditedSave
import com.nightreign.relicchecker.gamedata.save.SaveAuditData
import com.nightreign.relicchecker.gamedata.save.SaveAuditPipeline
import com.nightreign.relicchecker.gamedata.save.SaveComparator
import com.nightreign.relicchecker.gamedata.save.SaveCompareDirection
import com.nightreign.relicchecker.gamedata.save.SaveCompareResult
import com.nightreign.relicchecker.gamedata.save.SaveFileException
import com.nightreign.relicchecker.gamedata.save.SaveFileInput
import com.nightreign.relicchecker.gamedata.save.SaveFileParser
import com.nightreign.relicchecker.gamedata.save.SaveFilter
import com.nightreign.relicchecker.gamedata.save.SaveReportBuilder
import com.nightreign.relicchecker.gamedata.save.SaveReportCatalogInfo
import com.nightreign.relicchecker.gamedata.save.SaveReportFormat
import java.io.File
import java.io.FileNotFoundException
import java.time.LocalDateTime
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** 存档检查页的两个视图：本存档的逐件检查 / 与另一份存档的对比。 */
internal enum class SaveView(val title: String) { CHECK("遗物检查"), COMPARE("存档对比") }

/** 等待系统「新建文档」回调时记下的导出请求（生成时间在点按时就定下，与建议文件名一致）。 */
internal class PendingExport(val format: SaveReportFormat, val generatedAt: LocalDateTime)

/**
 * 存档检查页的会话状态（进程级，与 GameDataRepository 同一思路）。
 *
 * 已审计的存档体积大、不能放进 Bundle，所以不走 rememberSaveable：放在这里，切底栏、返回枢纽、
 * 旋转屏幕都不丢；读取与解析在进程级作用域的 IO 线程上跑，页面中途离开也照样完成。
 * 与这份存档绑定的页内状态（所选角色、过滤、搜索、对比筛选）也放在这里，换一份存档时一起重置。
 * 进程被系统回收后需要重新选择存档（SAF 的临时读权限本来也随之失效）。
 */
internal object SaveSession {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var loadJob: Job? = null
    private var compareJob: Job? = null
    private var exportJob: Job? = null

    /** 当前载入并审计好的存档。 */
    var save by mutableStateOf<AuditedSave?>(null)
        private set
    var loading by mutableStateOf(false)
        private set

    /** 载入失败的提示（红字）。 */
    var saveMessage by mutableStateOf("")
        private set

    var compare by mutableStateOf<SaveCompareResult?>(null)
        private set
    var comparing by mutableStateOf(false)
        private set
    var compareMessage by mutableStateOf("")
        private set

    /** 导出 / 分享结果；second 为 true 时是错误。 */
    var exportMessage by mutableStateOf<Pair<String, Boolean>?>(null)
        private set
    var exporting by mutableStateOf(false)
        private set
    var pendingExport: PendingExport? = null

    // ---- 与当前存档绑定的页内状态 ----
    var selectedSlot by mutableStateOf<Int?>(null)
    var filter by mutableStateOf(SaveFilter.ALL)
    var query by mutableStateOf("")
    var view by mutableStateOf(SaveView.CHECK)
    var compareDirection by mutableStateOf(SaveCompareDirection.ALL)
    var compareQuery by mutableStateOf("")

    /** 选择存档：读取、解析、审计都在 IO 线程；换存档时清掉上一次的对比与提示。 */
    fun open(resolver: ContentResolver, uri: Uri, data: SaveAuditData) {
        loadJob?.cancel()
        compareJob?.cancel()
        loading = true
        comparing = false
        saveMessage = ""
        compareMessage = ""
        exportMessage = null
        compare = null
        view = SaveView.CHECK
        loadJob = scope.launch {
            try {
                val audited = withContext(Dispatchers.IO) { readAndAudit(resolver, uri, data) }
                save = audited
                selectedSlot = audited.characters.firstOrNull()?.slot
                filter = SaveFilter.ALL
                query = ""
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                // 与桌面端一致：载入失败时清掉上一份，避免把旧结果当成新文件的结论
                save = null
                selectedSlot = null
                saveMessage = "解析失败：" + describe(error)
            } finally {
                loading = false
            }
        }
    }

    /** 选择另一份存档做对比（以当前存档为准：多出的记为新增，少掉的记为减少）。 */
    fun openCompare(resolver: ContentResolver, uri: Uri, data: SaveAuditData) {
        val base = save ?: return
        compareJob?.cancel()
        comparing = true
        compareMessage = ""
        compareJob = scope.launch {
            try {
                val result = withContext(Dispatchers.IO) {
                    SaveComparator.compare(base, readAndAudit(resolver, uri, data))
                }
                compare = result
                compareDirection = SaveCompareDirection.ALL
                compareQuery = ""
                view = SaveView.COMPARE
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                compare = null
                compareMessage = "对比失败：" + describe(error)
            } finally {
                comparing = false
            }
        }
    }

    fun closeCompare() {
        compareJob?.cancel()
        comparing = false
        compare = null
        compareMessage = ""
        view = SaveView.CHECK
    }

    fun reportLaunchFailure(message: String) {
        saveMessage = message
    }

    fun reportExportFailure(message: String) {
        exportMessage = message to true
    }

    /** 把报告写进系统「新建文档」返回的位置。 */
    fun writeExport(context: Context, uri: Uri, catalogInfo: SaveReportCatalogInfo) {
        val current = save
        val request = pendingExport
        pendingExport = null
        if (current == null || request == null) {
            // 选位置期间进程被系统回收：存档已不在内存里，新建的文档保持为空，明确告诉用户
            exportMessage = "导出失败：存档已失效，请重新选择存档后再导出" to true
            return
        }
        exportJob?.cancel()
        exporting = true
        val resolver = context.applicationContext.contentResolver
        exportJob = scope.launch {
            try {
                val name = withContext(Dispatchers.IO) {
                    val content = SaveReportBuilder.content(current, request.format, request.generatedAt, catalogInfo)
                    val bytes = SaveReportBuilder.fileBytes(request.format, content)
                    openForWrite(resolver, uri).use { it.write(bytes) }
                    displayName(resolver, uri) ?: SaveReportBuilder.suggestedFileName(current, request.format, request.generatedAt)
                }
                exportMessage = "已导出：$name" to false
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                exportMessage = "导出失败：" + describe(error) to true
            } finally {
                exporting = false
            }
        }
    }

    /** 生成报告写进 cacheDir，再经 FileProvider 交给系统分享面板。 */
    fun share(context: Context, format: SaveReportFormat, catalogInfo: SaveReportCatalogInfo) {
        val current = save ?: return
        exportJob?.cancel()
        exporting = true
        val appContext = context.applicationContext
        exportJob = scope.launch {
            try {
                val now = LocalDateTime.now()
                val fileName = SaveReportBuilder.suggestedFileName(current, format, now)
                val uri = withContext(Dispatchers.IO) {
                    val directory = File(appContext.cacheDir, SHARE_DIRECTORY).apply { mkdirs() }
                    // 只留这一份：上次分享的报告没有必要继续占空间
                    directory.listFiles()?.forEach { it.delete() }
                    val file = File(directory, fileName)
                    val content = SaveReportBuilder.content(current, format, now, catalogInfo)
                    file.writeBytes(SaveReportBuilder.fileBytes(format, content))
                    FileProvider.getUriForFile(appContext, appContext.packageName + AUTHORITY_SUFFIX, file)
                }
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = format.mimeType
                    putExtra(Intent.EXTRA_STREAM, uri)
                    putExtra(Intent.EXTRA_SUBJECT, fileName)
                    clipData = ClipData.newRawUri(fileName, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                val chooser = Intent.createChooser(send, "分享存档检查报告")
                if (context !is Activity) chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(chooser)
                exportMessage = null
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                exportMessage = "分享失败：" + describe(error) to true
            } finally {
                exporting = false
            }
        }
    }

    private fun readAndAudit(resolver: ContentResolver, uri: Uri, data: SaveAuditData): AuditedSave {
        val (declaredName, declaredSize) = queryMeta(resolver, uri)
        SaveFileInput.checkDeclaredSize(declaredSize)
        val bytes = try {
            resolver.openInputStream(uri)?.use { SaveFileInput.readLimited(it) }
        } catch (error: SaveFileException) {
            throw error
        } catch (error: SecurityException) {
            throw SaveFileException("没有读取所选文件的权限")
        } catch (error: FileNotFoundException) {
            throw SaveFileException("无法打开所选文件")
        } ?: throw SaveFileException("无法打开所选文件")
        val parsed = SaveFileParser.parse(bytes, SaveFileInput.displayFileName(declaredName ?: uri.lastPathSegment))
        return SaveAuditPipeline.audit(parsed, data)
    }

    private fun queryMeta(resolver: ContentResolver, uri: Uri): Pair<String?, Long?> = runCatching {
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return@use null to null
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
            val name = if (nameIndex >= 0 && !cursor.isNull(nameIndex)) cursor.getString(nameIndex) else null
            val size = if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) cursor.getLong(sizeIndex) else null
            name to size
        }
    }.getOrNull() ?: (null to null)

    private fun displayName(resolver: ContentResolver, uri: Uri): String? = queryMeta(resolver, uri).first

    /** 新建的文档本来是空的；"wt" 不被支持时退回 "w"。 */
    private fun openForWrite(resolver: ContentResolver, uri: Uri) =
        runCatching { resolver.openOutputStream(uri, "wt") }.getOrNull()
            ?: resolver.openOutputStream(uri, "w")
            ?: throw SaveFileException("无法写入所选位置")

    private fun describe(error: Throwable): String = when (error) {
        is SaveFileException -> error.message.orEmpty()
        is OutOfMemoryError -> "内存不足，无法读取这份文件"
        else -> error.message?.takeIf { it.isNotBlank() } ?: error::class.java.simpleName
    }

    /** cacheDir 下的分享目录；与 res/xml/file_paths.xml 一致。 */
    private const val SHARE_DIRECTORY = "save-reports"

    /** FileProvider 的 authority 后缀；与 AndroidManifest.xml 一致。 */
    const val AUTHORITY_SUFFIX = ".savereport"
}
