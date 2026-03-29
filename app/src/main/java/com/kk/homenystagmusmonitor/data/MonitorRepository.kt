package com.kk.homenystagmusmonitor.data

import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

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
    val suspectNystagmus: Boolean,
    val uploaded: Boolean
)

interface MonitorRepository {
    suspend fun loginOrCreateAccount(id: String, name: String): PatientAccount
    suspend fun getAllAccounts(): List<PatientAccount>
    suspend fun addMockRecord(account: PatientAccount): NystagmusRecord
    suspend fun uploadPending(accountId: String, serverUrl: String): Int
    suspend fun getRecordsByAccount(accountId: String): List<NystagmusRecord>
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

    override suspend fun addMockRecord(account: PatientAccount): NystagmusRecord {
        val accountRecords = recordsByAccount.getOrPut(account.id) { mutableListOf() }
        val now = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date())
        val record = NystagmusRecord(
            id = "rec_${System.currentTimeMillis()}",
            accountId = account.id,
            accountName = account.name,
            startedAt = now,
            durationSec = 20,
            suspectNystagmus = (accountRecords.size % 2 == 0),
            uploaded = false
        )
        accountRecords.add(0, record)
        return record
    }

    override suspend fun uploadPending(accountId: String, serverUrl: String): Int {
        if (serverUrl.isBlank()) return 0
        val accountRecords = recordsByAccount[accountId] ?: return 0
        delay(700)
        var count = 0
        for (idx in accountRecords.indices) {
            val item = accountRecords[idx]
            if (!item.uploaded) {
                accountRecords[idx] = item.copy(uploaded = true)
                count++
            }
        }
        return count
    }

    override suspend fun getRecordsByAccount(accountId: String): List<NystagmusRecord> {
        return recordsByAccount[accountId]?.toList().orEmpty()
    }
}

object AppGraph {
    val repository: MonitorRepository by lazy { InMemoryMonitorRepository() }
}
