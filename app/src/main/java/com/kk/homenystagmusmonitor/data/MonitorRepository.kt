package com.kk.homenystagmusmonitor.data

import android.content.Context
import android.content.SharedPreferences
import com.kk.homenystagmusmonitor.analysis.NystagmusDetectionResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.io.File
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL

data class PatientAccount(
    val id: String,
    val name: String
)

data class NystagmusRecord(
    val id: String,
    val accountId: String,
    val accountName: String,
    val startedAt: String,
    val durationSec: Int,
    val analysisCompleted: Boolean,
    val suspectNystagmus: Boolean,
    val summary: String,
    val horizontalDirectionLabel: String,
    val verticalDirectionLabel: String,
    val dominantFrequencyHz: Double,
    val spvDegPerSec: Double,
    val uploaded: Boolean,
    val archivedOnServer: Boolean = false,
    val videoPath: String? = null,
    val pitchSeries: List<Double> = emptyList(),
    val yawSeries: List<Double> = emptyList(),
    val timestampsMs: List<Long> = emptyList()
)

interface MonitorRepository {
    suspend fun loginOrCreateAccount(id: String, name: String): PatientAccount
    suspend fun getAllAccounts(): List<PatientAccount>
    suspend fun addRawRecord(
        account: PatientAccount,
        videoPath: String?,
        pitchSeries: List<Double>,
        yawSeries: List<Double>,
        timestampsMs: List<Long>
    ): NystagmusRecord
    suspend fun updateRecordAnalysis(
        accountId: String,
        recordId: String,
        analysis: NystagmusDetectionResult
    ): Boolean
    suspend fun getPendingAnalysisRecords(accountId: String): List<NystagmusRecord>
    suspend fun uploadPending(accountId: String, serverUrl: String): Int
    suspend fun getRecordsByAccount(accountId: String): List<NystagmusRecord>
    suspend fun deleteRecord(accountId: String, recordId: String): Boolean
}

private data class ServerAnalysis(
    val analysisCompleted: Boolean,
    val suspectNystagmus: Boolean,
    val summary: String,
    val horizontalDirectionLabel: String,
    val verticalDirectionLabel: String,
    val dominantFrequencyHz: Double,
    val spvDegPerSec: Double
)

private data class UploadSyncResult(
    val uploadedIds: Set<String>,
    val analyzedById: Map<String, ServerAnalysis>
)

private fun createPendingRecord(
    account: PatientAccount,
    videoPath: String?,
    pitchSeries: List<Double>,
    yawSeries: List<Double>,
    timestampsMs: List<Long>
): NystagmusRecord {
    val now = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date())
    val durationSec = when {
        timestampsMs.size >= 2 -> {
            ((timestampsMs.last() - timestampsMs.first()) / 1000.0).roundToInt().coerceAtLeast(1)
        }
        else -> (maxOf(pitchSeries.size, yawSeries.size) / 30.0).roundToInt().coerceAtLeast(1)
    }
    return NystagmusRecord(
        id = "rec_${System.currentTimeMillis()}",
        accountId = account.id,
        accountName = account.name,
        startedAt = now,
        durationSec = durationSec,
        analysisCompleted = false,
        suspectNystagmus = false,
        summary = "待分析",
        horizontalDirectionLabel = "-",
        verticalDirectionLabel = "-",
        dominantFrequencyHz = 0.0,
        spvDegPerSec = 0.0,
        uploaded = false,
        archivedOnServer = false,
        videoPath = videoPath,
        pitchSeries = pitchSeries,
        yawSeries = yawSeries,
        timestampsMs = timestampsMs
    )
}

class InMemoryMonitorRepository : MonitorRepository {
    private val accounts = linkedMapOf<String, PatientAccount>()
    private val recordsByAccount = mutableMapOf<String, MutableList<NystagmusRecord>>()

    override suspend fun loginOrCreateAccount(id: String, name: String): PatientAccount {
        val cleanId = id.trim()
        val cleanName = name.trim()
        val existing = accounts[cleanId]
        if (existing != null) return existing
        val created = PatientAccount(id = cleanId, name = cleanName)
        accounts[cleanId] = created
        recordsByAccount.putIfAbsent(cleanId, mutableListOf())
        return created
    }

    override suspend fun getAllAccounts(): List<PatientAccount> = accounts.values.toList()

    override suspend fun addRawRecord(
        account: PatientAccount,
        videoPath: String?,
        pitchSeries: List<Double>,
        yawSeries: List<Double>,
        timestampsMs: List<Long>
    ): NystagmusRecord {
        val accountRecords = recordsByAccount.getOrPut(account.id) { mutableListOf() }
        val record = createPendingRecord(account, videoPath, pitchSeries, yawSeries, timestampsMs)
        accountRecords.add(0, record)
        return record
    }

    override suspend fun updateRecordAnalysis(
        accountId: String,
        recordId: String,
        analysis: NystagmusDetectionResult
    ): Boolean {
        val list = recordsByAccount[accountId] ?: return false
        val idx = list.indexOfFirst { it.id == recordId }
        if (idx < 0) return false
        val original = list[idx]
        list[idx] = original.copy(
            analysisCompleted = true,
            suspectNystagmus = analysis.hasNystagmus,
            summary = analysis.summary,
            horizontalDirectionLabel = analysis.horizontal.directionLabel,
            verticalDirectionLabel = analysis.vertical.directionLabel,
            dominantFrequencyHz = maxOf(analysis.horizontal.frequencyHz, analysis.vertical.frequencyHz),
            spvDegPerSec = maxOf(analysis.horizontal.spv, analysis.vertical.spv)
        )
        return true
    }

    override suspend fun getPendingAnalysisRecords(accountId: String): List<NystagmusRecord> {
        return recordsByAccount[accountId]?.filter { !it.analysisCompleted }.orEmpty()
    }

    override suspend fun uploadPending(accountId: String, serverUrl: String): Int {
        if (serverUrl.isBlank()) return 0
        val accountRecords = recordsByAccount[accountId] ?: return 0
        val pending = accountRecords.filter { !it.uploaded }
        var count = 0
        for (item in pending) {
            val idx = accountRecords.indexOfFirst { it.id == item.id }
            if (idx >= 0) {
                accountRecords[idx] = item.copy(uploaded = true)
                count++
            }
        }
        return count
    }

    override suspend fun getRecordsByAccount(accountId: String): List<NystagmusRecord> {
        return recordsByAccount[accountId]?.toList().orEmpty()
    }

    override suspend fun deleteRecord(accountId: String, recordId: String): Boolean {
        val list = recordsByAccount[accountId] ?: return false
        val removed = list.removeAll { it.id == recordId }
        return removed
    }
}

class SharedPrefsMonitorRepository(
    context: Context
) : MonitorRepository {
    private val prefs: SharedPreferences = context.getSharedPreferences(
        PREFS_NAME,
        Context.MODE_PRIVATE
    )
    private val accounts = linkedMapOf<String, PatientAccount>()
    private val recordsByAccount = mutableMapOf<String, MutableList<NystagmusRecord>>()

    init {
        loadState()
    }

    override suspend fun loginOrCreateAccount(id: String, name: String): PatientAccount {
        val cleanId = id.trim()
        val cleanName = name.trim()
        val existing = accounts[cleanId]
        if (existing != null) {
            if (existing.name != cleanName && cleanName.isNotBlank()) {
                val updated = existing.copy(name = cleanName)
                accounts[cleanId] = updated
                saveState()
                return updated
            }
            return existing
        }
        val created = PatientAccount(id = cleanId, name = cleanName)
        accounts[cleanId] = created
        recordsByAccount.putIfAbsent(cleanId, mutableListOf())
        saveState()
        return created
    }

    override suspend fun getAllAccounts(): List<PatientAccount> = accounts.values.toList()

    override suspend fun addRawRecord(
        account: PatientAccount,
        videoPath: String?,
        pitchSeries: List<Double>,
        yawSeries: List<Double>,
        timestampsMs: List<Long>
    ): NystagmusRecord {
        val accountRecords = recordsByAccount.getOrPut(account.id) { mutableListOf() }
        val record = createPendingRecord(account, videoPath, pitchSeries, yawSeries, timestampsMs)
        accountRecords.add(0, record)
        saveState()
        return record
    }

    override suspend fun updateRecordAnalysis(
        accountId: String,
        recordId: String,
        analysis: NystagmusDetectionResult
    ): Boolean {
        val list = recordsByAccount[accountId] ?: return false
        val idx = list.indexOfFirst { it.id == recordId }
        if (idx < 0) return false
        val original = list[idx]
        list[idx] = original.copy(
            analysisCompleted = true,
            suspectNystagmus = analysis.hasNystagmus,
            summary = analysis.summary,
            horizontalDirectionLabel = analysis.horizontal.directionLabel,
            verticalDirectionLabel = analysis.vertical.directionLabel,
            dominantFrequencyHz = maxOf(analysis.horizontal.frequencyHz, analysis.vertical.frequencyHz),
            spvDegPerSec = maxOf(analysis.horizontal.spv, analysis.vertical.spv)
        )
        saveState()
        return true
    }

    override suspend fun getPendingAnalysisRecords(accountId: String): List<NystagmusRecord> {
        return recordsByAccount[accountId]?.filter { !it.analysisCompleted }.orEmpty()
    }

    override suspend fun uploadPending(accountId: String, serverUrl: String): Int {
        if (serverUrl.isBlank()) return 0
        val accountRecords = recordsByAccount[accountId] ?: return 0
        // 先拉一次服务器记录，用于判断“本地已上传但服务器缺失”的自愈重传。
        val beforeServerRecords = fetchServerRecords(serverUrl, accountId)
        val serverIdsBefore = beforeServerRecords?.map { it.id }?.toHashSet()

        val pending = accountRecords.filter { local ->
            if (local.archivedOnServer) return@filter false
            if (local.videoPath.isNullOrBlank()) return@filter false
            if (!local.uploaded) return@filter true
            // 本地显示已上传，但服务器没有该记录 -> 允许重传修复
            if (serverIdsBefore != null && !serverIdsBefore.contains(local.id)) return@filter true
            false
        }
        var uploadedCount = 0
        if (pending.isNotEmpty()) {
            val mergedUploadedIds = mutableSetOf<String>()
            val mergedAnalysis = mutableMapOf<String, ServerAnalysis>()
            pending.forEach { record ->
                val sync = uploadSingleVideoRecord(serverUrl, accountId, record)
                mergedUploadedIds += sync.uploadedIds
                mergedAnalysis.putAll(sync.analyzedById)
            }
            if (mergedUploadedIds.isNotEmpty()) {
                for (idx in accountRecords.indices) {
                    val item = accountRecords[idx]
                    if (!item.uploaded && mergedUploadedIds.contains(item.id)) {
                        val analyzed = mergedAnalysis[item.id]
                        accountRecords[idx] = if (analyzed != null) {
                            item.copy(
                                uploaded = true,
                                analysisCompleted = analyzed.analysisCompleted,
                                suspectNystagmus = analyzed.suspectNystagmus,
                                summary = analyzed.summary,
                                horizontalDirectionLabel = analyzed.horizontalDirectionLabel,
                                verticalDirectionLabel = analyzed.verticalDirectionLabel,
                                dominantFrequencyHz = analyzed.dominantFrequencyHz,
                                spvDegPerSec = analyzed.spvDegPerSec,
                                archivedOnServer = false
                            )
                        } else {
                            item.copy(uploaded = true, archivedOnServer = false)
                        }
                        uploadedCount++
                    }
                }
            }
        }

        // 每次上传后都进行一次服务器->手机同步，确保两端一致
        val serverRecords = fetchServerRecords(serverUrl, accountId)
        if (serverRecords != null) {
            // 增量同步策略：
            // 1) 服务器记录补回客户端（支持“之前上传过的记录重新同步回来”）
            // 2) 客户端本地独有记录（通常待上传）不被强制删除
            val localById = accountRecords.associateBy { it.id }
            val merged = mutableListOf<NystagmusRecord>()
            val serverIds = hashSetOf<String>()
            for (remote in serverRecords) {
                serverIds += remote.id
                val local = localById[remote.id]
                merged += if (local == null) {
                    remote
                } else {
                    local.copy(
                        uploaded = remote.uploaded,
                        analysisCompleted = remote.analysisCompleted,
                        suspectNystagmus = remote.suspectNystagmus,
                        summary = remote.summary,
                        horizontalDirectionLabel = remote.horizontalDirectionLabel,
                        verticalDirectionLabel = remote.verticalDirectionLabel,
                        dominantFrequencyHz = remote.dominantFrequencyHz,
                        spvDegPerSec = remote.spvDegPerSec,
                        archivedOnServer = remote.archivedOnServer,
                        pitchSeries = if (remote.pitchSeries.isNotEmpty()) remote.pitchSeries else local.pitchSeries,
                        yawSeries = if (remote.yawSeries.isNotEmpty()) remote.yawSeries else local.yawSeries,
                        timestampsMs = if (remote.timestampsMs.isNotEmpty()) remote.timestampsMs else local.timestampsMs,
                        videoPath = local.videoPath
                    )
                }
            }
            for (local in accountRecords) {
                if (!serverIds.contains(local.id)) {
                    merged += local
                }
            }
            // 用 startedAt 倒序（格式 yyyy-MM-dd HH:mm:ss，字符串可比）
            recordsByAccount[accountId] = merged.sortedByDescending { it.startedAt }.toMutableList()
        }

        saveState()
        return uploadedCount
    }

    override suspend fun getRecordsByAccount(accountId: String): List<NystagmusRecord> {
        return recordsByAccount[accountId]?.toList().orEmpty()
    }

    override suspend fun deleteRecord(accountId: String, recordId: String): Boolean {
        val list = recordsByAccount[accountId] ?: return false
        val removed = list.removeAll { it.id == recordId }
        if (removed) saveState()
        return removed
    }

    private fun loadState() {
        accounts.clear()
        recordsByAccount.clear()
        val stateRaw = prefs.getString(KEY_STATE_JSON, null) ?: return
        runCatching {
            val root = JSONObject(stateRaw)
            val accountsArray = root.optJSONArray("accounts") ?: JSONArray()
            for (i in 0 until accountsArray.length()) {
                val item = accountsArray.optJSONObject(i) ?: continue
                val id = item.optString("id").trim()
                val name = item.optString("name").trim()
                if (id.isBlank() || name.isBlank()) continue
                accounts[id] = PatientAccount(id = id, name = name)
            }

            val recordsObj = root.optJSONObject("recordsByAccount") ?: JSONObject()
            val ids = recordsObj.keys()
            while (ids.hasNext()) {
                val accountId = ids.next()
                val recordArray = recordsObj.optJSONArray(accountId) ?: JSONArray()
                val parsed = mutableListOf<NystagmusRecord>()
                for (idx in 0 until recordArray.length()) {
                    val recObj = recordArray.optJSONObject(idx) ?: continue
                    parseRecord(recObj)?.let { parsed += it }
                }
                recordsByAccount[accountId] = parsed
            }
        }.onFailure {
            // 忽略坏数据，保持可用
        }
    }

    private fun saveState() {
        val root = JSONObject()
        val accountsArray = JSONArray()
        accounts.values.forEach { account ->
            accountsArray.put(
                JSONObject()
                    .put("id", account.id)
                    .put("name", account.name)
            )
        }
        root.put("accounts", accountsArray)

        val recordsObj = JSONObject()
        recordsByAccount.forEach { (accountId, records) ->
            val arr = JSONArray()
            records.forEach { arr.put(recordToJson(it)) }
            recordsObj.put(accountId, arr)
        }
        root.put("recordsByAccount", recordsObj)

        prefs.edit().putString(KEY_STATE_JSON, root.toString()).apply()
    }

    private fun recordToJson(item: NystagmusRecord): JSONObject {
        return JSONObject()
            .put("id", item.id)
            .put("accountId", item.accountId)
            .put("accountName", item.accountName)
            .put("startedAt", item.startedAt)
            .put("durationSec", item.durationSec)
            .put("analysisCompleted", item.analysisCompleted)
            .put("suspectNystagmus", item.suspectNystagmus)
            .put("summary", item.summary)
            .put("horizontalDirectionLabel", item.horizontalDirectionLabel)
            .put("verticalDirectionLabel", item.verticalDirectionLabel)
            .put("dominantFrequencyHz", item.dominantFrequencyHz)
            .put("spvDegPerSec", item.spvDegPerSec)
            .put("uploaded", item.uploaded)
            .put("archivedOnServer", item.archivedOnServer)
            .put("videoPath", item.videoPath)
            .put("pitchSeries", JSONArray(item.pitchSeries))
            .put("yawSeries", JSONArray(item.yawSeries))
            .put("timestampsMs", JSONArray(item.timestampsMs))
    }

    private fun parseRecord(obj: JSONObject): NystagmusRecord? {
        val id = obj.optString("id").trim()
        val accountId = obj.optString("accountId").trim()
        if (id.isBlank() || accountId.isBlank()) return null
        return NystagmusRecord(
            id = id,
            accountId = accountId,
            accountName = obj.optString("accountName"),
            startedAt = obj.optString("startedAt"),
            durationSec = obj.optInt("durationSec", 0),
            analysisCompleted = obj.optBoolean("analysisCompleted", true),
            suspectNystagmus = obj.optBoolean("suspectNystagmus", false),
            summary = obj.optString("summary"),
            horizontalDirectionLabel = obj.optString("horizontalDirectionLabel"),
            verticalDirectionLabel = obj.optString("verticalDirectionLabel"),
            dominantFrequencyHz = obj.optDouble("dominantFrequencyHz", 0.0),
            spvDegPerSec = obj.optDouble("spvDegPerSec", 0.0),
            uploaded = obj.optBoolean("uploaded", false),
            archivedOnServer = obj.optBoolean("archivedOnServer", false),
            videoPath = obj.optString("videoPath").takeIf { it.isNotBlank() },
            pitchSeries = jsonArrayToDoubleList(obj.optJSONArray("pitchSeries")),
            yawSeries = jsonArrayToDoubleList(obj.optJSONArray("yawSeries")),
            timestampsMs = jsonArrayToLongList(obj.optJSONArray("timestampsMs"))
        )
    }

    private fun jsonArrayToDoubleList(arr: JSONArray?): List<Double> {
        if (arr == null) return emptyList()
        return buildList {
            for (i in 0 until arr.length()) add(arr.optDouble(i, Double.NaN))
        }
    }

    private fun jsonArrayToLongList(arr: JSONArray?): List<Long> {
        if (arr == null) return emptyList()
        return buildList {
            for (i in 0 until arr.length()) add(arr.optLong(i, 0L))
        }
    }

    private suspend fun uploadRecordsToServer(
        serverUrl: String,
        accountId: String,
        records: List<NystagmusRecord>
    ): UploadSyncResult = withContext(Dispatchers.IO) {
        runCatching {
            val endpoint = buildUploadEndpoint(serverUrl)
            val payload = JSONObject()
                .put("accountId", accountId)
                .put("records", JSONArray(records.map { recordToJson(it) }))
            val body = payload.toString().toByteArray(Charsets.UTF_8)

            val conn = (URL(endpoint).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 5000
                readTimeout = 15000
                doOutput = true
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
                setRequestProperty("Accept", "application/json")
            }
            conn.outputStream.use { it.write(body) }
            val responseCode = conn.responseCode
            val responseText = if (responseCode in 200..299) {
                conn.inputStream.bufferedReader().use { it.readText() }
            } else {
                conn.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
            }
            conn.disconnect()
            if (responseCode !in 200..299) {
                return@runCatching UploadSyncResult(emptySet(), emptyMap())
            }
            val json = JSONObject(responseText.ifBlank { "{}" })
            val analysisById = parseServerAnalysisMap(json.optJSONArray("analyzedRecords"))
            val uploadedIds = json.optJSONArray("uploadedRecordIds")
            if (uploadedIds != null) {
                val ids = buildSet {
                    for (i in 0 until uploadedIds.length()) {
                        val id = uploadedIds.optString(i).trim()
                        if (id.isNotEmpty()) add(id)
                    }
                }
                return@runCatching UploadSyncResult(ids, analysisById)
            }
            // 兼容只返回 acceptedCount 的服务端
            val accepted = json.optInt("acceptedCount", 0).coerceAtMost(records.size)
            UploadSyncResult(
                uploadedIds = records.take(accepted).map { it.id }.toSet(),
                analyzedById = analysisById
            )
        }.getOrElse { UploadSyncResult(emptySet(), emptyMap()) }
    }

    private suspend fun uploadSingleVideoRecord(
        serverUrl: String,
        accountId: String,
        record: NystagmusRecord
    ): UploadSyncResult = withContext(Dispatchers.IO) {
        runCatching {
            val filePath = record.videoPath ?: return@runCatching UploadSyncResult(emptySet(), emptyMap())
            val file = File(filePath)
            if (!file.exists() || !file.isFile) {
                return@runCatching UploadSyncResult(emptySet(), emptyMap())
            }

            val endpoint = buildVideoUploadEndpoint(serverUrl)
            val boundary = "----HNM${System.currentTimeMillis()}"
            val conn = (URL(endpoint).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 5000
                readTimeout = 120000
                doOutput = true
                setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
                setRequestProperty("Accept", "application/json")
            }

            conn.outputStream.use { os ->
                writeFormField(os, boundary, "accountId", accountId)
                writeFormField(os, boundary, "recordId", record.id)
                writeFormField(os, boundary, "accountName", record.accountName)
                writeFormField(
                    os,
                    boundary,
                    "patientId",
                    record.accountId.ifBlank { accountId }
                )
                writeFormField(os, boundary, "startedAt", record.startedAt)
                writeFormField(os, boundary, "durationSec", record.durationSec.toString())
                writeFormField(os, boundary, "inputMode", "single_eye")
                writeFileField(os, boundary, "video", file, "video/mp4")
                os.write("--$boundary--\r\n".toByteArray(Charsets.UTF_8))
            }

            val responseCode = conn.responseCode
            val responseText = if (responseCode in 200..299) {
                conn.inputStream.bufferedReader().use { it.readText() }
            } else {
                conn.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
            }
            conn.disconnect()
            if (responseCode !in 200..299) {
                return@runCatching UploadSyncResult(emptySet(), emptyMap())
            }

            val json = JSONObject(responseText.ifBlank { "{}" })
            val uploadedRecordId = json.optString("uploadedRecordId").trim()
            val analysis = ServerAnalysis(
                analysisCompleted = json.optBoolean("analysisCompleted", true),
                suspectNystagmus = json.optBoolean("suspectNystagmus", false),
                summary = json.optString("summary"),
                horizontalDirectionLabel = json.optString("horizontalDirectionLabel"),
                verticalDirectionLabel = json.optString("verticalDirectionLabel"),
                dominantFrequencyHz = json.optDouble("dominantFrequencyHz", 0.0),
                spvDegPerSec = json.optDouble("spvDegPerSec", 0.0)
            )
            if (uploadedRecordId.isBlank()) {
                UploadSyncResult(emptySet(), emptyMap())
            } else {
                UploadSyncResult(setOf(uploadedRecordId), mapOf(uploadedRecordId to analysis))
            }
        }.getOrElse { UploadSyncResult(emptySet(), emptyMap()) }
    }

    private fun buildUploadEndpoint(serverUrl: String): String {
        val base = serverUrl.trim().removeSuffix("/")
        return if (base.endsWith("/api/records")) base else "$base/api/records"
    }

    private fun buildVideoUploadEndpoint(serverUrl: String): String {
        val base = serverUrl.trim().removeSuffix("/")
        return if (base.endsWith("/api/videos")) base else "$base/api/videos"
    }

    private fun writeFormField(
        os: OutputStream,
        boundary: String,
        name: String,
        value: String
    ) {
        os.write("--$boundary\r\n".toByteArray(Charsets.UTF_8))
        os.write("Content-Disposition: form-data; name=\"$name\"\r\n\r\n".toByteArray(Charsets.UTF_8))
        os.write(value.toByteArray(Charsets.UTF_8))
        os.write("\r\n".toByteArray(Charsets.UTF_8))
    }

    private fun writeFileField(
        os: OutputStream,
        boundary: String,
        name: String,
        file: File,
        mimeType: String
    ) {
        os.write("--$boundary\r\n".toByteArray(Charsets.UTF_8))
        os.write(
            "Content-Disposition: form-data; name=\"$name\"; filename=\"${file.name}\"\r\n"
                .toByteArray(Charsets.UTF_8)
        )
        os.write("Content-Type: $mimeType\r\n\r\n".toByteArray(Charsets.UTF_8))
        file.inputStream().use { input -> input.copyTo(os) }
        os.write("\r\n".toByteArray(Charsets.UTF_8))
    }

    private fun parseServerAnalysisMap(arr: JSONArray?): Map<String, ServerAnalysis> {
        if (arr == null) return emptyMap()
        return buildMap {
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                val id = obj.optString("id").trim()
                if (id.isEmpty()) continue
                put(
                    id,
                    ServerAnalysis(
                        analysisCompleted = obj.optBoolean("analysisCompleted", true),
                        suspectNystagmus = obj.optBoolean("suspectNystagmus", false),
                        summary = obj.optString("summary"),
                        horizontalDirectionLabel = obj.optString("horizontalDirectionLabel"),
                        verticalDirectionLabel = obj.optString("verticalDirectionLabel"),
                        dominantFrequencyHz = obj.optDouble("dominantFrequencyHz", 0.0),
                        spvDegPerSec = obj.optDouble("spvDegPerSec", 0.0)
                    )
                )
            }
        }
    }

    private suspend fun fetchServerRecords(
        serverUrl: String,
        accountId: String
    ): List<NystagmusRecord>? = withContext(Dispatchers.IO) {
        runCatching {
            val endpoint = buildRecordsQueryEndpoint(serverUrl, accountId)
            val conn = (URL(endpoint).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 5000
                readTimeout = 15000
                setRequestProperty("Accept", "application/json")
            }
            val responseCode = conn.responseCode
            val responseText = if (responseCode in 200..299) {
                conn.inputStream.bufferedReader().use { it.readText() }
            } else {
                conn.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
            }
            conn.disconnect()
            if (responseCode !in 200..299) return@runCatching null
            val root = JSONObject(responseText.ifBlank { "{}" })
            val arr = root.optJSONArray("records") ?: return@runCatching emptyList<NystagmusRecord>()
            buildList {
                for (i in 0 until arr.length()) {
                    val obj = arr.optJSONObject(i) ?: continue
                    val id = obj.optString("id").trim()
                    val accId = obj.optString("accountId").trim()
                    if (id.isBlank() || accId.isBlank()) continue
                    add(
                        NystagmusRecord(
                            id = id,
                            accountId = accId,
                            accountName = obj.optString("accountName"),
                            startedAt = obj.optString("startedAt"),
                            durationSec = obj.optInt("durationSec", 0),
                            analysisCompleted = obj.optBoolean("analysisCompleted", false),
                            suspectNystagmus = obj.optBoolean("suspectNystagmus", false),
                            summary = obj.optString("summary"),
                            horizontalDirectionLabel = obj.optString("horizontalDirectionLabel"),
                            verticalDirectionLabel = obj.optString("verticalDirectionLabel"),
                            dominantFrequencyHz = obj.optDouble("dominantFrequencyHz", 0.0),
                            spvDegPerSec = obj.optDouble("spvDegPerSec", 0.0),
                            uploaded = obj.optBoolean("uploaded", true),
                            archivedOnServer = obj.optBoolean("archived", false),
                            videoPath = null,
                            pitchSeries = jsonArrayToDoubleList(obj.optJSONArray("pitchSeries")),
                            yawSeries = jsonArrayToDoubleList(obj.optJSONArray("yawSeries")),
                            timestampsMs = jsonArrayToLongList(obj.optJSONArray("timestampsMs"))
                        )
                    )
                }
            }
        }.getOrElse { null }
    }

    private fun buildRecordsQueryEndpoint(serverUrl: String, accountId: String): String {
        val base = serverUrl.trim().removeSuffix("/")
        val encoded = java.net.URLEncoder.encode(accountId, Charsets.UTF_8.name())
        return "$base/api/records?accountId=$encoded&limit=500&includeArchived=1"
    }

    private companion object {
        private const val PREFS_NAME = "monitor_repository_prefs"
        private const val KEY_STATE_JSON = "state_json"
    }
}

object AppGraph {
    fun repository(context: Context): MonitorRepository {
        return SharedPrefsMonitorRepository(context.applicationContext)
    }
}
