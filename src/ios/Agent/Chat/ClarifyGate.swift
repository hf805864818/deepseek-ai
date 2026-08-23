import Foundation

/// Clarification gate for 深度龙虾Ai — Phase 2.
///
/// Before entering the planning phase for a complex task, the client checks
/// whether the user's request contains high-confidence ambiguities (multiple
/// tech-stack options, vague goals, missing critical parameters). If so, it
/// raises a clarification question and pauses — instead of guessing.
///
/// Design principle: conservative first. We only trigger on very clear
/// ambiguity signals to avoid becoming "the agent that asks about everything".
/// False negatives (missed ambiguity) are cheap — the model just guesses and
/// the user can correct it. False positives (unnecessary question) are
/// annoying — so we keep the bar high.
enum ClarifyGate {

    enum State: Equatable {
        case idle
        case awaitingClarification(question: String, originalRequest: String)
    }

    /// High-confidence ambiguity patterns. Each is a simple heuristic — this
    /// is intentionally not an LLM call; a lightweight keyword check is enough
    /// for the most common "A or B" / "build me a thing (but what thing?)"
    /// cases and keeps the gate deterministic and cheap.
    private static let techChoicePatterns: [String] = [
        "react", "vue", "angular", "svelte",
        "python", "node", "nodejs", "node.js", "go", "golang", "rust",
        "java", "kotlin", "swift", "flutter", "react native",
        "mysql", "postgres", "postgresql", "mongodb", "sqlite", "redis",
        "tailwind", "bootstrap",
        "docker", "kubernetes", "k8s",
        "aws", "gcp", "azure", "vercel", "netlify",
        "django", "flask", "fastapi", "spring", "express", "nestjs",
        "nextjs", "next.js", "nuxt", "remix"
    ]

    /// Vague-goal patterns — requests that are too broad to execute well
    /// without clarification. Matched against the WHOLE request.
    private static let vaguePatterns: [String] = [
        "帮我做个网站", "帮我做个app", "帮我做个应用", "帮我做个软件",
        "做个网站", "做个app", "做个应用", "做个软件",
        "帮我写个项目", "写个项目", "做个项目",
        "帮我整个网站", "整个网站", "整个项目"
    ]

    /// Detect whether a user request contains high-confidence ambiguity that
    /// warrants a clarification question before planning. Returns the
    /// clarification question text, or nil if no clarification is needed.
    ///
    /// Intentionally conservative: returns nil for anything that's not a very
    /// clear signal. The cost of asking unnecessarily is higher than the cost
    /// of the model making a reasonable guess.
    static func detectAmbiguity(in text: String) -> String? {
        let lowercased = text.lowercased()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Very short requests are unlikely to be complex multi-step tasks
        // that need clarification — they're probably trivial commands.
        guard trimmed.count > 8 else { return nil }

        // 1. Choice ambiguity: "X 还是 Y" / "X 或者 Y" / "用 X 还是 Y"
        //    where both X and Y are known tech-stack keywords.
        if let question = detectChoiceAmbiguity(in: lowercased, original: text) {
            return question
        }

        // 2. Vague-goal ambiguity: the user asked for "a website/app/project"
        //    but gave zero specifics about what it should do.
        if let question = detectVagueGoalAmbiguity(in: lowercased, original: text) {
            return question
        }

        return nil
    }

    // MARK: - Private detectors

    private static func detectChoiceAmbiguity(in lowercased: String, original: String) -> String? {
        // Look for "还是" / "或者" / "还是用" patterns that connect two
        // known tech keywords.
        let choicePatterns = ["还是", "或者", "或是"]

        for pattern in choicePatterns {
            guard let range = lowercased.range(of: pattern) else { continue }
            let before = String(lowercased[..<range.lowerBound])
            let after = String(lowercased[range.upperBound...])

            let beforeKeywords = findTechKeywords(in: before)
            let afterKeywords = findTechKeywords(in: after)

            if !beforeKeywords.isEmpty && !afterKeywords.isEmpty {
                return "你提到了 \(beforeKeywords.joined("/")) 还是 \(afterKeywords.joined("/"))，请问你希望使用哪个技术栈？"
            }
        }
        return nil
    }

    private static func detectVagueGoalAmbiguity(in lowercased: String, original: String) -> String? {
        for vague in vaguePatterns {
            if lowercased.contains(vague) {
                // If the request is very short (< 30 chars) and hits a vague
                // pattern, it's almost certainly underspecified.
                if original.count < 30 {
                    return "需求有点宽泛，可以再具体说说吗？比如需要什么功能、面向什么场景、有没有偏好的技术栈？"
                }
                // Longer requests may have enough detail even if they contain
                // a vague-phrasing keyword. Check for specific feature words.
                let detailKeywords = ["功能", "页面", "登录", "注册", "数据", "后台",
                                      "管理", "支付", "搜索", "推荐", "用户", "系统",
                                      "接口", "数据库", "设计", "ui", "界面"]
                let hasDetails = detailKeywords.contains { lowercased.contains($0) }
                if !hasDetails {
                    return "需求可以再具体些吗？比如核心功能是什么、有没有特定的使用场景、对技术栈有没有偏好？"
                }
            }
        }
        return nil
    }

    private static func findTechKeywords(in text: String) -> [String] {
        var found: [String] = []
        for keyword in techChoicePatterns {
            if text.contains(keyword) {
                found.append(keyword)
                if found.count >= 2 { break } // cap: only need to know there's a choice
            }
        }
        return found
    }
}
