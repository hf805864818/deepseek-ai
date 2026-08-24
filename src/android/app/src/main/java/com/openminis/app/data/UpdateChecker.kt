package com.openminis.app.data

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.openminis.app.BuildConfig
import com.openminis.app.logging.AppLogger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.concurrent.TimeUnit

/**
 * Checks GitHub releases for an APK newer than [BuildConfig.VERSION_NAME] and
 * coordinates download → install. iOS has no equivalent (sideloading is not
 * permitted) so this is Android-only.
 *
 * Comparison strategy: strip a leading `v` from `tag_name`, then split both
 * the tag and the local versionName on `.` and compare numerically component
 * by component. A tag like `v1.0.1` beats local `1.0.0`; `v1.0.0-rc1` beats
 * `1.0.0` because the suffix sorts higher under string fallback.
 */
object UpdateChecker {

    private const val TAG = "UpdateChecker"
    private const val OWNER = "vbox-Ai"
    // T133: the public repo is vbox-Ai/Lobster-APP.
    // Previously pointed at OpenMinis/MinisApp, which is the private dev
    // mirror — every API call 404'd, which we mistranslated as "no release
    // published". The 0.1-preview release is published as a prerelease on
    // vbox-Ai/Lobster-APP with a MinisApp-*.apk asset attached.
    private const val REPO = "Lobster-APP"
    private const val DOWNLOAD_FILENAME = "minis-update.apk"
    /**
     * Sub-directory of `filesDir` where we stage downloaded update APKs. We
     * moved off `cacheDir/shared/` (the original location) so the OS can't
     * evict a freshly-downloaded APK between the moment we hand the user off
     * to "install unknown apps" settings and the moment they return — the
     * eviction was a contributing factor to the "re-download after grant"
     * bug. See [PendingUpdateStore]. Exposed via `file_provider_paths.xml`
     * `<files-path name="updates" path="updates/" />`.
     */
    private const val UPDATES_DIR = "updates"
    internal const val PREFS_NAME = "update_checker"
    private const val KEY_LAST_CHECK = "last_check_ms"
    private const val KEY_HAS_PENDING = "has_pending"
    private const val KEY_PENDING_VERSION = "pending_version"
    private const val KEY_PENDING_APK_URL = "pending_apk_url"
    private const val KEY_PENDING_SIZE = "pending_size"
    private const val KEY_PENDING_CHANGELOG = "pending_changelog"
    private const val KEY_PENDING_TAG = "pending_tag"
    private const val KEY_PENDING_RELEASE_NAME = "pending_release_name"
    private const val KEY_DISMISSED_VERSION = "dismissed_version"
    private const val AUTO_CHECK_INTERVAL_MS = 24L * 60L * 60L * 1000L // 24 hours

    private var prefs: SharedPreferences? = null

    private fun requirePrefs(context: Context): SharedPreferences {
        prefs?.let { return it }
        val p = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs = p
        return p
    }

    /**
     * Whether there is a pending update that the user has not dismissed.
     * Drives the red dot badge on the Settings → About row.
     */
    fun hasUnreadUpdate(context: Context): Boolean {
        val p = requirePrefs(context)
        if (!p.getBoolean(KEY_HAS_PENDING, false)) return false
        val pending = p.getString(KEY_PENDING_VERSION, null) ?: return false
        val dismissed = p.getString(KEY_DISMISSED_VERSION, null)
        return pending != dismissed
    }

    /** Returns the pending update info, or null. */
    fun getPendingUpdate(context: Context): CheckResult.UpdateAvailable? {
        val p = requirePrefs(context)
        if (!p.getBoolean(KEY_HAS_PENDING, false)) return null
        val tag = p.getString(KEY_PENDING_TAG, null) ?: return null
        val version = p.getString(KEY_PENDING_VERSION, null) ?: return null
        val apkUrl = p.getString(KEY_PENDING_APK_URL, null) ?: return null
        return CheckResult.UpdateAvailable(
            tagName = tag,
            versionName = version,
            releaseName = p.getString(KEY_PENDING_RELEASE_NAME, "") ?: "",
            changelog = p.getString(KEY_PENDING_CHANGELOG, "") ?: "",
            apkUrl = apkUrl,
            apkSizeBytes = p.getLong(KEY_PENDING_SIZE, 0L),
        )
    }

    /** Marks a version as dismissed so the red dot goes away. */
    fun dismissUpdate(context: Context, versionName: String) {
        requirePrefs(context).edit()
            .putString(KEY_DISMISSED_VERSION, versionName)
            .apply()
    }

    /**
     * Performs a silent background check if enough time has passed.
     * Updates persisted state only — does not show any UI.
     * Safe to call from onCreate / onStart.
     */
    fun checkSilentlyIfNeeded(context: Context) {
        val p = requirePrefs(context)
        val lastCheck = p.getLong(KEY_LAST_CHECK, 0L)
        if (lastCheck > 0 && System.currentTimeMillis() - lastCheck < AUTO_CHECK_INTERVAL_MS) {
            return // Throttled — skip.
        }
        val appContext = context.applicationContext
        // Fire and forget on the app-level IO scope.
        appScope.launch {
            val result = check()
            val now = System.currentTimeMillis()
            val editor = p.edit()
            editor.putLong(KEY_LAST_CHECK, now)
            when (result) {
                is CheckResult.UpdateAvailable -> {
                    editor.putBoolean(KEY_HAS_PENDING, true)
                    editor.putString(KEY_PENDING_TAG, result.tagName)
                    editor.putString(KEY_PENDING_VERSION, result.versionName)
                    editor.putString(KEY_PENDING_APK_URL, result.apkUrl)
                    editor.putLong(KEY_PENDING_SIZE, result.apkSizeBytes)
                    editor.putString(KEY_PENDING_CHANGELOG, result.changelog)
                    editor.putString(KEY_PENDING_RELEASE_NAME, result.releaseName)
                }
                CheckResult.UpToDate -> {
                    editor.putBoolean(KEY_HAS_PENDING, false)
                    editor.remove(KEY_PENDING_TAG)
                    editor.remove(KEY_PENDING_VERSION)
                    editor.remove(KEY_PENDING_APK_URL)
                    editor.remove(KEY_PENDING_SIZE)
                    editor.remove(KEY_PENDING_CHANGELOG)
                    editor.remove(KEY_PENDING_RELEASE_NAME)
                }
                else -> {
                    // Don't clear pending state on transient errors.
                }
            }
            editor.apply()
        }
    }

    sealed class CheckResult {
        data class UpdateAvailable(
            val tagName: String,
            val versionName: String,
            val releaseName: String,
            val changelog: String,
            val apkUrl: String,
            val apkSizeBytes: Long,
        ) : CheckResult()
        data object UpToDate : CheckResult()
        // The repo has zero non-draft releases (or 404'd entirely).
        data object NoReleaseAvailable : CheckResult()
        // A newer release exists but no .apk asset was attached. Distinct
        // from NoReleaseAvailable so the UI can say "newer release exists,
        // but it didn't ship an APK" instead of misleading "no release yet".
        data class NoApkAsset(val tagName: String) : CheckResult()
        data class Error(val message: String) : CheckResult()
        // GitHub returned 403 / 451 — usually a geo-block or rate-limit in CN
        // without a VPN. UI surfaces a hint with a clickable Releases link.
        data object Forbidden : CheckResult()
        // DNS / connect / read timeout — network unreachable. UI nudges the
        // user to check connectivity and retry.
        data object NetworkUnreachable : CheckResult()
    }

    sealed class DownloadResult {
        data class Success(val file: File) : DownloadResult()
        data class Error(val message: String) : DownloadResult()
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()

    /** App-wide scope for fire-and-forget background work (silent checks). */
    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * Hit `repos/{owner}/{repo}/releases` (the list endpoint, NOT
     * `/releases/latest`), pick the highest-version non-draft release that
     * carries an APK asset, and decide whether the user should upgrade.
     *
     * T133: switched from `/releases/latest` to `/releases` because
     * `/releases/latest` excludes prereleases by GitHub design — our
     * `0.1 preview` release is flagged as a prerelease, so the old endpoint
     * 404'd and the UI falsely showed "No release published yet". The list
     * endpoint includes prereleases; we filter drafts client-side.
     *
     * All network work happens on [Dispatchers.IO]; safe to call from any
     * coroutine scope.
     */
    suspend fun check(): CheckResult = withContext<CheckResult>(Dispatchers.IO) {
        val url = "https://api.github.com/repos/$OWNER/$REPO/releases?per_page=30"
        AppLogger.info(TAG, "GET $url (local=${BuildConfig.VERSION_NAME})")
        try {
            // 先直连官方 API；若网络不通（403/超时/连接失败）再自动切镜像重试。
            val direct = executeReleases(url)
            when (direct) {
                is ReleaseResponse.Success -> {
                    return@withContext processReleaseResponse(direct.body)
                }
                is ReleaseResponse.Error -> {
                    // 404=无 release；403/451=被墙或限流，此时尝试镜像再判断
                    if (direct.code == 404) return@withContext CheckResult.NoReleaseAvailable
                    if (direct.code == 403 || direct.code == 451) {
                        val mirrored = GitHubMirrorManager.mirrorUrl(url)
                        val m = executeReleases(mirrored)
                        when (m) {
                            is ReleaseResponse.Success -> return@withContext processReleaseResponse(m.body)
                            else -> return@withContext CheckResult.Forbidden
                        }
                    }
                    AppLogger.info(TAG, "直接访问失败(code=${direct.code})，切换镜像重试")
                    val mirrored = GitHubMirrorManager.mirrorUrl(url)
                    val m = executeReleases(mirrored)
                    when (m) {
                        is ReleaseResponse.Success -> return@withContext processReleaseResponse(m.body)
                        is ReleaseResponse.Error ->
                            if (m.code == 404) return@withContext CheckResult.NoReleaseAvailable
                            else return@withContext CheckResult.NetworkUnreachable
                        else -> return@withContext CheckResult.NetworkUnreachable
                    }
                }
                ReleaseResponse.NetworkError -> {
                    AppLogger.info(TAG, "直连网络错误，切换镜像重试")
                    val mirrored = GitHubMirrorManager.mirrorUrl(url)
                    val m = executeReleases(mirrored)
                    when (m) {
                        is ReleaseResponse.Success -> return@withContext processReleaseResponse(m.body)
                        is ReleaseResponse.Error ->
                            if (m.code == 404) return@withContext CheckResult.NoReleaseAvailable
                            else return@withContext CheckResult.NetworkUnreachable
                        else -> return@withContext CheckResult.NetworkUnreachable
                    }
                }
            }
            // Unreachable, but required to give the try block a CheckResult-
            // typed tail expression so withContext infers CheckResult (not Unit).
            @Suppress("UNREACHABLE_CODE")
            return@withContext CheckResult.NetworkUnreachable
        } catch (e: Exception) {
            AppLogger.warning(TAG, "check() 异常: ${e.message}")
            return@withContext CheckResult.NetworkUnreachable
        }
    }

    private sealed class ReleaseResponse {
        data class Success(val body: String) : ReleaseResponse()
        data class Error(val code: Int, val message: String) : ReleaseResponse()
        object NetworkError : ReleaseResponse()
    }

    /** 执行一次 releases 请求并分类结果。 */
    private fun executeReleases(targetUrl: String): ReleaseResponse {
        return try {
            val req = Request.Builder()
                .url(targetUrl)
                .header("Accept", "application/vnd.github+json")
                .header("X-GitHub-Api-Version", "2022-11-28")
                .header("User-Agent", "MinisApp/1.0")
                .build()
            client.newCall(req).execute().use { resp ->
                if (resp.isSuccessful) {
                    ReleaseResponse.Success(resp.body?.string() ?: "")
                } else {
                    ReleaseResponse.Error(resp.code, "HTTP ${resp.code}")
                }
            }
        } catch (e: Exception) {
            AppLogger.warning(TAG, "releases 请求失败: $targetUrl → ${e.message}")
            ReleaseResponse.NetworkError
        }
    }

    /** 解析已成功取得的 releases JSON body；若不是数组或为空则视为无 release。 */
    private suspend fun processReleaseResponse(body: String): CheckResult = withContext(Dispatchers.IO) {
        try {
            val arr = runCatching { JSONArray(body) }.getOrNull()
            if (arr == null || arr.length() == 0) {
                AppLogger.info(TAG, "releases list empty")
                return@withContext CheckResult.NoReleaseAvailable
            }

                // Build a list of non-draft releases. GitHub already returns
                // them sorted by created_at desc, but we re-sort by parsed
                // version number to be robust against odd ordering.
                data class ReleaseInfo(
                    val tagName: String,
                    val versionName: String,
                    val releaseName: String,
                    val changelog: String,
                    val isPrerelease: Boolean,
                    val apkUrl: String?,
                    val apkSize: Long,
                )

                val candidates = mutableListOf<ReleaseInfo>()
                for (i in 0 until arr.length()) {
                    val r = arr.optJSONObject(i) ?: continue
                    if (r.optBoolean("draft", false)) continue
                    val tag = r.optString("tag_name")
                    if (tag.isEmpty()) continue
                    val (apkUrl, apkSize) = findApkAsset(r.optJSONArray("assets"))
                    candidates += ReleaseInfo(
                        tagName = tag,
                        versionName = normalizeTag(tag),
                        releaseName = r.optString("name").ifEmpty { tag },
                        changelog = r.optString("body", ""),
                        isPrerelease = r.optBoolean("prerelease", false),
                        apkUrl = apkUrl,
                        apkSize = apkSize,
                    )
                }
                AppLogger.info(
                    TAG,
                    "non-draft releases=${candidates.size} (apk-bearing=${candidates.count { it.apkUrl != null }})",
                )
                if (candidates.isEmpty()) {
                    return@withContext CheckResult.NoReleaseAvailable
                }

                // [T-android-updatechecker-localver-normalize] Normalize the
                // LOCAL version the same way remote tags are (normalizeTag),
                // otherwise the comparison is asymmetric: remote "v0.11-preview"
                // becomes "0.11" but local "0.11-preview" stays raw, and
                // compareVersions("0.11","0.11-preview") puts "" before
                // "preview" in the 3rd component → remote judged OLDER → the
                // user is told they're up to date when they're actually on the
                // matching version (and a real newer "0.12-preview" → "0.12"
                // still compares greater, so updates still surface).
                val localVer = normalizeTag(BuildConfig.VERSION_NAME)
                // Highest version we've seen at all (used for the "release
                // exists but is older or equal" → UpToDate decision and for
                // logging).
                val highest = candidates.maxWithOrNull(
                    compareBy { compareVersions(it.versionName, "0") },
                ) ?: candidates.first()
                AppLogger.info(
                    TAG,
                    "highest-published tag=${highest.tagName} parsed=${highest.versionName} prerelease=${highest.isPrerelease} apk=${highest.apkUrl != null}",
                )

                // First APK-bearing release with version > local. We pick the
                // highest such release so a stale older APK never shadows a
                // newer non-APK preview.
                val upgradeCandidate = candidates
                    .filter { it.apkUrl != null }
                    .filter { compareVersions(it.versionName, localVer) > 0 }
                    .maxWithOrNull(compareBy { compareVersions(it.versionName, "0") })

                if (upgradeCandidate != null) {
                    AppLogger.info(
                        TAG,
                        "Update available: $localVer → ${upgradeCandidate.versionName} (${upgradeCandidate.tagName})",
                    )
                    return@withContext CheckResult.UpdateAvailable(
                        tagName = upgradeCandidate.tagName,
                        versionName = upgradeCandidate.versionName,
                        releaseName = upgradeCandidate.releaseName,
                        changelog = upgradeCandidate.changelog,
                        apkUrl = upgradeCandidate.apkUrl!!,
                        apkSizeBytes = upgradeCandidate.apkSize,
                    )
                }

                // No newer-with-APK candidate exists. Decide between three
                // remaining states:
                //   1. Highest release ≤ local version → UpToDate.
                //   2. Highest release > local but no APK in the listing →
                //      NoApkAsset (mention the tag so the user can grab the
                //      release manually if they really want).
                //   3. Otherwise (all releases ≤ local) → UpToDate as well.
                val highestVsLocal = compareVersions(highest.versionName, localVer)
                if (highestVsLocal > 0 && highest.apkUrl == null) {
                    AppLogger.info(
                        TAG,
                        "Release ${highest.tagName} > local but no APK asset",
                    )
                    return@withContext CheckResult.NoApkAsset(highest.tagName)
                }

                AppLogger.info(TAG, "Up to date: local=$localVer highest=${highest.versionName}")
                CheckResult.UpToDate
            } catch (e: UnknownHostException) {
                AppLogger.error(TAG, "check failed: UnknownHostException: ${e.message}")
                CheckResult.NetworkUnreachable
            } catch (e: ConnectException) {
                AppLogger.error(TAG, "check failed: ConnectException: ${e.message}")
                CheckResult.NetworkUnreachable
            } catch (e: SocketTimeoutException) {
                AppLogger.error(TAG, "check failed: SocketTimeoutException: ${e.message}")
                CheckResult.NetworkUnreachable
            } catch (e: IOException) {
                // Catch-all for okhttp connection plumbing (e.g.
                // "failed to connect", SSL handshake errors).
                AppLogger.error(TAG, "check failed: ${e.javaClass.simpleName}: ${e.message}")
                CheckResult.NetworkUnreachable
            } catch (e: Exception) {
                AppLogger.error(TAG, "check failed: ${e.javaClass.simpleName}: ${e.message}")
                CheckResult.Error(e.message ?: e.javaClass.simpleName)
            }
        }

    /** Public so UI can deep-link users to manual download when GitHub is blocked. */
    const val RELEASES_URL: String = "https://github.com/vbox-Ai/Lobster-APP/releases"

    /** Returns (downloadUrl, sizeBytes) for the first .apk asset, or (null, 0). */
    private fun findApkAsset(assets: JSONArray?): Pair<String?, Long> {
        if (assets == null) return null to 0L
        for (i in 0 until assets.length()) {
            val a = assets.optJSONObject(i) ?: continue
            val name = a.optString("name").lowercase()
            if (name.endsWith(".apk")) {
                val u = a.optString("browser_download_url").ifEmpty { null }
                if (u != null) return u to a.optLong("size", 0)
            }
        }
        return null to 0L
    }

    /**
     * Strip the leading `v` and any `-preview` / `-rc1` / etc. trailing
     * label so the numeric comparator keeps `0.1` and `0.1-preview`
     * treated as equivalent. Without this, "0.1 (local) vs 0.1-preview
     * (remote)" reported the remote as newer because the trailing token
     * fell into string comparison.
     */
    private fun normalizeTag(tag: String): String {
        val trimmed = tag.trim().removePrefix("v").removePrefix("V")
        // "0.1-preview" → "0.1"; "0.1.0" → "0.1.0"; "1.2.3-rc1" → "1.2.3"
        val dashIdx = trimmed.indexOf('-')
        return if (dashIdx > 0) trimmed.substring(0, dashIdx) else trimmed
    }

    /**
     * Stream the APK from [url] into `${cacheDir}/shared/minis-update.apk`,
     * surfacing progress (0..1) through [onProgress] roughly every 64 KiB.
     * Returns the on-disk [File] on success so the caller can hand it to
     * [installApk]. The path is intentionally inside `shared/` because that's
     * the only sub-directory of cacheDir already exposed by FileProvider in
     * `file_provider_paths.xml`.
     */
    suspend fun download(
        context: Context,
        url: String,
        versionName: String? = null,
        onProgress: (Float) -> Unit = {},
    ): DownloadResult = withContext(Dispatchers.IO) {
        try {
            // Stage under filesDir (NOT cacheDir) so the OS doesn't evict
            // the APK mid-flow while the user is in system Settings granting
            // install permission — that eviction caused the "re-download
            // after grant" regression (T-android-update-resume-33637).
            val outDir = File(context.filesDir, UPDATES_DIR).apply { mkdirs() }
            // Filename keyed by version so a partial old-version download
            // can't accidentally satisfy a check for a newer version.
            val safeName = versionName
                ?.replace(Regex("[^A-Za-z0-9._-]"), "_")
                ?.takeIf { it.isNotEmpty() }
                ?.let { "minis-$it.apk" }
                ?: DOWNLOAD_FILENAME
            val outFile = File(outDir, safeName)
            // A previous, possibly-aborted download could leave a stale APK
            // behind that the installer would happily try to consume. Wipe it.
            if (outFile.exists()) outFile.delete()

            val req = Request.Builder().url(url).build()
            val firstOk = downloadToFile(req, outFile, onProgress)
            if (!firstOk) {
                // 直连下载失败（被墙/超时），改用镜像重试一次。
                val mirrored = GitHubMirrorManager.mirrorUrl(url)
                if (mirrored != url) {
                    AppLogger.info(TAG, "直连下载失败，切换镜像: $mirrored")
                    val req2 = Request.Builder().url(mirrored)
                        .header("User-Agent", "MinisApp/1.0").build()
                    if (downloadToFile(req2, outFile, onProgress)) {
                        return@withContext afterDownload(context, outFile, versionName)
                    }
                }
                return@withContext DownloadResult.Error("download failed (direct & mirror)")
            }
            return@withContext afterDownload(context, outFile, versionName)
        } catch (e: Exception) {
            AppLogger.error(TAG, "download failed: ${e.javaClass.simpleName}: ${e.message}")
            DownloadResult.Error(e.message ?: e.javaClass.simpleName)
        }
    }

    /** 下载文件成功后的收尾：计算 sha256 并写入 pending 记录，返回成功结果。 */
    private fun afterDownload(
        context: Context,
        outFile: File,
        versionName: String?,
    ): DownloadResult {
        AppLogger.info(TAG, "Downloaded ${outFile.length()} bytes to ${outFile.absolutePath}")
        // Persist so a subsequent Activity recreate can resume the install
        // without re-downloading. sha256 best-effort.
        val sha = runCatching { PendingUpdateStore.sha256(outFile) }
            .onFailure { AppLogger.warning(TAG, "sha256 compute failed: ${it.message}") }
            .getOrNull()
        if (versionName != null) {
            PendingUpdateStore.setPending(
                context,
                PendingUpdateStore.PendingUpdate(
                    targetVersionName = versionName,
                    apkPath = outFile.absolutePath,
                    apkSize = outFile.length(),
                    sha256 = sha,
                    downloadedAtMs = System.currentTimeMillis(),
                ),
            )
        }
        return DownloadResult.Success(outFile)
    }

    /** 将 [req] 的响应体流式写入 [outFile]，同步进度；成功返回 true。 */
    private fun downloadToFile(
        req: Request,
        outFile: File,
        onProgress: (Float) -> Unit,
    ): Boolean {
        return try {
            client.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) return@downloadToFile false
                val body = resp.body ?: return@downloadToFile false
                val total = body.contentLength().takeIf { it > 0 } ?: -1L
                body.byteStream().use { input ->
                    outFile.outputStream().use { output ->
                        val buf = ByteArray(64 * 1024)
                        var read: Int
                        var totalRead = 0L
                        var lastReported = -1
                        while (input.read(buf).also { read = it } != -1) {
                            output.write(buf, 0, read)
                            totalRead += read
                            if (total > 0) {
                                val pct = ((totalRead * 100) / total).toInt()
                                if (pct != lastReported) {
                                    lastReported = pct
                                    onProgress(pct / 100f)
                                }
                            }
                        }
                    }
                }
            }
            true
        } catch (e: Exception) {
            AppLogger.error(TAG, "downloadToFile failed: ${e.message}")
            false
        }
    }

    /**
     * Whether the OS will allow this app to launch a package-installer
     * intent. On Android 8+ the user must grant "install unknown apps" per
     * source-app; older releases inherit the system-wide setting.
     */
    fun canInstall(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    /**
     * Send the user to the system "install unknown apps" preferences page
     * for this package. Caller should re-check [canInstall] after the user
     * returns.
     */
    fun openInstallPermissionSettings(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
            data = Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    /**
     * Hand [apk] to the system package installer via FileProvider.
     * Caller must ensure [canInstall] before calling, otherwise the system
     * silently bounces back to the launcher. Returns false on any
     * launch failure so callers can surface an error instead of closing
     * the dialog with no visible feedback.
     */
    /**
     * If a pending APK from a previous download is still on disk and intact,
     * returns the [File]. The caller is responsible for checking
     * [canInstall] and firing [installApk]. Returns null when nothing pending
     * or when the cached file failed integrity checks — in the latter case
     * the pending record is cleared so the UI falls through to a fresh
     * download.
     */
    fun resumablePendingFile(context: Context): File? {
        val pending = PendingUpdateStore.getPending(context) ?: return null
        // Only resume if the persisted target is still newer than the running
        // build — protects against the case where the user updated by some
        // other means since the download.
        // [T-android-updatechecker-localver-normalize] targetVersionName is a
        // normalized version (set from upgradeCandidate.versionName), so the
        // local side must be normalized too — same asymmetry fix as check().
        if (compareVersions(pending.targetVersionName, normalizeTag(BuildConfig.VERSION_NAME)) <= 0) {
            AppLogger.info(TAG, "pending target ${pending.targetVersionName} <= local; clearing")
            PendingUpdateStore.clearPending(context)
            return null
        }
        val file = PendingUpdateStore.verify(pending)
        if (file == null) {
            AppLogger.info(TAG, "pending APK failed integrity; clearing")
            PendingUpdateStore.clearPending(context)
            return null
        }
        return file
    }

    fun installApk(context: Context, apk: File): Boolean {
        return try {
            val authority = "${context.packageName}.fileprovider"
            val uri = FileProvider.getUriForFile(context, authority, apk)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            AppLogger.info(TAG, "installApk launched apk=${apk.absolutePath} size=${apk.length()}")
            // Once the installer is in flight we don't want a subsequent
            // resume to re-fire the intent (would double-prompt). Clear the
            // pending record now; if the user backs out, the next "Check for
            // Updates" tap will re-discover and re-download.
            PendingUpdateStore.clearPending(context)
            true
        } catch (e: Exception) {
            AppLogger.error(TAG, "installApk failed: ${e.javaClass.simpleName}: ${e.message}")
            false
        }
    }

    /**
     * Numeric-aware version comparator. `1.0.10` beats `1.0.9`.
     *
     * Both sides are normalised first (strip leading `v` and any `-preview` /
     * `-rc1` suffix), then compared component-by-component numerically. This
     * matches the iOS UpdateChecker behaviour so silent-check / manual-check
     * decisions are identical across platforms.
     *
     * Returns positive when `a > b`, negative when `a < b`, zero when equal.
     */
    private fun compareVersions(a: String, b: String): Int {
        val aClean = normalizeTag(a)
        val bClean = normalizeTag(b)
        val aParts = aClean.split('.').map { it.toIntOrNull() ?: 0 }
        val bParts = bClean.split('.').map { it.toIntOrNull() ?: 0 }
        val n = maxOf(aParts.size, bParts.size)
        for (i in 0 until n) {
            val x = aParts.getOrElse(i) { 0 }
            val y = bParts.getOrElse(i) { 0 }
            val c = x.compareTo(y)
            if (c != 0) return c
        }
        return 0
    }
}
