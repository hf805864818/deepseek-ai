package com.openminis.app.data

import android.net.Uri
import android.util.Log
import com.openminis.app.auth.GoogleDriveOAuthManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * Google Drive file metadata returned by the Drive REST API v3.
 */
data class GoogleDriveFile(
    val id: String,
    val name: String,
    val mimeType: String,
    val modifiedTime: String? = null,
    val size: Long? = null,
    val md5Checksum: String? = null,
)

/**
 * Google Drive REST API v3 client. Singleton object that delegates token
 * retrieval to a [GoogleDriveOAuthManager]. Call [configure] once before
 * using any method (typically from [GoogleDriveSyncManager]).
 *
 * Uses the multipart upload protocol for file creation and the `alt=media`
 * parameter for downloads. All methods are `suspend` and run on [Dispatchers.IO].
 */
object GoogleDriveAPI {
    private const val TAG = "GoogleDriveAPI"
    private const val BASE_URL = "https://www.googleapis.com/drive/v3"
    private const val UPLOAD_URL = "https://www.googleapis.com/upload/drive/v3"

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .build()

    private var oauthManager: GoogleDriveOAuthManager? = null

    /**
     * Configure the singleton with the OAuth manager used to obtain
     * access tokens. Called by [GoogleDriveSyncManager] before Drive operations.
     */
    fun configure(oauth: GoogleDriveOAuthManager) {
        oauthManager = oauth
    }

    private suspend fun accessToken(): String {
        return oauthManager?.validAccessToken()
            ?: throw IllegalStateException("GoogleDriveAPI not configured with OAuth manager")
    }

    /**
     * Create a folder in Google Drive. Returns the new file ID.
     * If [parentId] is provided the folder is created inside that parent.
     */
    suspend fun createFolder(name: String, parentId: String? = null): String = withContext(Dispatchers.IO) {
        val token = accessToken()
        val metadata = JSONObject().apply {
            put("name", name)
            put("mimeType", "application/vnd.google-apps.folder")
            if (parentId != null) put("parents", org.json.JSONArray().put(parentId))
        }
        val request = Request.Builder()
            .url("$BASE_URL/files?fields=id")
            .post(metadata.toString().toRequestBody("application/json; charset=utf-8".toMediaType()))
            .addHeader("Authorization", "Bearer $token")
            .build()
        val response = httpClient.newCall(request).execute()
        val body = response.body?.string() ?: ""
        response.close()
        if (response.code !in 200..299) {
            throw IOException("createFolder failed: ${response.code} $body")
        }
        JSONObject(body).getString("id")
    }

    /**
     * Find a folder by name in the user's Drive root, or create it if
     * it does not exist. Returns the folder file ID.
     */
    suspend fun findOrCreateFolder(name: String): String = withContext(Dispatchers.IO) {
        val token = accessToken()
        val query = Uri.encode(
            "name='$name' and mimeType='application/vnd.google-apps.folder' and trashed=false",
        )
        val request = Request.Builder()
            .url("$BASE_URL/files?q=$query&fields=files(id,name)")
            .addHeader("Authorization", "Bearer $token")
            .build()
        val response = httpClient.newCall(request).execute()
        val body = response.body?.string() ?: ""
        response.close()
        if (response.code == 403) {
            // 403 on search may mean the folder exists but we can't search for it.
            // Fall back to creating it directly (create also returns existing folder ID
            // if one with the same name already exists in the same location).
            Log.w(TAG, "findOrCreateFolder search returned 403, falling back to create")
            return@withContext createFolder(name)
        } else if (response.code !in 200..299) {
            throw IOException("findOrCreateFolder search failed: ${response.code} $body")
        }
        val files = JSONObject(body).optJSONArray("files")
        if (files != null && files.length() > 0) {
            files.getJSONObject(0).getString("id")
        } else {
            createFolder(name)
        }
    }

    /**
     * Upload a file to Google Drive using multipart upload. Returns the
     * new file ID.
     */
    suspend fun uploadFile(name: String, data: ByteArray, parentId: String, mimeType: String): String =
        withContext(Dispatchers.IO) {
            val token = accessToken()
            val metadata = JSONObject().apply {
                put("name", name)
                put("parents", org.json.JSONArray().put(parentId))
            }
            val metadataPart = MultipartBody.Part.createFormData(
                "metadata",
                null,
                metadata.toString().toRequestBody("application/json; charset=utf-8".toMediaType()),
            )
            val mediaPart = MultipartBody.Part.createFormData(
                "media",
                name,
                data.toRequestBody(mimeType.toMediaType()),
            )
            val multipartBody = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addPart(metadataPart)
                .addPart(mediaPart)
                .build()
            val request = Request.Builder()
                .url("$UPLOAD_URL/files?uploadType=multipart&fields=id")
                .post(multipartBody)
                .addHeader("Authorization", "Bearer $token")
                .build()
            val response = httpClient.newCall(request).execute()
            val body = response.body?.string() ?: ""
            response.close()
            if (response.code !in 200..299) {
                throw IOException("uploadFile failed: ${response.code} $body")
            }
            JSONObject(body).getString("id")
        }

    /**
     * Download the content of a file by ID. Returns the raw bytes.
     */
    suspend fun downloadFile(fileId: String): ByteArray = withContext(Dispatchers.IO) {
        val token = accessToken()
        val request = Request.Builder()
            .url("$BASE_URL/files/$fileId?alt=media")
            .addHeader("Authorization", "Bearer $token")
            .build()
        val response = httpClient.newCall(request).execute()
        val bytes = response.body?.bytes()
        val code = response.code
        response.close()
        if (code !in 200..299 || bytes == null) {
            throw IOException("downloadFile failed: $code")
        }
        bytes
    }

    /**
     * List files in a parent folder (or in the Drive root when [parentId]
     * is null). Returns a list of [GoogleDriveFile] entries.
     */
    suspend fun listFiles(parentId: String?, pageSize: Int = 100): List<GoogleDriveFile> =
        withContext(Dispatchers.IO) {
            val token = accessToken()
            val queryParts = mutableListOf("trashed=false")
            if (parentId != null) {
                queryParts.add("'$parentId' in parents")
            }
            val query = Uri.encode(queryParts.joinToString(" and "))
            val fields = Uri.encode("files(id,name,mimeType,modifiedTime,size,md5Checksum)")
            val request = Request.Builder()
                .url("$BASE_URL/files?q=$query&pageSize=$pageSize&fields=$fields")
                .addHeader("Authorization", "Bearer $token")
                .build()
            val response = httpClient.newCall(request).execute()
            val body = response.body?.string() ?: ""
            response.close()
            if (response.code !in 200..299) {
                throw IOException("listFiles failed: ${response.code} $body")
            }
            val filesArray = JSONObject(body).optJSONArray("files")
                ?: return@withContext emptyList()
            val result = mutableListOf<GoogleDriveFile>()
            for (i in 0 until filesArray.length()) {
                val obj = filesArray.getJSONObject(i)
                result.add(parseFile(obj))
            }
            result
        }

    /**
     * Permanently delete a file by ID.
     */
    suspend fun deleteFile(fileId: String) = withContext(Dispatchers.IO) {
        val token = accessToken()
        val request = Request.Builder()
            .url("$BASE_URL/files/$fileId")
            .delete()
            .addHeader("Authorization", "Bearer $token")
            .build()
        val response = httpClient.newCall(request).execute()
        val code = response.code
        response.close()
        if (code !in 200..299) {
            throw IOException("deleteFile failed: $code")
        }
        Unit
    }

    /**
     * Get metadata for a single file by ID.
     */
    suspend fun getFileMetadata(fileId: String): GoogleDriveFile = withContext(Dispatchers.IO) {
        val token = accessToken()
        val fields = Uri.encode("id,name,mimeType,modifiedTime,size,md5Checksum")
        val request = Request.Builder()
            .url("$BASE_URL/files/$fileId?fields=$fields")
            .addHeader("Authorization", "Bearer $token")
            .build()
        val response = httpClient.newCall(request).execute()
        val body = response.body?.string() ?: ""
        response.close()
        if (response.code !in 200..299) {
            throw IOException("getFileMetadata failed: ${response.code} $body")
        }
        parseFile(JSONObject(body))
    }

    private fun parseFile(obj: JSONObject): GoogleDriveFile {
        return GoogleDriveFile(
            id = obj.optString("id"),
            name = obj.optString("name"),
            mimeType = obj.optString("mimeType"),
            modifiedTime = obj.optString("modifiedTime").ifEmpty { null },
            size = obj.optString("size").ifEmpty { null }?.toLongOrNull(),
            md5Checksum = obj.optString("md5Checksum").ifEmpty { null },
        )
    }
}
