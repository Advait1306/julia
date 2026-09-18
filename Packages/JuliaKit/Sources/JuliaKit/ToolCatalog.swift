import Foundation
import AppKit

public struct ToolParameter: Sendable {
    public enum Kind: String, Sendable { case string, integer, boolean }
    public let name: String
    public let type: Kind
    public let required: Bool
    public let help: String
}
public struct ToolDefinition: Sendable {
    public let name: String
    public let application: String
    public let summary: String
    public let parameters: [ToolParameter]

    public var schema: JSONValue {
        .object([
            "name": .string(name), "description": .string(summary),
            "parameters": .object([
                "type": .string("object"), "additionalProperties": .bool(false),
                "required": .array(parameters.filter(\.required).map { .string($0.name) }),
                "properties": .object(Dictionary(uniqueKeysWithValues: parameters.map {
                    ($0.name, .object(["type": .string($0.type.rawValue), "description": .string($0.help)]))
                }))
            ])
        ])
    }
    public func validate(_ args: [String: JSONValue]) throws {
        let known = Set(parameters.map(\.name))
        guard Set(args.keys).isSubset(of: known) else { throw JuliaError("Unknown arguments for \(name): \(Set(args.keys).subtracting(known).sorted())") }
        for p in parameters {
            guard let value = args[p.name], value != .null else {
                if p.required { throw JuliaError("\(name) requires \(p.name).") }; continue
            }
            let valid: Bool
            switch p.type {
            case .string: valid = value.string != nil
            case .integer: valid = value.integer != nil
            case .boolean: valid = value.boolean != nil
            }
            guard valid else { throw JuliaError("\(p.name) must be \(p.type.rawValue).") }
            if let s = value.string, s.utf8.count > 32_000 { throw JuliaError("\(p.name) exceeds 32 KB. Split the request.") }
        }
    }
}

public enum ToolCatalog {
    public static let all = orchard + [
        ToolDefinition(name: "calendar.today", application: "Calendar", summary: "List today's calendar events.", parameters: []),
        ToolDefinition(name: "system.info", application: "System", summary: "Get the local date, timezone, home directory, and macOS version.", parameters: []),
        ToolDefinition(name: "system.running_apps", application: "System", summary: "List running foreground-capable applications.", parameters: []),
        ToolDefinition(name: "system.open_application", application: "System", summary: "Open an installed application or bring its existing instance to the foreground.", parameters: [
            .init(name: "application", type: .string, required: true, help: "Application name or bundle ID, for example Calendar, Safari, or com.apple.iCal.")
        ])
    ]
    public static let applications = Array(Set(all.map(\.application))).sorted()
    public static func skill(_ application: String) throws -> JSONValue {
        guard let app = applications.first(where: { $0.caseInsensitiveCompare(application) == .orderedSame }) else {
            throw JuliaError("No dedicated skill named '\(application)'. This does not mean the app is unavailable. To open or focus any installed app, read the System skill. Available skill groups: \(applications.joined(separator: ", ")).")
        }
        return .object([
            "application": .string(app),
            "instructions": .string(app == "System" ? """
                You now have the System documentation. To open the user's requested app, your next response is a call to system.open_application. Copy the complete tool name including system.
                Example for a user asking to open Safari:
                {"tool":"system.open_application","arguments":{"application":"Safari"}}
                Example for a user asking to open settings:
                {"tool":"system.open_application","arguments":{"application":"System Settings"}}
                For other apps, substitute the name from the original request in application.
                A reply naming the app does not open it. You must emit the tool call and receive status opened BEFORE a final answer. Do not read this skill again.
                For system information or running apps, use the corresponding tool below. All registered tools remain callable.
                """ : """
                You now have the \(app) documentation. Execute the requested operation using a tool below; do not read this skill again.
                Examples of data operations (adapt the arguments to the original user request):
                \(dataExamples(app))
                After a successful data result, answer using that result. If it contains no matches, say so. If access is denied, report the permission error.
                Use IDs and paths from actual tool results, not example values. Relative dates use the user's local timezone.
                Reading data does not require opening an application's window.
                If the user's request is to OPEN or FOCUS \(app == "Files" ? "Finder" : app), use the shared application-opening tool:
                {"tool":"system.open_application","arguments":{"application":"\(app == "Files" ? "Finder" : app)"}}
                This tool takes an application name and opens or focuses it. After it returns status opened, answer the user. Do not reread this skill.
                No UI automation is available. All tools remain callable whether or not their skill has been read.
                """),
            "tools": .array(all.filter { $0.application == app }.map(\.schema))
        ])
    }

    private static func dataExamples(_ app: String) -> String {
        switch app {
        case "Contacts":
            return """
            User: Search Vivek's contact information.
            Next response: {"tool":"contacts.search","arguments":{"query":"Vivek","limit":10}}
            User: What is Maya's phone number?
            Next response: {"tool":"contacts.search","arguments":{"query":"Maya","limit":10}}
            Search results include phone numbers and emails. Answer from those results when sufficient.
            If more details are needed and the search returned id "contact-42":
            Next response: {"tool":"contacts.read","arguments":{"id":"contact-42"}}
            If contacts.search or contacts.read returns "Contacts access denied":
            Next response: {"answer":"Contacts access was denied. Enable Julia in System Settings > Privacy & Security > Contacts, then try again."}
            A denied search is finished with this error explanation. Do not open Contacts or search again.
            """
        case "Reminders":
            return """
            User: What todos are in my reminders?
            Next response: {"tool":"reminders.list","arguments":{"filter":"incomplete","limit":10}}
            User: Show all reminders, including completed ones.
            Next response: {"tool":"reminders.list","arguments":{"filter":"all","limit":10}}
            Omit list to search across all lists. The list argument is an actual list name, never the special value "all".
            User: What is due today?
            Next response: {"tool":"reminders.today","arguments":{}}
            User: Show my reminder lists.
            Next response: {"tool":"reminders.lists","arguments":{}}
            User: Add buy milk to my Groceries list.
            Next response: {"tool":"reminders.create","arguments":{"list":"Groceries","title":"Buy milk"}}
            Example successful reminders.list result: [{"title":"Water plants","list":"Home","isCompleted":false}]
            Next response: {"answer":"Water plants — Home, incomplete."}
            List the returned reminders. isCompleted false means a pending todo, not an empty result. Say no reminders only when the result is empty.
            """
        case "Calendar":
            return """
            User: What's on my calendar today?
            Next response: {"tool":"calendar.today","arguments":{}}
            User: Show my calendars.
            Next response: {"tool":"calendar.list_calendars","arguments":{}}
            """
        case "Files":
            return """
            User: List my Downloads folder.
            Next response: {"tool":"files.list","arguments":{"path":"~/Downloads"}}
            User: Find budget PDFs.
            Next response: {"tool":"files.search","arguments":{"query":"budget","kind":"pdf"}}
            """
        case "Mail":
            return """
            User: Show unread emails.
            Next response: {"tool":"mail.unread","arguments":{"limit":10}}
            User: Find emails about invoices.
            Next response: {"tool":"mail.search","arguments":{"query":"invoice","limit":10}}
            """
        case "Notes":
            return """
            User: Find my shopping note.
            Next response: {"tool":"notes.search","arguments":{"query":"shopping","searchIn":"title","limit":10}}
            If the matching result returned id "note-42" and the user wants its contents:
            Next response: {"tool":"notes.read","arguments":{"id":"note-42","maxBodyLength":4000}}
            """
        case "Numbers":
            return """
            User: Find my budget spreadsheet.
            Next response: {"tool":"numbers.search","arguments":{"query":"budget","limit":10}}
            If the matching result returned file "~/Documents/Budget.numbers", read a bounded cell range:
            Next response: {"tool":"numbers.read","arguments":{"file":"~/Documents/Budget.numbers","range":"A1:C10"}}
            """
        case "Pages":
            return """
            User: Find my proposal document.
            Next response: {"tool":"pages.search","arguments":{"query":"proposal","limit":10}}
            If the matching result returned file "~/Documents/Proposal.pages" and the user wants its contents:
            Next response: {"tool":"pages.read","arguments":{"file":"~/Documents/Proposal.pages"}}
            """
        case "Keynote":
            return """
            User: Find my roadmap presentation.
            Next response: {"tool":"keynote.search","arguments":{"query":"roadmap","limit":10}}
            If the matching result returned file "~/Documents/Roadmap.key" and the user wants the first slide:
            Next response: {"tool":"keynote.read","arguments":{"file":"~/Documents/Roadmap.key","slide":1}}
            """
        default: return ""
        }
    }

}

public protocol ToolExecuting: Sendable {
    func execute(name: String, arguments: [String: JSONValue]) async throws -> JSONValue
}

/// One native operation at a time, including across actor reentrancy. No discovery authorization state.
public actor NativeTools: ToolExecuting {
    private var busy = false
    public init() {}
    public func execute(name: String, arguments: [String: JSONValue]) async throws -> JSONValue {
        try Task.checkCancellation()
        guard let tool = ToolCatalog.all.first(where: { $0.name == name }) else { throw JuliaError("Unknown tool '\(name)'. Use get_skill to inspect its exact name and arguments.") }
        try tool.validate(arguments)
        try ToolGuards.validate(name, arguments)
        guard !busy else { throw JuliaError("Another native operation is finishing. Try again shortly.") }
        busy = true; defer { busy = false }
        if name == "system.open_application" {
            return try await ApplicationLauncher.open(arguments.string("application"))
        }
        if name == "system.info" {
            return .object(["date": .string(iso8601(Date())), "timezone": .string(TimeZone.current.identifier),
                            "home": .string(NSHomeDirectory()), "macOS": .string(ProcessInfo.processInfo.operatingSystemVersionString)])
        }
        if name == "system.running_apps" {
            return await MainActor.run {
                .array(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map {
                    .object(["name": .string($0.localizedName ?? ""), "bundleID": .string($0.bundleIdentifier ?? "")])
                })
            }
        }
        let sink = ResultSink()
        try await JSONOutput.$sink.withValue(sink) {
            if name == "calendar.today" {
                let start = Calendar.current.startOfDay(for: Date())
                let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
                await CalendarBridge.listEvents(startISO: iso8601(start), endISO: iso8601(end), calendarID: nil)
            } else { try await OrchardDispatch.call(name, arguments) }
        }
        guard let result = sink.value else { throw JuliaError("\(name) did not return a result.") }
        if result["status"].string == "error" { throw JuliaError(result["error"].string ?? "Tool failed") }
        return result["data"]
    }
}

enum ToolGuards {
    static func validate(_ name: String, _ p: [String: JSONValue]) throws {
        if let n = p["limit"]?.integer, !(1...100).contains(n) { throw JuliaError("limit must be between 1 and 100.") }
        if let n = p["maxBodyLength"]?.integer, !(1...8000).contains(n) { throw JuliaError("maxBodyLength must be between 1 and 8000.") }
        if let n = p["depth"]?.integer, !(0...5).contains(n) { throw JuliaError("depth must be between 0 and 5.") }
        if let n = p["offset"]?.integer, !(0...500).contains(n) { throw JuliaError("offset must be between 0 and 500.") }
        for key in ["slide", "position", "from"] {
            if let n = p[key]?.integer, n < 1 { throw JuliaError("\(key) is one-based.") }
        }
        if let n = p["index"]?.integer, n < 0 { throw JuliaError("index must be non-negative.") }
        if let n = p["priority"]?.integer, ![0, 1, 5, 9].contains(n) { throw JuliaError("priority must be 0, 1, 5, or 9.") }
        if name == "notes.search", let field = p["searchIn"]?.string, field != "title" {
            throw JuliaError("Search Notes titles, then read a specific note. Broad body scans are disabled.")
        }
        if ["numbers.read", "numbers.get_formulas"].contains(name), p["range"]?.string?.isEmpty != false {
            throw JuliaError("Provide a bounded range such as A1:C20.")
        }
        if name == "keynote.export", ["png", "jpeg"].contains(p["format"]?.string ?? ""), p["slide"]?.integer == nil {
            throw JuliaError("Provide a slide index for image export.")
        }
        if ["mail.message", "mail.save_attachment"].contains(name) {
            guard p["account"]?.string?.isEmpty == false, p["mailbox"]?.string?.isEmpty == false else {
                throw JuliaError("Provide account and mailbox from the message search result.")
            }
        }
        if name == "files.move" {
            let items = try JSONValue.parse(p.string("items"))
            guard let a = items.array, !a.isEmpty, a.count <= 25 else { throw JuliaError("Provide 1–25 move items.") }
        }
    }
}
