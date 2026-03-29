package com.kk.homenystagmusmonitor.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.kk.homenystagmusmonitor.data.AppGraph
import com.kk.homenystagmusmonitor.data.NystagmusRecord
import com.kk.homenystagmusmonitor.data.SharedPrefsSessionStore
import com.kk.homenystagmusmonitor.ui.theme.MonitorTheme
import kotlin.math.max

private enum class Tab(val label: String) {
    Home("采集"),
    Records("记录"),
    Settings("设置")
}

@Composable
fun MonitorApp() {
    val context = LocalContext.current
    val sessionStore = remember { SharedPrefsSessionStore(context.applicationContext) }
    val repository = remember { AppGraph.repository(context.applicationContext) }
    val vm: MonitorViewModel = viewModel(
        factory = MonitorViewModel.factory(
            repository = repository,
            sessionStore = sessionStore
        )
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
                        onToggleLens = vm::toggleCameraLens,
                        onVideoRecorded = vm::onVideoRecorded
                    )

                    Tab.Records -> RecordsScreen(
                        modifier = Modifier.padding(innerPadding),
                        uiState = uiState,
                        onUploadPending = vm::uploadPending,
                        onDeleteRecord = vm::deleteRecord
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
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface)
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
                Button(onClick = onLogin, modifier = Modifier.fillMaxWidth()) {
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
    onToggleLens: () -> Unit,
    onVideoRecorded: (String?, Long) -> Unit
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(0.96f),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                AssistChip(
                    onClick = {},
                    label = { Text(if (uiState.useFrontCamera) "前置" else "后置") }
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    AssistChip(
                        onClick = {},
                        label = {
                            Text(
                                if (uiState.liveFps != null) {
                                    "${"%.0f".format(uiState.liveFps)} fps"
                                } else {
                                    "60 fps 目标"
                                }
                            )
                        }
                    )
                    AssistChip(
                        onClick = onToggleLens,
                        enabled = !uiState.isSessionRunning,
                        label = { Text("切换镜头") }
                    )
                }
            }

            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainerLow
                )
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Box(modifier = Modifier.fillMaxWidth()) {
                        CameraCaptureView(
                            isRunning = uiState.isSessionRunning,
                            useFrontCamera = uiState.useFrontCamera,
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(420.dp),
                            onVideoRecorded = onVideoRecorded
                        )
                        if (uiState.isSessionRunning) {
                            Text(
                                "REC",
                                modifier = Modifier
                                    .align(Alignment.TopStart)
                                    .padding(10.dp),
                                color = MaterialTheme.colorScheme.error,
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }

                    Button(
                        onClick = if (uiState.isSessionRunning) onStop else onStart,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(54.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (uiState.isSessionRunning) {
                                MaterialTheme.colorScheme.error
                            } else {
                                MaterialTheme.colorScheme.primary
                            }
                        )
                    ) {
                        Text(if (uiState.isSessionRunning) "停止并保存" else "开始采集")
                    }
                }
            }

            if (uiState.isAnalyzingPending) {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceContainerLow
                    )
                ) {
                    Column(
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            if (uiState.analysisProgressText.isNotBlank()) {
                                uiState.analysisProgressText
                            } else {
                                "后台分析中..."
                            },
                            style = MaterialTheme.typography.bodySmall
                        )
                        if (uiState.analysisProgress > 0f) {
                            LinearProgressIndicator(
                                progress = { uiState.analysisProgress.coerceIn(0f, 1f) },
                                modifier = Modifier.fillMaxWidth()
                            )
                        } else {
                            LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                        }
                    }
                }
            }

            Text(
                uiState.statusMessage,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun RecordsScreen(
    modifier: Modifier = Modifier,
    uiState: MonitorUiState,
    onUploadPending: () -> Unit,
    onDeleteRecord: (String) -> Unit
) {
    var selectedRecordId by rememberSaveable { mutableStateOf<String?>(null) }
    val selectedRecord = uiState.records.firstOrNull { it.id == selectedRecordId }
    var deleteRecordId by rememberSaveable { mutableStateOf<String?>(null) }
    val pendingDelete = uiState.records.firstOrNull { it.id == deleteRecordId }

    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            SectionTitle(title = "记录列表", subtitle = "仅展示当前账号数据")
            Spacer(modifier = Modifier.height(8.dp))
            Button(
                onClick = onUploadPending,
                enabled = !uiState.isAnalyzingPending,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(if (uiState.isAnalyzingPending) "同步中..." else "同步")
            }
            if (uiState.isAnalyzingPending) {
                Spacer(modifier = Modifier.height(6.dp))
                if (uiState.analysisProgress > 0f) {
                    LinearProgressIndicator(
                        progress = { uiState.analysisProgress.coerceIn(0f, 1f) },
                        modifier = Modifier.fillMaxWidth()
                    )
                } else {
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                }
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    if (uiState.analysisProgressText.isNotBlank()) {
                        uiState.analysisProgressText
                    } else {
                        "服务端分析中..."
                    },
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
        if (uiState.records.isEmpty()) {
            item {
                EmptyStateCard(
                    title = "暂无记录",
                    description = "完成一次采集后，系统会自动生成分析记录。"
                )
            }
        } else {
            items(uiState.records) { item ->
                RecordCard(
                    item = item,
                    onClick = { selectedRecordId = item.id },
                    onDelete = { deleteRecordId = item.id }
                )
            }
        }
    }

    if (selectedRecord != null) {
        RecordDetailDialog(item = selectedRecord, onDismiss = { selectedRecordId = null })
    }

    if (pendingDelete != null) {
        AlertDialog(
            onDismissRequest = { deleteRecordId = null },
            title = { Text("删除记录") },
            text = { Text("确认删除该记录？删除后不可恢复。") },
            confirmButton = {
                TextButton(onClick = {
                    onDeleteRecord(pendingDelete.id)
                    deleteRecordId = null
                    if (selectedRecordId == pendingDelete.id) {
                        selectedRecordId = null
                    }
                }) { Text("确认删除") }
            },
            dismissButton = {
                TextButton(onClick = { deleteRecordId = null }) { Text("取消") }
            }
        )
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
        item { SectionTitle(title = "设置", subtitle = "账号管理与上传配置") }
        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("当前账号", style = MaterialTheme.typography.titleMedium)
                    Text("${uiState.currentAccount?.name} (${uiState.currentAccount?.id})")
                }
            }
        }
        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
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
            item { Text("历史账号", style = MaterialTheme.typography.titleMedium) }
            items(uiState.accounts) { account ->
                val isCurrent = uiState.currentAccount?.id == account.id
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .border(
                            width = if (isCurrent) 1.dp else 0.dp,
                            color = if (isCurrent) MaterialTheme.colorScheme.primary else Color.Transparent,
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
                "不同账号数据已隔离，上传地址可按机构系统配置。",
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

@Composable
private fun RecordCard(
    item: NystagmusRecord,
    onClick: () -> Unit,
    onDelete: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(
                    item.startedAt,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Medium
                )
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
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
                    AssistChip(
                        onClick = {},
                        label = { Text(if (item.analysisCompleted) "已分析" else "待分析") }
                    )
                    if (item.archivedOnServer) {
                        AssistChip(
                            onClick = {},
                            label = { Text("已归档") }
                        )
                    }
                    Text(
                        "点击查看详情",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }
            TextButton(
                onClick = onDelete
            ) {
                Text("删除", color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

@Composable
private fun RecordDetailDialog(
    item: NystagmusRecord,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("记录详情") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("时间：${item.startedAt}")
                Text("记录ID：${item.id}")
                Text("账号：${item.accountName} (${item.accountId})")
                Text("时长：${item.durationSec}s")
                Text("上传：${if (item.uploaded) "已上传" else "待上传"}")
                Text("分析：${if (item.analysisCompleted) "已分析" else "待分析"}")
                if (item.archivedOnServer) {
                    Text("服务端状态：已归档")
                }
                Text("结论：${if (item.analysisCompleted) item.summary else "待分析"}")
                Text("水平快相：${if (item.analysisCompleted) item.horizontalDirectionLabel else "-"}")
                Text("垂直快相：${if (item.analysisCompleted) item.verticalDirectionLabel else "-"}")
                Text("主频：${if (item.analysisCompleted) "${"%.2f".format(item.dominantFrequencyHz)} Hz" else "-"}")
                Text("SPV：${if (item.analysisCompleted) "${"%.2f".format(item.spvDegPerSec)} deg/s" else "-"}")
                SignalChart(
                    pitchSeries = item.pitchSeries,
                    yawSeries = item.yawSeries,
                    timestampsMs = item.timestampsMs
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    AssistChip(onClick = {}, label = { Text("Pitch") })
                    AssistChip(onClick = {}, label = { Text("Yaw") })
                    AssistChip(
                        onClick = {},
                        label = { Text("样本 ${maxOf(item.pitchSeries.size, item.yawSeries.size)}") }
                    )
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("关闭") } }
    )
}

@Composable
private fun SignalChart(
    pitchSeries: List<Double>,
    yawSeries: List<Double>,
    timestampsMs: List<Long>
) {
    val sampleCount = maxOf(pitchSeries.size, yawSeries.size)
    if (sampleCount < 2) {
        Text(
            "当前记录采样点不足，无法绘制曲线。",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        return
    }

    val pitchColor = MaterialTheme.colorScheme.primary
    val yawColor = MaterialTheme.colorScheme.tertiary
    val axisColor = MaterialTheme.colorScheme.outline
    val allValues = buildList {
        addAll(pitchSeries)
        addAll(yawSeries)
    }.filter { !it.isNaN() }
    val minValue = allValues.minOrNull() ?: -1.0
    val maxValue = allValues.maxOrNull() ?: 1.0
    val span = (maxValue - minValue).takeIf { it > 1e-6 } ?: 1.0
    val scrollState = rememberScrollState()
    val chartWidthDp = max(320, sampleCount * 3).dp

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(scrollState)
    ) {
        Canvas(
            modifier = Modifier
                .height(210.dp)
                .width(chartWidthDp)
        ) {
            val leftPadding = 8f
            val rightPadding = 8f
            val topPadding = 8f
            val bottomPadding = 8f
            val chartWidth = size.width - leftPadding - rightPadding
            val chartHeight = size.height - topPadding - bottomPadding
            if (chartWidth <= 0f || chartHeight <= 0f) return@Canvas

            fun mapY(value: Double): Float {
                val normalized = ((value - minValue) / span).toFloat()
                return topPadding + (1f - normalized) * chartHeight
            }

            fun buildPath(values: List<Double>): Path {
                val path = Path()
                if (values.isEmpty()) return path
                var hasStarted = false
                values.forEachIndexed { index, value ->
                    if (value.isNaN()) {
                        hasStarted = false
                        return@forEachIndexed
                    }
                    val x = leftPadding + (index.toFloat() / (values.lastIndex.coerceAtLeast(1))) * chartWidth
                    val y = mapY(value)
                    if (!hasStarted) {
                        path.moveTo(x, y)
                        hasStarted = true
                    } else {
                        path.lineTo(x, y)
                    }
                }
                return path
            }

            val midY = mapY((minValue + maxValue) * 0.5)
            drawLine(
                color = axisColor,
                start = Offset(leftPadding, midY),
                end = Offset(size.width - rightPadding, midY),
                strokeWidth = 1.5f
            )
            drawPath(path = buildPath(pitchSeries), color = pitchColor, style = Stroke(width = 3f))
            drawPath(path = buildPath(yawSeries), color = yawColor, style = Stroke(width = 3f))
        }
    }

    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("Pitch", color = pitchColor, style = MaterialTheme.typography.labelSmall)
        Text("Yaw", color = yawColor, style = MaterialTheme.typography.labelSmall)
        if (timestampsMs.size >= 2) {
            val durationSec = ((timestampsMs.last() - timestampsMs.first()) / 1000.0).coerceAtLeast(0.0)
            Text("时长 ${"%.1f".format(durationSec)}s", style = MaterialTheme.typography.labelSmall)
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
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(
                description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
