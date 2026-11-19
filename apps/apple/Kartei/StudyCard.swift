// Copyright: Kartei contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation
import KarteiCore

/// Finishing the backend's partial render the way Anki's Python layer does (pylib/anki/template.py):
/// text nodes as they are, {{FrontSide}} replaced by the question, other pending filters left as the field text.
enum CardText {
    static func flatten(_ nodes: [Anki_CardRendering_RenderedTemplateNode], frontSide: String?) -> String {
        var out = ""
        for node in nodes {
            switch node.value {
            case .text(let t): out += t
            case .replacement(let r): out += (r.fieldName == "FrontSide" ? frontSide : nil) ?? r.currentText
            case nil: break
            }
        }
        return out
    }

    private static let playRef = try! NSRegularExpression(pattern: #"\[anki:play:(q|a):(\d+)\]"#)

    /// Replace the backend's [anki:play:q:0] references with replay buttons that post "play:q:0" to the app.
    static func playButtons(_ html: String) -> String {
        let ns = html as NSString
        var out = ""
        var last = 0
        for m in playRef.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let side = ns.substring(with: m.range(at: 1)), index = ns.substring(with: m.range(at: 2))
            let n = (Int(index) ?? 0) + 1
            out += ##"<a class="k-play" href="#" role="button" aria-label="Play audio \##(n)" onclick="return kartei.play('\##(side):\##(index)')"><svg viewBox="0 0 64 64" aria-hidden="true"><path d="M18 10 L54 32 L18 54 Z"/></svg></a>"##
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    /// Parse "play:q:3" from the page into side and index.
    static func playRequest(_ message: String) -> (question: Bool, index: Int)? {
        let parts = message.split(separator: ":")
        guard parts.count == 3, parts[0] == "play", parts[1] == "q" || parts[1] == "a", let i = Int(parts[2]), i >= 0 else { return nil }
        return (parts[1] == "q", i)
    }
}

/// {{type:Field}} as Anki's reviewer handles it (qt/aqt/reviewer.py typeAnsQuestionFilter / typeAnsAnswerFilter).
struct TypeAnswer: Equatable {
    var field: String
    var cloze = false
    var combining = true
    var ignoreCase = false

    private static let pattern = try! NSRegularExpression(pattern: #"\[\[type:(.+?)\]\]"#)

    /// The first [[type:…]] in the question, with its modifiers (cloze, nc, ci).
    static func find(in html: String) -> TypeAnswer? {
        let ns = html as NSString
        guard let m = pattern.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let inner = ns.substring(with: m.range(at: 1))
        // Field names cannot contain a colon, so everything before the last one is a modifier.
        var spec = TypeAnswer(field: inner)
        if let colon = inner.lastIndex(of: ":") {
            spec.field = String(inner[inner.index(after: colon)...])
            for modifier in inner[..<colon].split(separator: ":") {
                switch modifier {
                case "cloze": spec.cloze = true
                case "nc": spec.combining = false
                case "ci": spec.ignoreCase = true
                default: break
                }
            }
        }
        return spec
    }

    static func replace(_ html: String, with replacement: String) -> String {
        let ns = html as NSString
        return pattern.stringByReplacingMatches(in: html, range: NSRange(location: 0, length: ns.length),
                                                withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
    }

    /// Question side: Kartei shows a native text field below the card, so the marker goes.
    static func question(_ html: String) -> String { replace(html, with: "") }

    /// Answer side: put the comparison where the template's [[type:…]] is. Mirrors Anki's hack that moves
    /// <hr id=answer> in front of the comparison so it lands on the answer half.
    static func answer(_ html: String, comparison: String?) -> String {
        guard let comparison else { return replace(html, with: "") }
        let hr = "<hr id=answer>"
        let withoutHR = html.replacingOccurrences(of: hr, with: "")
        let hadHR = withoutHR.count != html.count
        if hadHR && find(in: withoutHR) == nil { return html }
        return replace(withoutHR, with: (hadHR ? hr : "") + comparison)
    }
}

/// The typed-answer comparison laid out as mockups/screens/typed.html: what you typed, the answer, and a reminder
/// that the learner grades (never auto-graded, docs/science-defaults.md).
enum TypedDiff {
    static let arrow = "<br><span id=typearrow>&darr;</span><br>"

    /// `compared` is the backend's CompareAnswer output, `typed` what the learner entered.
    static func html(compared: String, typed: String) -> String {
        var inner = compared
        if inner.hasPrefix("<code id=typeans>") { inner.removeFirst("<code id=typeans>".count) }
        if inner.hasSuffix("</code>") { inner.removeLast("</code>".count) }
        let typedHTML: String, answerHTML: String, note: String
        if let r = inner.range(of: arrow) {
            typedHTML = String(inner[..<r.lowerBound]); answerHTML = String(inner[r.upperBound...])
            note = "You decide how it counts."
        } else if typed.isEmpty {
            typedHTML = "<span class=meta>nothing</span>"; answerHTML = inner
            note = "Nothing typed. Grade how well you recalled it."
        } else {
            typedHTML = inner; answerHTML = inner
            note = "Exact match. You still decide how it counts."
        }
        let spoken = "You typed: \(typed.isEmpty ? "nothing" : escape(typed)). Answer: \(plain(answerHTML)). \(note)"
        return """
        <div class="k-typed"><span class="k-sr">\(spoken)</span>\
        <div class="ln" aria-hidden="true"><span class="meta">You typed</span><span class="v">\(typedHTML)</span></div>\
        <div class="ln" aria-hidden="true"><span class="meta">Answer</span><span class="v">\(answerHTML)</span></div>\
        <div class="note" aria-hidden="true">\(note)</div></div>
        """
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Tags removed, entities left encoded (it goes back into HTML).
    static func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}

/// Which exam applies to a card: its own deck's, else the nearest ancestor's (deck names nest with "::").
enum ExamLookup {
    static func examDate(deck: Int64, names: [Int64: String], exams: [Int64: Date]) -> Date? {
        if let own = exams[deck] { return own }
        guard let name = names[deck] else { return nil }
        let byName = Dictionary(names.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })
        var parts = name.components(separatedBy: "::")
        while parts.count > 1 {
            parts.removeLast()
            if let id = byName[parts.joined(separator: "::")], let date = exams[id] { return date }
        }
        return nil
    }

    /// Calendar days from today to the exam day, in local time (0 = exam today, negative = past).
    static func daysLeft(until exam: Date, from now: Date = .now, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: exam)).day ?? 0
    }

    private static let dayMonth: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "d MMM"; return f
    }()

    static func note(_ exam: Date) -> String { "Shorter because of the exam on \(dayMonth.string(from: exam))" }
}

extension Backend {
    /// Cap the answer states for an exam `daysLeft` days away (core/ffi/src/exam.rs, Cepeda et al. 2008).
    /// Returns the states unchanged if there is no exam ahead or the library rejects the bytes.
    static func capStates(_ states: Anki_Scheduler_SchedulingStates, daysLeft: Int) -> Anki_Scheduler_SchedulingStates {
        guard daysLeft > 0, let data = try? states.serializedData() else { return states }
        let out = data.withUnsafeBytes { raw in
            kartei_cap_states(raw.bindMemory(to: UInt8.self).baseAddress, raw.count, Int32(clamping: daysLeft))
        }
        defer { kartei_free(out) }
        guard out.ok, let ptr = out.ptr else { return states }
        return (try? Anki_Scheduler_SchedulingStates(serializedBytes: Data(bytes: ptr, count: out.len))) ?? states
    }
}
