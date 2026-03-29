package com.kk.homenystagmusmonitor.data

import android.content.Context
import android.content.SharedPreferences

data class LastLogin(
    val accountId: String,
    val accountName: String
)

interface SessionStore {
    fun getLastLogin(): LastLogin?
    fun saveLastLogin(account: PatientAccount)
    fun getServerUrl(): String?
    fun saveServerUrl(url: String)
}

class SharedPrefsSessionStore(context: Context) : SessionStore {
    private val prefs: SharedPreferences = context.getSharedPreferences(
        PREFS_NAME,
        Context.MODE_PRIVATE
    )

    override fun getLastLogin(): LastLogin? {
        val id = prefs.getString(KEY_LAST_ACCOUNT_ID, null)?.trim().orEmpty()
        val name = prefs.getString(KEY_LAST_ACCOUNT_NAME, null)?.trim().orEmpty()
        if (id.isEmpty() || name.isEmpty()) return null
        return LastLogin(accountId = id, accountName = name)
    }

    override fun saveLastLogin(account: PatientAccount) {
        prefs.edit()
            .putString(KEY_LAST_ACCOUNT_ID, account.id)
            .putString(KEY_LAST_ACCOUNT_NAME, account.name)
            .apply()
    }

    override fun getServerUrl(): String? {
        return prefs.getString(KEY_SERVER_URL, null)?.trim()?.takeIf { it.isNotEmpty() }
    }

    override fun saveServerUrl(url: String) {
        prefs.edit()
            .putString(KEY_SERVER_URL, url.trim())
            .apply()
    }

    private companion object {
        private const val PREFS_NAME = "monitor_session_prefs"
        private const val KEY_LAST_ACCOUNT_ID = "last_account_id"
        private const val KEY_LAST_ACCOUNT_NAME = "last_account_name"
        private const val KEY_SERVER_URL = "server_url"
    }
}
