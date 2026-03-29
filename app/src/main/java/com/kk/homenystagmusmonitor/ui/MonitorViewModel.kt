package com.kk.homenystagmusmonitor.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.kk.homenystagmusmonitor.data.MonitorRepository
import com.kk.homenystagmusmonitor.data.NystagmusRecord
import com.kk.homenystagmusmonitor.data.PatientAccount
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
    val serverUrl: String = "https://example.com/api/records",
    val isSessionRunning: Boolean = false,
    val statusMessage: String = "请先登录患者账号",
    val records: List<NystagmusRecord> = emptyList()
)

class MonitorViewModel(
    private val repository: MonitorRepository
) : ViewModel() {
    private val _uiState = MutableStateFlow(MonitorUiState())
    val uiState: StateFlow<MonitorUiState> = _uiState.asStateFlow()

    init {
        refreshAccounts()
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
        _uiState.update { it.copy(serverUrl = value) }
    }

    fun startSession() {
        _uiState.update { it.copy(isSessionRunning = true, statusMessage = "采集中（占位流程）") }
    }

    fun stopSession() {
        _uiState.update { it.copy(isSessionRunning = false, statusMessage = "采集已停止") }
    }

    fun addMockRecord() {
        viewModelScope.launch {
            val state = _uiState.value
            val account = state.currentAccount ?: run {
                _uiState.update { it.copy(statusMessage = "请先登录账号") }
                return@launch
            }
            repository.addMockRecord(account)
            _uiState.update { it.copy(statusMessage = "已生成一条本地记录（模拟）") }
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
            val uploaded = repository.uploadPending(account.id, state.serverUrl)
            _uiState.update { it.copy(statusMessage = "上传完成：$uploaded 条") }
            refreshRecords()
        }
    }

    private fun refreshAccounts() {
        viewModelScope.launch {
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
    }

    private fun refreshRecords() {
        viewModelScope.launch {
            val accountId = _uiState.value.currentAccount?.id
            val list = if (accountId == null) emptyList() else repository.getRecordsByAccount(accountId)
            _uiState.update { it.copy(records = list) }
        }
    }

    companion object {
        fun factory(repository: MonitorRepository): ViewModelProvider.Factory {
            return object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return MonitorViewModel(repository) as T
                }
            }
        }
    }
}
