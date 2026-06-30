package com.kk.homenystagmusmonitor.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.kk.homenystagmusmonitor.data.MonitorRepository
import com.kk.homenystagmusmonitor.data.NystagmusRecord
import com.kk.homenystagmusmonitor.data.PatientAccount
import com.kk.homenystagmusmonitor.data.SessionStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class MonitorUiState(
    val loginIdInput: String = "",
    val loginNameInput: String = "",
    val currentAccount: PatientAccount? = null,
    val accounts: List<PatientAccount> = emptyList(),
    val serverUrl: String = "http://10.0.2.2:8787",
    val isSessionRunning: Boolean = false,
    val useFrontCamera: Boolean = false,
    val statusMessage: String = "请先登录患者账号",
    val livePitchDeg: Double? = null,
    val liveYawDeg: Double? = null,
    val liveFps: Double? = null,
    val liveSampleCount: Int = 0,
    val isAnalyzingPending: Boolean = false,
    val analysisProgress: Float = 0f,
    val analysisProgressText: String = "",
    val records: List<NystagmusRecord> = emptyList()
)

class MonitorViewModel(
    private val repository: MonitorRepository,
    private val sessionStore: SessionStore
) : ViewModel() {
    private var sessionStartedAtMs: Long = 0L
    private val _uiState = MutableStateFlow(MonitorUiState())
    val uiState: StateFlow<MonitorUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            restoreLastLoginIfAny()
            restoreServerUrlIfAny()
            refreshAccounts()
        }
    }

    fun updateLoginIdInput(value: String) {
        _uiState.update { it.copy(loginIdInput = value) }
    }

    fun updateLoginNameInput(value: String) {
        _uiState.update { it.copy(loginNameInput = value) }
    }

    fun login() {
        viewModelScope.launch {
            val state = _uiState.value
            if (state.loginIdInput.isBlank() || state.loginNameInput.isBlank()) {
                _uiState.update { it.copy(statusMessage = "请输入患者ID和姓名") }
                return@launch
            }
            val account = repository.loginOrCreateAccount(
                id = state.loginIdInput,
                name = state.loginNameInput
            )
            sessionStore.saveLastLogin(account)
            _uiState.update {
                it.copy(
                    currentAccount = account,
                    statusMessage = "已登录：${account.name}"
                )
            }
            refreshAccounts()
            refreshRecords()
        }
    }

    fun switchAccount(accountId: String) {
        viewModelScope.launch {
            val account = repository.getAllAccounts().firstOrNull { it.id == accountId } ?: return@launch
            sessionStore.saveLastLogin(account)
            _uiState.update {
                it.copy(
                    currentAccount = account,
                    loginIdInput = account.id,
                    loginNameInput = account.name,
                    statusMessage = "已切换到：${account.name}"
                )
            }
            refreshRecords()
        }
    }

    fun updateServerUrl(value: String) {
        sessionStore.saveServerUrl(value)
        _uiState.update { it.copy(serverUrl = value) }
    }

    fun deleteRecord(recordId: String) {
        viewModelScope.launch {
            val accountId = _uiState.value.currentAccount?.id ?: return@launch
            val deleted = repository.deleteRecord(accountId, recordId)
            if (deleted) {
                _uiState.update { it.copy(statusMessage = "记录已删除") }
                refreshRecords()
            } else {
                _uiState.update { it.copy(statusMessage = "删除失败，请重试") }
            }
        }
    }

    fun toggleCameraLens() {
        if (_uiState.value.isSessionRunning) {
            _uiState.update { it.copy(statusMessage = "请先停止采集，再切换镜头") }
            return
        }
        _uiState.update { state ->
            val nextUseFront = !state.useFrontCamera
            state.copy(
                useFrontCamera = nextUseFront,
                statusMessage = if (nextUseFront) {
                    "已切换到前置相机"
                } else {
                    "已切换到后置相机"
                }
            )
        }
    }

    fun startSession() {
        sessionStartedAtMs = System.currentTimeMillis()
        _uiState.update {
            it.copy(
                isSessionRunning = true,
                statusMessage = "采集中：仅录制视频",
                liveFps = null,
                liveSampleCount = 0
            )
        }
    }

    fun stopSession() {
        viewModelScope.launch {
            val state = _uiState.value
            _uiState.update { it.copy(isSessionRunning = false) }
            if (state.currentAccount == null) {
                _uiState.update { it.copy(statusMessage = "请先登录账号") }
                return@launch
            }
            _uiState.update {
                it.copy(
                    statusMessage = "停止采集，正在保存视频文件..."
                )
            }
        }
    }

    fun onVideoRecorded(videoPath: String?, durationMs: Long) {
        viewModelScope.launch {
            val account = _uiState.value.currentAccount ?: return@launch
            if (videoPath.isNullOrBlank() || durationMs < 1_000L) {
                _uiState.update { it.copy(statusMessage = "视频保存失败或时长不足，未生成记录") }
                return@launch
            }
            val timestamps = listOf(sessionStartedAtMs, sessionStartedAtMs + durationMs)
            repository.addRawRecord(
                account = account,
                videoPath = videoPath,
                pitchSeries = emptyList(),
                yawSeries = emptyList(),
                timestampsMs = timestamps
            )
            _uiState.update { it.copy(statusMessage = "视频记录已保存，等待上传分析") }
            refreshRecords()
        }
    }

    fun uploadPending() {
        viewModelScope.launch {
            val state = _uiState.value
            val account = state.currentAccount ?: run {
                _uiState.update { it.copy(statusMessage = "请先登录账号") }
                return@launch
            }
            _uiState.update {
                it.copy(
                    isAnalyzingPending = true,
                    analysisProgress = 0f,
                    analysisProgressText = "同步中..."
                )
            }
            val uploaded = repository.uploadPending(account.id, state.serverUrl)
            _uiState.update {
                it.copy(
                    isAnalyzingPending = false,
                    analysisProgress = 0f,
                    analysisProgressText = "",
                    statusMessage = "同步完成：$uploaded 条已上传"
                )
            }
            refreshRecords()
        }
    }

    private suspend fun refreshAccounts() {
        val list = repository.getAllAccounts()
        _uiState.update { state ->
            val current = state.currentAccount ?: list.firstOrNull()
            state.copy(
                accounts = list,
                currentAccount = current,
                loginIdInput = current?.id ?: state.loginIdInput,
                loginNameInput = current?.name ?: state.loginNameInput
            )
        }
        refreshRecords()
    }

    private suspend fun refreshRecords() {
        val accountId = _uiState.value.currentAccount?.id
        val list = if (accountId == null) emptyList() else repository.getRecordsByAccount(accountId)
        _uiState.update { it.copy(records = list) }
    }

    private suspend fun restoreLastLoginIfAny() {
        val lastLogin = sessionStore.getLastLogin() ?: return
        val account = repository.loginOrCreateAccount(
            id = lastLogin.accountId,
            name = lastLogin.accountName
        )
        _uiState.update {
            it.copy(
                currentAccount = account,
                loginIdInput = account.id,
                loginNameInput = account.name,
                statusMessage = "欢迎回来，${account.name}"
            )
        }
    }

    private fun restoreServerUrlIfAny() {
        val saved = sessionStore.getServerUrl() ?: return
        _uiState.update { it.copy(serverUrl = saved) }
    }

    companion object {
        fun factory(
            repository: MonitorRepository,
            sessionStore: SessionStore
        ): ViewModelProvider.Factory {
            return object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return MonitorViewModel(repository, sessionStore) as T
                }
            }
        }
    }
}
