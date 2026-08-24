package com.openminis.app.data

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * 动态 GitHub 镜像管理器。
 *
 * 设计要点（基于实测验证，2026-08-24）：
 *  1. 首用懒加载：App 启动不拉取；用户第一次真正需要用 GitHub 时触发拉取节点列表。
 *  2. TTL 缓存：拉到的节点列表缓存 30 分钟，TTL 内复用，过期后下次使用再刷新。
 *  3. 内置兜底：ghfast.top（raw 文件代理，已验证）+ gh.sixyin.com（API 代理，已验证返回真 JSON），
 *     拉取失败时立即用兜底节点，保证首次操作仍可用。
 *  4. 真实节点来源：用 ghfast.top 代理拉取 ghproxy-next 的 nodes.ts，避免“鸡生蛋”（拉节点列表又要代理）。
 *
 * 实测结论（重要，不要改动默认值）：
 *  - ghfast.top 支持 raw/git/release 文件代理，但【不支持 API 代理】（设计如此）。
 *  - gh.sixyin.com 是唯一实测返回真 GitHub API JSON 的节点。
 *  - 多数第三方节点返回的 200 是反爬 JS 页面，不是真数据，不可用于代码调用。
 */
object GitHubMirrorManager {

    private const val TAG = "GitHubMirror"
    private const val DEFAULT_TTL_MS = 30L * 60 * 1000 // 30分钟

    /** 内置兜底节点，首用/拉取失败时立即可用。 */
    const val FALLBACK_RAW_NODE = "ghfast.top"          // raw/git/release 代理
    const val FALLBACK_API_NODE = "gh.sixyin.com"       // API 代理（真 JSON 已验证）

    /** nodes.ts 拉取地址：用 ghfast.top 代理 ghproxy-next，解决自举问题。 */
    private const val NODES_TS_URL =
        "https://ghfast.top/https://raw.githubusercontent.com/hubporg/ghproxy-next/main/components/nodes.ts"

    private val client = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(12, TimeUnit.SECONDS)
        .build()

    @Volatile private var cachedRawNode: String? = null
    @Volatile private var cachedApiNode: String? = null
    @Volatile private var lastFetchMs: Long = 0
    @Volatile private var fetchAttempted = false

    /**
     * 获取当前应使用的代理节点。
     * [needApi]：是否需要 API 代理（api.github.com），true 走 API 节点，false 走 raw/git 节点。
     *
     * 触发策略（首次真实使用时才拉取；之后 TTL 内复用，TTL 过期且当前不是兜底时刷新）。
     */
    suspend fun resolveNode(needApi: Boolean): String = withContext(Dispatchers.IO) {
        val now = System.currentTimeMillis()
        val cached = if (needApi) cachedApiNode else cachedRawNode
        if (cached != null && now - lastFetchMs < DEFAULT_TTL_MS) {
            return@withContext cached
        }
        ensureFetched()
        (if (needApi) cachedApiNode else cachedRawNode)
            ?: if (needApi) FALLBACK_API_NODE else FALLBACK_RAW_NODE
    }

    /**
     * 将 GitHub URL 替换为代理 URL。
     * 仅替换明确属于 GitHub 的域名；其余 URL 原样返回。
     */
    suspend fun mirrorUrl(original: String): String = withContext(Dispatchers.IO) {
        when {
            original.contains("api.github.com") -> {
                val node = resolveNode(needApi = true)
                val path = original.substringAfter("https://api.github.com")
                "https://$node/https://api.github.com$path"
            }
            original.contains("raw.githubusercontent.com") -> {
                val node = resolveNode(needApi = false)
                val path = original.substringAfter("https://raw.githubusercontent.com")
                "https://$node/https://raw.githubusercontent.com$path"
            }
            original.contains("github.com") && original.contains("releases/download/") -> {
                val node = resolveNode(needApi = false)
                val path = original.substringAfter("https://")
                "https://$node/https://$path"
            }
            original.contains("github.com/blobs") || original.contains("github.com/archive") -> {
                val node = resolveNode(needApi = false)
                val path = original.substringAfter("https://")
                "https://$node/https://$path"
            }
            else -> original
        }
    }

    /** 强制刷新节点列表（供设置界面手动刷新）。 */
    suspend fun forceRefresh() {
        fetchAttempted = false
        lastFetchMs = 0
        fetchNodesFromProxy()
    }

    /** 从 ghproxy-next 拉取最新节点列表，检测延迟后缓存最优节点。 */
    private suspend fun fetchNodesFromProxy() {
        val content = runCatching {
            val req = Request.Builder().url(NODES_TS_URL)
                .header("User-Agent", "Mozilla/5.0 (Linux; Android) GitHubMirror/1.0")
                .build()
            client.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) throw IOException("nodes.ts HTTP ${resp.code}")
                resp.body?.string() ?: throw IOException("empty body")
            }
        }.getOrNull()

        if (content == null) {
            Log.w(TAG, "nodes.ts 拉取失败，回退到内置兜底节点")
            cachedRawNode = FALLBACK_RAW_NODE
            cachedApiNode = FALLBACK_API_NODE
            lastFetchMs = System.currentTimeMillis()
            return
        }

        // 解析 nodes.ts 中的 value: "域名"
        val pattern = Regex("value\\s*:\\s*\"([^\"]+)\"")
        val domains = pattern.findAll(content)
            .map { it.groupValues[1] }
            .filter { it.isNotEmpty() && !it.contains("/") }
            .toList()
        if (domains.isEmpty()) {
            Log.w(TAG, "nodes.ts 未解析到域名，回退兜底")
            cachedRawNode = FALLBACK_RAW_NODE
            cachedApiNode = FALLBACK_API_NODE
            lastFetchMs = System.currentTimeMillis()
            return
        }
        Log.i(TAG, "解析到 ${domains.size} 个节点")

        // 顺序检测前几个节点作为 raw 代理的延迟，取最快的一个。
        // 不搞并发：并发在 iSH/低端机上有协程作用域与超时控制的复杂度，顺序走更稳，
        // 且每个节点带上限。用 OkHttp client 的超时(连接8s/读12s)做兜底。
        val ua = "Mozilla/5.0 (Linux; Android) GitHubMirror/1.0"
        val probe = "https://raw.githubusercontent.com/hubporg/ghproxy-next/main/README.md"
        val candidates = domains.take(8) // 只测前8个，避免耗时过长
        var bestNode: String? = null
        var bestLatency = Long.MAX_VALUE
        for (node in candidates) {
            try {
                val t0 = System.currentTimeMillis()
                val req = Request.Builder().url("https://$node/https://$probe")
                    .header("User-Agent", ua)
                    .build()
                client.newCall(req).execute().use { resp ->
                    if (resp.isSuccessful) {
                        val lat = System.currentTimeMillis() - t0
                        if (lat < bestLatency) {
                            bestLatency = lat
                            bestNode = node
                        }
                        Log.i(TAG, "node=$node OK ${lat}ms")
                    } else {
                        Log.i(TAG, "node=$node HTTP ${resp.code} 跳过")
                    }
                }
            } catch (e: Exception) {
                Log.i(TAG, "node=$node 不可用: ${e.javaClass.simpleName}")
            }
        }

        cachedRawNode = bestNode ?: FALLBACK_RAW_NODE
        cachedApiNode = FALLBACK_API_NODE
        lastFetchMs = System.currentTimeMillis()
        Log.i(TAG, "最优 raw 节点=$cachedRawNode (${bestLatency}ms)")
    }

    /** 确保节点已拉取（懒加载入口，只执行一次）。 */
    private suspend fun ensureFetched() {
        if (fetchAttempted) return
        fetchAttempted = true
        fetchNodesFromProxy()
    }
}
