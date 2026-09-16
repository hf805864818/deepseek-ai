//
//  AppLocalization.swift
//  MinisApp
//
//  [T-ios-inapp-language-string-localized] Makes the in-app language picker
//  actually apply to every localized string, not just some of them.
//
//  The problem
//  -----------
//  `Bundle.enableLanguageOverride()` (MinisApp.swift) swizzles
//  `Bundle.localizedString(forKey:value:table:)` so the in-app language choice
//  is honoured without an app restart. That works for `Text("…")` and UIKit,
//  which route through that ObjC method — but `String(localized:)` does NOT.
//
//  Measured, not assumed. With the swizzle installed:
//
//      NSLocalizedString("k")   -> Bundle.localizedString hits: 1
//      String(localized: "k")   -> Bundle.localizedString hits: 0
//
//  Three interception strategies were tried against a real bundle and all
//  three failed to redirect `String(localized:)`:
//    1. method swizzling `localizedString(forKey:value:table:)`   — bypassed
//    2. `object_setClass` onto a Bundle subclass overriding it    — bypassed
//    3. overriding `preferredLocalizations` / `localizations`     — bypassed
//  `String(localized:)` resolves the table natively inside Foundation and
//  never calls back into the ObjC entry point, so nothing installed on
//  `Bundle.main` can steer it. Setting `AppleLanguages` does work, but only
//  from the NEXT process launch — verified: `preferredLocalizations` does not
//  change within the running process.
//
//  What DOES work is the one documented seam: `String(localized:bundle:)`
//  honours an explicit bundle. Verified against `es.lproj` / `de.lproj` /
//  `en.lproj` — each returns that language's value.
//
//  The fix
//  -------
//  Route every call through `AppBundle.current`, which is the overridden
//  `.lproj` bundle when the user has picked a language in-app, and
//  `Bundle.main` otherwise. This is deliberately generic: it is keyed off
//  whatever language is selected, so de / fr / ja / ko / ru / zh-Hans /
//  zh-Hant / es all behave the same. Nothing here is Spanish-specific.
//

import Foundation

// MARK: - Format specifier detection

/// Detects whether a string contains unsubstituted `printf`-style format
/// specifiers of any common variant.
///
/// Covers plain (`%lld`), positional (`%1$lld`), width/precision (`%.1f`,
/// `%3$@`) and length-modifier forms (`%zd`, `%tu`) so the hybrid fallback
/// triggers for every interpolated string, not just the single-`lld` case.
/// Translators routinely reorder arguments with `%1$… / %2$…` when the
/// target-language word order differs from English — a naive
/// `contains("%lld")` misses those entirely, which is why the first fix
/// (commit 439ca80) only partially worked.
private func hasUnsubstitutedFormatSpecifiers(_ string: String) -> Bool {
    // %  →  (positional index like "1$")?  →  (width)?  →  (precision like ".2")?
    //    →  (length like ll / l / z / t)?  →  (conversion: @ d i u f e g x c p s …)
    let pattern = "%(?:[0-9]+\\$)?[0-9]*(?:\\.[0-9]+)?(?:ll|l|z|t|h|j)?[@dfiufegxcpsOX]"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return false
    }
    let range = NSRange(string.startIndex..., in: string)
    return regex.firstMatch(in: string, range: range) != nil
}

/// The bundle localized lookups should read from.
///
/// Mirrors `Bundle.main.languageBundle` (set by `Bundle.setLanguage(_:)`), so
/// the in-app picker and this helper can never disagree about which language is
/// active. Falls back to `Bundle.main` when no in-app override is set, which is
/// the normal case — the system language then applies exactly as before.
enum AppBundle {
    /// Memoized override bundle. Populated lazily on first use and cleared by
    /// `Bundle.setLanguage(_:)` via `resetCache()`, so a language change in-app
    /// still takes effect immediately without re-reading the ObjC associated
    /// object on every localized lookup during first-frame render.
    private static var cachedBundle: Bundle?

    /// Call whenever the in-app language override changes so the next lookup
    /// re-reads `Bundle.main.languageBundle`.
    static func resetCache() {
        cachedBundle = nil
    }

    static var current: Bundle {
        if let cachedBundle { return cachedBundle }
        let resolved = (Bundle.main.languageBundle ?? Bundle.main)
        cachedBundle = resolved
        return resolved
    }
}

/// Localized string that follows the in-app language override.
///
/// Drop-in replacement for `String(localized:)`. Prefer this over
/// `String(localized:)` anywhere the result is shown to the user: the bare
/// form silently ignores the in-app language setting (see the file comment),
/// which is what produced mixed-language UI for users whose system language
/// differs from their in-app choice.
///
/// `Text("…")` does not need this — SwiftUI's `Text` routes through
/// `NSLocalizedString`, which the existing swizzle already covers.
///
/// - Parameters:
///   - key: the localization key, i.e. the English source string.
///   - comment: translator context, kept so `genstrings`-style extraction and
///     the String Catalog continue to see it.
///
/// [T-ios-lld-bundle-substitution] `String(localized:bundle:)` retrieves the
/// correct translation for the override bundle but does NOT substitute format
/// specifiers (`%lld`, `%d`, `%@`, `%.1f`, …) at runtime — the translated
/// format string is returned verbatim with placeholders intact. The no-bundle
/// form `String(localized:)` DOES substitute them correctly because it
/// resolves through Foundation's native path. So we use the explicit-bundle
/// form first (for language correctness), then fall back to the no-bundle
/// form when any unsubstituted format specifier is detected in the result.
/// This means interpolated strings (timestamps, model counts, token counts,
/// file sizes, etc.) render in the system language rather than the in-app
/// override — but showing "3 小时前" is strictly better than showing
/// "%lld 小时前". Non-interpolated strings are unaffected and still honour the
/// in-app language setting.
///
/// Detection uses a regex (not `contains("%lld")`) because translators
/// routinely reorder arguments with positional forms like `%1$lld / %2$@`
/// when the target-language word order differs from English. A literal
/// `%lld` check missed those entirely — that was the gap in the first fix
/// (commit 439ca80).
func AppLocalized(_ key: String.LocalizationValue, comment: StaticString? = nil) -> String {
    let result = String(localized: key, bundle: AppBundle.current, comment: comment)
    if hasUnsubstitutedFormatSpecifiers(result) {
        return String(localized: key, comment: comment)
    }
    return result
}

/// `LocalizedStringResource` overload, for call sites that already hold a
/// resource (App Intents build these) rather than a literal key.
///
/// [T-ios-crash-applocalized-recursion] Previous implementation called
/// `AppLocalized(resource)` from its own body, i.e. unbounded self-recursion
/// on the `LocalizedStringResource` overload — any call site that reached this
/// overload spun the main thread indefinitely, which is what surfaced in the
/// scene-create watchdog stack (the top app frame was `AppLocalized`).
/// A `LocalizedStringResource` carries its own bundle reference, so it cannot
/// be re-pointed the way a literal key can. Resolve it as-is — extracting the
/// `String.LocalizationValue` (the key) and re-using the literal-key path so
/// the in-app override still applies to the active bundle.
///
/// Same hybrid fallback as the literal-key overload: `Bundle.localizedString`
/// returns the translated format string verbatim without substituting `%lld`
/// / `%d` / `%@` / positional variants, so if we detect any unsubstituted
/// format specifier we fall back to `String(localized:)` which goes through
/// Foundation's native path and does the substitution correctly.
func AppLocalized(_ resource: LocalizedStringResource) -> String {
    // LocalizedStringResource.key is a plain String on the current SDK (it was
    // String.LocalizationValue on older ones), so plumbing it through
    // String(localized:bundle:) is not type-stable across SDKs. Resolve via
    // Bundle.localizedString(forKey:value:table:), which is the same seam the
    // language-override swizzle already patches — `AppBundle.current` +
    // `overrideLocalizedString` honor the in-app language and need no generic
    // key-typed re-construction.
    let result = AppBundle.current.localizedString(
        forKey: resource.key, value: resource.key, table: nil
    )
    if hasUnsubstitutedFormatSpecifiers(result) {
        return String(localized: resource)
    }
    return result
}
