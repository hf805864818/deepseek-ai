package com.openminis.app.agent

/**
 * Clarification gate for 深度龙虾Ai — Phase 2.
 *
 * Before entering the planning phase for a complex task, the client checks
 * whether the user's request contains high-confidence ambiguities (multiple
 * tech-stack options, vague goals, missing critical parameters). If so, it
 * raises a clarification question and pauses — instead of guessing.
 *
 * Design principle: conservative first. We only trigger on very clear
 * ambiguity signals to avoid becoming "the agent that asks about everything".
 * False negatives (missed ambiguity) are cheap — the model just guesses and
 * the user can correct it. False positives (unnecessary question) are
 * annoying — so we keep the bar high.
 */
object ClarifyGate {

    enum class State {
        IDLE,
        AWAITING_CLARIFICATION,
    }

    data class AmbiguityResult(
        val question: String,
        val originalRequest: String,
    )

    /** High-confidence tech-stack keywords used for choice-ambiguity detection. */
    private val techChoiceKeywords = listOf(
        "react", "vue", "angular", "svelte",
        "python", "node", "nodejs", "node.js", "go", "golang", "rust",
        "java", "kotlin", "swift", "flutter", "react native",
        "mysql", "postgres", "postgresql", "mongodb", "sqlite", "redis",
        "tailwind", "bootstrap",
        "docker", "kubernetes", "k8s",
        "aws", "gcp", "azure", "vercel", "netlify",
        "django", "flask", "fastapi", "spring", "express", "nestjs",
        "nextjs", "next.js", "nuxt", "remix",
    )

    /** Vague-goal patterns — requests that are too broad to execute well without clarification. */
    private val vaguePatterns = listOf(
        "帮我做个网站", "帮我做个app", "帮我做个应用", "帮我做个软件",
        "做个网站", "做个app", "做个应用", "做个软件",
        "帮我写个项目", "写个项目", "做个项目",
        "帮我整个网站", "整个网站", "整个项目",
    )

    /**
     * Detect whether a user request contains high-confidence ambiguity that
     * warrants a clarification question before planning. Returns the
     * clarification question text, or null if no clarification is needed.
     *
     * Intentionally conservative: returns null for anything that's not a very
     * clear signal.
     */
    fun detectAmbiguity(text: String): AmbiguityResult? {
        val lowercased = text.lowercase()
        val trimmed = text.trim()

        // Very short requests are unlikely to be complex multi-step tasks
        // that need clarification — they're probably trivial commands.
        if (trimmed.length <= 8) return null

        // 1. Choice ambiguity: "X 还是 Y" / "X 或者 Y" where both sides
        //    contain known tech-stack keywords.
        detectChoiceAmbiguity(lowercased, text)?.let { question ->
            return AmbiguityResult(question, text)
        }

        // 2. Vague-goal ambiguity: the user asked for "a website/app/project"
        //    but gave zero specifics about what it should do.
        detectVagueGoalAmbiguity(lowercased, text)?.let { question ->
            return AmbiguityResult(question, text)
        }

        return null
    }

    // MARK: - Private detectors

    private fun detectChoiceAmbiguity(lowercased: String, original: String): String? {
        val choicePatterns = listOf("还是", "或者", "或是")

        for (pattern in choicePatterns) {
            val idx = lowercased.indexOf(pattern)
            if (idx < 0) continue

            val before = lowercased.substring(0, idx)
            val after = lowercased.substring(idx + pattern.length)

            val beforeKeywords = findTechKeywords(before)
            val afterKeywords = findTechKeywords(after)

            if (beforeKeywords.isNotEmpty() && afterKeywords.isNotEmpty()) {
                return "你提到了 ${beforeKeywords.joinToString("/")} 还是 ${afterKeywords.joinToString("/")}，请问你希望使用哪个技术栈？"
            }
        }
        return null
    }

    private fun detectVagueGoalAmbiguity(lowercased: String, original: String): String? {
        for (vague in vaguePatterns) {
            if (lowercased.contains(vague)) {
                // If the request is very short (< 30 chars) and hits a vague
                // pattern, it's almost certainly underspecified.
                if (original.length < 30) {
                    return "需求有点宽泛，可以再具体说说吗？比如需要什么功能、面向什么场景、有没有偏好的技术栈？"
                }
                // Longer requests may have enough detail even if they contain
                // a vague-phrasing keyword. Check for specific feature words.
                val detailKeywords = listOf(
                    "功能", "页面", "登录", "注册", "数据", "后台",
                    "管理", "支付", "搜索", "推荐", "用户", "系统",
                    "接口", "数据库", "设计", "ui", "界面",
                )
                val hasDetails = detailKeywords.any { lowercased.contains(it) }
                if (!hasDetails) {
                    return "需求可以再具体些吗？比如核心功能是什么、有没有特定的使用场景、对技术栈有没有偏好？"
                }
            }
        }
        return null
    }

    private fun findTechKeywords(text: String): List<String> {
        val found = mutableListOf<String>()
        for (keyword in techChoiceKeywords) {
            if (keyword in text) {
                found.add(keyword)
                if (found.size >= 2) break // cap: only need to know there's a choice
            }
        }
        return found
    }
}
