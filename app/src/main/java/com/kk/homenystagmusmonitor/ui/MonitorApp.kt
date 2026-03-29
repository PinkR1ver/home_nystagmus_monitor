package com.kk.homenystagmusmonitor.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.kk.homenystagmusmonitor.data.AppGraph
import com.kk.homenystagmusmonitor.data.NystagmusRecord
import com.kk.homenystagmusmonitor.ui.theme.MonitorTheme

private enum class Tab(val label: String) {
    Home("采集"),
    Records("记录"),
    Settings("设置")
}

@Composable
fun MonitorApp() {
    val vm: MonitorViewModel = viewModel(
        factory = MonitorViewModel.factory(AppGraph.repository)
    )
    val uiState by vm.uiState.collectAsState()
    var tab by rememberSaveable { mutableStateOf(Tab.Home) }

    MonitorTheme {
        if (uiState.currentAccount == null) {
            LoginScreen(
                uiState = uiState,
                onLoginIdInputChange = vm::updateLoginIdInput,
                onLoginNameInputChange = vm::updateLoginNameInput,
                onLogin = vm::login
            )
        } else {
            Scaffold(
                bottomBar = {
                    NavigationBar {
                        Tab.entries.forEach { item ->
                            NavigationBarItem(
                                selected = tab == item,
                                onClick = { tab = item },
                                icon = {},
                                label = { Text(item.label) }
                            )
                        }
                    }
                }
            ) { innerPadding ->
                when (tab) {
                    Tab.Home -> HomeScreen(
                        modifier = Modifier.padding(innerPadding),
                        uiState = uiState,
                        onStart = vm::startSession,
                        onStop = vm::stopSession,
                        onAddMockRecord = vm::addMockRecord,
                        onUpload = vm::uploadPending
                    )

                    Tab.Records -> RecordsScreen(
                        modifier = Modifier.padding(innerPadding),
                        uiState = uiState
                    )

                    Tab.Settings -> SettingsScreen(
                        modifier = Modifier.padding(innerPadding),
                        uiState = uiState,
                        onServerUrlChange = vm::updateServerUrl,
                        onLoginIdInputChange = vm::updateLoginIdInput,
                        onLoginNameInputChange = vm::updateLoginNameInput,
                        onLogin = vm::login,
                        onSwitchAccount = vm::switchAccount
                    )
                }
            }
        }
    }
}

@Composable
private fun LoginScreen(
    uiState: MonitorUiState,
    onLoginIdInputChange: (String) -> Unit,
    onLoginNameInputChange: (String) -> Unit,
    onLogin: () -> Unit
) {
    val gradient = Brush.verticalGradient(
        colors = listOf(
            MaterialTheme.colorScheme.primaryContainer,
            MaterialTheme.colorScheme.surface
        )
    )
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(gradient)
            .padding(24.dp),
        contentAlignment = Alignment.Center
    ) {
        ElevatedCard(
            modifier = Modifier
                .fillMaxWidth(),
            colors = CardDefaults.elevatedCardColors(
                containerColor = MaterialTheme.colorScheme.surface
            )
        ) {
            Column(
                modifier = Modifier.padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text("Home Nystagmus Monitor", style = MaterialTheme.typography.titleMedium)
                Text(
                    "患者账号登录",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold
                )
                OutlinedTextField(
                    value = uiState.loginIdInput,
                    onValueChange = onLoginIdInputChange,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("患者ID") },
                    placeholder = { Text("例如 P-001") },
                    singleLine = true
                )
                OutlinedTextField(
                    value = uiState.loginNameInput,
                    onValueChange = onLoginNameInputChange,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("姓名") },
                    placeholder = { Text("例如 张三") },
                    singleLine = true
                )
                Button(
                    onClick = onLogin,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("登录并开始")
                }
                Text(
                    uiState.statusMessage,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun HomeScreen(
    modifier: Modifier = Modifier,
    uiState: MonitorUiState,
    onStart: () -> Unit,
    onStop: () -> Unit,
    onAddMockRecord: () -> Unit,
    onUpload: () -> Unit
) {
    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        contentPadding = PaddingValues(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            SectionTitle(
                title = "采集控制台",
                subtitle = "当前账号：${uiState.currentAccount?.name} (${uiState.currentAccount?.id})"
            )
        }
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer
                )
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("设备状态", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Spacer(modifier = Modifier.height(10.dp))
                    Text(uiState.statusMessage)
                }
            }
        }
        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = onStart,
                            enabled = !uiState.isSessionRunning,
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("开始采集")
                        }
                        FilledTonalButton(
                            onClick = onStop,
                            enabled = uiState.isSessionRunning,
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("停止采集")
                        }
                    }
                    FilledTonalButton(onClick = onAddMockRecord, modifier = Modifier.fillMaxWidth()) {
                        Text("生成本次模拟记录")
                    }
                    Button(onClick = onUpload, modifier = Modifier.fillMaxWidth()) {
                        Text("上传待传记录")
                    }
                }
            }
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                AssistChip(
                    onClick = {},
                    label = { Text("记录 ${uiState.records.size} 条") },
                    colors = AssistChipDefaults.assistChipColors(
                        containerColor = MaterialTheme.colorScheme.secondaryContainer
                    )
                )
                AssistChip(
                    onClick = {},
                    label = { Text(if (uiState.isSessionRunning) "采集中" else "待机") }
                )
            }
        }
        item {
            Text(
                "提示：检测算法尚未接入，当前用于流程与界面联调。",
                style = MaterialTheme.typography.bodySmall
            )
        }
    }
}

@Composable
private fun RecordsScreen(
    modifier: Modifier = Modifier,
    uiState: MonitorUiState
) {
    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            SectionTitle(
                title = "记录列表",
                subtitle = "仅展示当前账号数据"
            )
        }
        if (uiState.records.isEmpty()) {
            item {
                EmptyStateCard(
                    title = "暂无记录",
                    description = "先回到采集页，点击“生成本次模拟记录”来验证流程。"
                )
            }
        } else {
            items(uiState.records) { item ->
                RecordCard(item = item)
            }
        }
    }
}

@Composable
private fun SettingsScreen(
    modifier: Modifier = Modifier,
    uiState: MonitorUiState,
    onServerUrlChange: (String) -> Unit,
    onLoginIdInputChange: (String) -> Unit,
    onLoginNameInputChange: (String) -> Unit,
    onLogin: () -> Unit,
    onSwitchAccount: (String) -> Unit
) {
    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        contentPadding = PaddingValues(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            SectionTitle(
                title = "设置",
                subtitle = "账号管理与上传配置"
            )
        }
        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text("当前账号", style = MaterialTheme.typography.titleMedium)
                    Text("${uiState.currentAccount?.name} (${uiState.currentAccount?.id})")
                }
            }
        }
        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text("切换 / 新增账号", style = MaterialTheme.typography.titleMedium)
                    OutlinedTextField(
                        value = uiState.loginIdInput,
                        onValueChange = onLoginIdInputChange,
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("患者ID") },
                        singleLine = true
                    )
                    OutlinedTextField(
                        value = uiState.loginNameInput,
                        onValueChange = onLoginNameInputChange,
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("姓名") },
                        singleLine = true
                    )
                    Button(onClick = onLogin, modifier = Modifier.fillMaxWidth()) {
                        Text("登录并切换账号")
                    }
                }
            }
        }
        if (uiState.accounts.isNotEmpty()) {
            item {
                Text("历史账号", style = MaterialTheme.typography.titleMedium)
            }
            items(uiState.accounts) { account ->
                val isCurrent = uiState.currentAccount?.id == account.id
                val borderColor = if (isCurrent) {
                    MaterialTheme.colorScheme.primary
                } else {
                    Color.Transparent
                }
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .border(
                            width = if (isCurrent) 1.dp else 0.dp,
                            color = borderColor,
                            shape = RoundedCornerShape(16.dp)
                        )
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column {
                            Text(account.name)
                            Text(account.id, style = MaterialTheme.typography.bodySmall)
                        }
                        Row {
                            if (isCurrent) {
                                FilterChip(
                                    selected = true,
                                    onClick = {},
                                    label = { Text("当前") },
                                    colors = FilterChipDefaults.filterChipColors(
                                        selectedContainerColor = MaterialTheme.colorScheme.primaryContainer
                                    )
                                )
                            } else {
                                TextButton(onClick = { onSwitchAccount(account.id) }) {
                                    Text("切换")
                                }
                            }
                        }
                    }
                }
            }
        }
        item {
            HorizontalDivider()
            Spacer(modifier = Modifier.height(6.dp))
            OutlinedTextField(
                value = uiState.serverUrl,
                onValueChange = onServerUrlChange,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("服务器上传地址") },
                singleLine = true
            )
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                "不同账号数据已隔离，上传逻辑仍为占位实现。",
                style = MaterialTheme.typography.bodySmall
            )
        }
    }
}

@Composable
private fun SectionTitle(
    title: String,
    subtitle: String
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
        Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Immutable
private data class RecordMeta(
    val title: String,
    val value: String
)

@Composable
private fun RecordCard(item: NystagmusRecord) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                AssistChip(onClick = {}, label = { Text("时长 ${item.durationSec}s") })
                AssistChip(
                    onClick = {},
                    label = { Text(if (item.uploaded) "已上传" else "待上传") },
                    colors = AssistChipDefaults.assistChipColors(
                        containerColor = if (item.uploaded) {
                            MaterialTheme.colorScheme.secondaryContainer
                        } else {
                            MaterialTheme.colorScheme.surfaceContainerHighest
                        }
                    )
                )
            }
            val rows = listOf(
                RecordMeta("记录ID", item.id),
                RecordMeta("账号", "${item.accountName} (${item.accountId})"),
                RecordMeta("开始时间", item.startedAt),
                RecordMeta("疑似眼震", if (item.suspectNystagmus) "是" else "否")
            )
            rows.forEach { row ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(row.title, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(row.value)
                }
            }
        }
    }
}

@Composable
private fun EmptyStateCard(
    title: String,
    description: String
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(description, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
