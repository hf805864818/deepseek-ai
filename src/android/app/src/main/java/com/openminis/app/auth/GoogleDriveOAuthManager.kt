package com.openminis.app.auth

import android.content.Context
import android.net.Uri
import android.util.Log
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Google Drive OAuth manager for backup/sync. Uses the Android (installed
 * application) client type — PKCE only, no client_secret. Mirrors the
 * authorization flow of [GeminiOAuthManager] (access_type=offline +
 * prompt=consent for a refreshable consent grant) but targets the
 * drive.file scope instead of cloud-platform.
 *
 * The base [OAuthManager.buildTokenParams] already skips `client_secret`
 * when [clientSecret] is null, so the token exchange request correctly
 * omits it for this Android-type client. No override of `exchangeCode`
 * is needed — the base implementation handles PKCE-only flows.
 *
 * `isAuthenticated()` is inherited from [OAuthManager] and checks whether
 * a stored access token exists.
 */
class GoogleDriveOAuthManager(context: Context, instanceId: String) : OAuthManager(context, instanceId) {
    companion object {
        private const val TAG = "GoogleDriveOAuth"

        /** Factory for the sync use-case — single shared instance id. */
        fun forSync(context: Context) = GoogleDriveOAuthManager(context, "gdrive")
    }

    override val authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    override val tokenURL = "https://oauth2.googleapis.com/token"
    override val clientId = "483538693797-hs0c9jrjg9b4s0pcj5hphrv20mrvf3d7.apps.googleusercontent.com"
    // Desktop app client type — requires client_secret for token exchange.
    // Changed from Android type to Desktop app type to support localhost redirect.
    // The base OAuthManager.buildTokenParams includes client_secret
    // when it is non-null, which is required for Desktop app clients.
    override val clientSecret: String? = "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"
    override val callbackPort = 8087
    override val redirectPath = "/oauth2callback"
    override val scopes = "https://www.googleapis.com/auth/drive.appdata"

    override fun buildAuthorizationUrl(): String {
        val (_, challenge) = generatePKCE()
        val state = generateState()
        return "$authURL?" + listOf(
            "client_id=$clientId",
            "redirect_uri=${Uri.encode(redirectUri)}",
            "response_type=code",
            "scope=${Uri.encode(scopes)}",
            "state=$state",
            "code_challenge=$challenge",
            "code_challenge_method=S256",
            "access_type=offline",
            "prompt=consent",
        ).joinToString("&")
    }

    /** Authenticated user email, fetched after token exchange. */
    var email: String?
        get() = loadOAuthString("email")
        private set(value) { value?.let { saveOAuthString("email", it) } }

    override suspend fun onTokensReceived(json: JSONObject) {
        fetchUserEmail()
    }

    private suspend fun fetchUserEmail() {
        val token = validAccessToken() ?: return
        try {
            val conn = URL("https://www.googleapis.com/oauth2/v1/userinfo").openConnection() as HttpURLConnection
            conn.setRequestProperty("Authorization", "Bearer $token")
            if (conn.responseCode == 200) {
                val body = conn.inputStream.bufferedReader().readText()
                email = JSONObject(body).optString("email")
            }
            conn.disconnect()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to fetch email", e)
        }
    }
}
