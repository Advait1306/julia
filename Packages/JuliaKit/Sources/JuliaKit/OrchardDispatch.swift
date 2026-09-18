// Adapted from Orchard's command definitions. See ORCHARD-PROVENANCE.md.
import Foundation

extension ToolCatalog {
    static let orchard: [ToolDefinition] = [
        .init(name: "calendar.list_calendars", application: "Calendar", summary: "List all calendars with account info.", parameters: []),
        .init(name: "calendar.list_events", application: "Calendar", summary: "List events in a date range. Recurring events are expanded.", parameters: [.init(name: "start", type: .string, required: true, help: "Start date (ISO 8601, e.g. 2026-02-17 or 2026-02-17T00:00:00Z)"), .init(name: "end", type: .string, required: true, help: "End date (ISO 8601)"), .init(name: "calendar", type: .string, required: false, help: "Filter by calendar ID (from 'calendars' subcommand)")]),
        .init(name: "calendar.search", application: "Calendar", summary: "Search events by title, notes, or location within a date range.", parameters: [.init(name: "query", type: .string, required: true, help: "Search query"), .init(name: "start", type: .string, required: true, help: "Start date (ISO 8601)"), .init(name: "end", type: .string, required: true, help: "End date (ISO 8601)")]),
        .init(name: "mail.accounts", application: "Mail", summary: "List all mail accounts with mailboxes and unread counts.", parameters: []),
        .init(name: "mail.unread", application: "Mail", summary: "Unread summary per account with recent message subjects.", parameters: [.init(name: "limit", type: .integer, required: false, help: "Max unread messages to return per account (default: 10)")]),
        .init(name: "mail.search", application: "Mail", summary: "Search messages by subject, sender, body, or all fields.", parameters: [.init(name: "query", type: .string, required: true, help: "Search query (matches subject and sender)"), .init(name: "account", type: .string, required: false, help: "Filter to specific account name"), .init(name: "mailbox", type: .string, required: false, help: "Mailbox to search in (default: inbox)"), .init(name: "limit", type: .integer, required: false, help: "Max results to return (default: 20)"), .init(name: "searchIn", type: .string, required: false, help: "Fields to search: subject, sender, body, all (default: all)"), .init(name: "offset", type: .integer, required: false, help: "Number of results to skip for pagination")]),
        .init(name: "mail.message", application: "Mail", summary: "Get full message content by message ID.", parameters: [.init(name: "id", type: .string, required: true, help: "Message ID (from mail-search or mail-unread)"), .init(name: "account", type: .string, required: false, help: "Mail account name from the search/list result"), .init(name: "mailbox", type: .string, required: false, help: "Mailbox name/path from the search/list result"), .init(name: "maxBodyLength", type: .integer, required: false, help: "Max body characters to return (default: 4000, maximum 8000)")]),
        .init(name: "mail.flagged", application: "Mail", summary: "List flagged messages across all accounts.", parameters: [.init(name: "limit", type: .integer, required: false, help: "Max results to return (default: 20)"), .init(name: "offset", type: .integer, required: false, help: "Number of results to skip for pagination")]),
        .init(name: "mail.create_draft", application: "Mail", summary: "Create a draft email in Mail.app.", parameters: [.init(name: "to", type: .string, required: true, help: "Recipient email addresses (comma-separated)"), .init(name: "cc", type: .string, required: false, help: "CC email addresses (comma-separated)"), .init(name: "bcc", type: .string, required: false, help: "BCC email addresses (comma-separated)"), .init(name: "subject", type: .string, required: true, help: "Email subject"), .init(name: "body", type: .string, required: true, help: "Email body text"), .init(name: "account", type: .string, required: false, help: "Sender email address (from mail-accounts)")]),
        .init(name: "mail.save_attachment", application: "Mail", summary: "Save a message attachment to disk.", parameters: [.init(name: "id", type: .string, required: true, help: "Message ID (from mail-search or mail-unread)"), .init(name: "account", type: .string, required: false, help: "Mail account name from the search/list result"), .init(name: "mailbox", type: .string, required: false, help: "Mailbox name/path from the search/list result"), .init(name: "index", type: .integer, required: true, help: "Attachment index (0-based, from mail-message output)"), .init(name: "path", type: .string, required: false, help: "Output directory")]),
        .init(name: "reminders.lists", application: "Reminders", summary: "List all reminder lists with account and color.", parameters: []),
        .init(name: "reminders.list", application: "Reminders", summary: "List reminders with optional filters.", parameters: [.init(name: "list", type: .string, required: false, help: "Filter to a specific list name"), .init(name: "filter", type: .string, required: false, help: "Filter: incomplete (default), completed, overdue, dueToday, all"), .init(name: "limit", type: .integer, required: false, help: "Max reminders to return (default: 50)")]),
        .init(name: "reminders.today", application: "Reminders", summary: "Incomplete reminders due today plus overdue across all lists.", parameters: []),
        .init(name: "reminders.create_list", application: "Reminders", summary: "Create a new reminder list.", parameters: [.init(name: "name", type: .string, required: true, help: "Name for the new list")]),
        .init(name: "reminders.create", application: "Reminders", summary: "Create a new reminder in a list.", parameters: [.init(name: "list", type: .string, required: true, help: "List name to add the reminder to"), .init(name: "title", type: .string, required: true, help: "Reminder title"), .init(name: "due", type: .string, required: false, help: "Due date (ISO 8601, e.g. 2026-02-18 or 2026-02-18T10:00:00Z)"), .init(name: "priority", type: .integer, required: false, help: "Priority: 0=none, 1=high, 5=medium, 9=low (default: 0)"), .init(name: "notes", type: .string, required: false, help: "Notes for the reminder")]),
        .init(name: "reminders.complete", application: "Reminders", summary: "Mark a reminder as completed.", parameters: [.init(name: "id", type: .string, required: true, help: "Reminder ID (from reminders command output)")]),
        .init(name: "reminders.delete", application: "Reminders", summary: "Delete a reminder.", parameters: [.init(name: "id", type: .string, required: true, help: "Reminder ID (from reminders command output)")]),
        .init(name: "reminders.delete_list", application: "Reminders", summary: "Delete a reminder list.", parameters: [.init(name: "id", type: .string, required: true, help: "List ID (from reminder-lists command output)"), .init(name: "force", type: .boolean, required: false, help: "Delete even if the list has reminders")]),
        .init(name: "files.list", application: "Files", summary: "List directory contents with metadata.", parameters: [.init(name: "path", type: .string, required: false, help: "Directory path (relative to ~ or absolute)"), .init(name: "recursive", type: .boolean, required: false, help: "List recursively"), .init(name: "depth", type: .integer, required: false, help: "Max recursion depth (default: 3)")]),
        .init(name: "files.info", application: "Files", summary: "Get detailed file or folder metadata.", parameters: [.init(name: "path", type: .string, required: true, help: "File path (relative to ~ or absolute)")]),
        .init(name: "files.search", application: "Files", summary: "Search files using Spotlight.", parameters: [.init(name: "query", type: .string, required: true, help: "Search query (Spotlight syntax)"), .init(name: "kind", type: .string, required: false, help: "Filter by kind: folder, image, pdf, document, audio, video, presentation, spreadsheet"), .init(name: "scope", type: .string, required: false, help: "Search scope directory (relative to ~ or absolute)")]),
        .init(name: "files.read", application: "Files", summary: "Read and extract text from a file.", parameters: [.init(name: "path", type: .string, required: true, help: "File path (relative to ~ or absolute)")]),
        .init(name: "files.move", application: "Files", summary: "Move or rename files and folders.", parameters: [.init(name: "items", type: .string, required: true, help: "JSON array of {\"source\": \"...\", \"destination\": \"...\"} pairs")]),
        .init(name: "files.copy", application: "Files", summary: "Copy a file or folder.", parameters: [.init(name: "source", type: .string, required: true, help: "Source path"), .init(name: "dest", type: .string, required: true, help: "Destination path")]),
        .init(name: "files.create_folder", application: "Files", summary: "Create a directory with intermediate directories.", parameters: [.init(name: "path", type: .string, required: true, help: "Directory path to create")]),
        .init(name: "files.trash", application: "Files", summary: "Move a file or folder to Trash.", parameters: [.init(name: "path", type: .string, required: true, help: "File or folder path to trash")]),
        .init(name: "numbers.search", application: "Numbers", summary: "Search for Numbers spreadsheets using Spotlight.", parameters: [.init(name: "query", type: .string, required: true, help: "Search query"), .init(name: "limit", type: .integer, required: false, help: "Max results (default: 20)")]),
        .init(name: "numbers.read", application: "Numbers", summary: "Read cell data from a Numbers spreadsheet as JSON.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .numbers file"), .init(name: "sheet", type: .string, required: false, help: "Sheet name (default: first sheet)"), .init(name: "table", type: .string, required: false, help: "Table name (default: first table)"), .init(name: "range", type: .string, required: false, help: "Cell range in A1 notation (e.g. A1:C10)")]),
        .init(name: "numbers.write", application: "Numbers", summary: "Write data to cells in a Numbers spreadsheet.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .numbers file"), .init(name: "sheet", type: .string, required: false, help: "Sheet name (default: first sheet)"), .init(name: "table", type: .string, required: false, help: "Table name (default: first table)"), .init(name: "range", type: .string, required: false, help: "Starting cell in A1 notation (e.g. A1)"), .init(name: "data", type: .string, required: true, help: "JSON array of arrays with cell data")]),
        .init(name: "numbers.create", application: "Numbers", summary: "Create a new Numbers spreadsheet.", parameters: [.init(name: "file", type: .string, required: true, help: "Output file path"), .init(name: "data", type: .string, required: false, help: "Initial data as JSON array of arrays"), .init(name: "template", type: .string, required: false, help: "Template name")]),
        .init(name: "numbers.list_sheets", application: "Numbers", summary: "List all sheets and tables in a Numbers document.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .numbers file")]),
        .init(name: "numbers.add_sheet", application: "Numbers", summary: "Add a new sheet to a Numbers document.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .numbers file"), .init(name: "name", type: .string, required: true, help: "Name for the new sheet")]),
        .init(name: "numbers.remove_sheet", application: "Numbers", summary: "Remove a sheet from a Numbers document.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .numbers file"), .init(name: "name", type: .string, required: true, help: "Sheet name to remove")]),
        .init(name: "numbers.get_formulas", application: "Numbers", summary: "Read formulas from cells in a Numbers spreadsheet.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .numbers file"), .init(name: "sheet", type: .string, required: false, help: "Sheet name (default: first sheet)"), .init(name: "table", type: .string, required: false, help: "Table name (default: first table)"), .init(name: "range", type: .string, required: false, help: "Cell range in A1 notation")]),
        .init(name: "numbers.export", application: "Numbers", summary: "Export a Numbers spreadsheet to CSV, PDF, or Excel.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .numbers file"), .init(name: "format", type: .string, required: true, help: "Export format: csv, pdf, xlsx"), .init(name: "dest", type: .string, required: false, help: "Output file path (default: same name with new extension)")]),
        .init(name: "numbers.info", application: "Numbers", summary: "Get metadata about a Numbers spreadsheet.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .numbers file")]),
        .init(name: "pages.search", application: "Pages", summary: "Search for Pages documents using Spotlight.", parameters: [.init(name: "query", type: .string, required: true, help: "Search query"), .init(name: "limit", type: .integer, required: false, help: "Max results (default: 20)")]),
        .init(name: "pages.read", application: "Pages", summary: "Read body text from a Pages document.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .pages file")]),
        .init(name: "pages.write", application: "Pages", summary: "Set the body text of a Pages document.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .pages file"), .init(name: "text", type: .string, required: true, help: "Text to write")]),
        .init(name: "pages.create", application: "Pages", summary: "Create a new Pages document.", parameters: [.init(name: "file", type: .string, required: true, help: "Output file path"), .init(name: "text", type: .string, required: false, help: "Initial body text"), .init(name: "template", type: .string, required: false, help: "Template name")]),
        .init(name: "pages.find_replace", application: "Pages", summary: "Find and replace text in a Pages document.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .pages file"), .init(name: "find", type: .string, required: true, help: "Text to find"), .init(name: "replace", type: .string, required: true, help: "Replacement text"), .init(name: "all", type: .boolean, required: false, help: "Replace all occurrences")]),
        .init(name: "pages.insert_table", application: "Pages", summary: "Insert a table into a Pages document.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .pages file"), .init(name: "data", type: .string, required: true, help: "Table data as JSON array of arrays")]),
        .init(name: "pages.list_sections", application: "Pages", summary: "List sections in a Pages document with previews.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .pages file")]),
        .init(name: "pages.export", application: "Pages", summary: "Export a Pages document to PDF, Word, TXT, or EPUB.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .pages file"), .init(name: "format", type: .string, required: true, help: "Export format: pdf, docx, txt, epub"), .init(name: "dest", type: .string, required: false, help: "Output file path (default: same name with new extension)")]),
        .init(name: "pages.info", application: "Pages", summary: "Get metadata about a Pages document.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .pages file")]),
        .init(name: "keynote.search", application: "Keynote", summary: "Search for Keynote presentations using Spotlight.", parameters: [.init(name: "query", type: .string, required: true, help: "Search query"), .init(name: "limit", type: .integer, required: false, help: "Max results (default: 20)")]),
        .init(name: "keynote.read", application: "Keynote", summary: "Read slide content from a Keynote presentation.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .key file"), .init(name: "slide", type: .integer, required: false, help: "Slide index (1-based, omit to read all)")]),
        .init(name: "keynote.create", application: "Keynote", summary: "Create a new Keynote presentation.", parameters: [.init(name: "file", type: .string, required: true, help: "Output file path"), .init(name: "theme", type: .string, required: false, help: "Theme name")]),
        .init(name: "keynote.add_slide", application: "Keynote", summary: "Add a slide to a Keynote presentation.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .key file"), .init(name: "layout", type: .string, required: false, help: "Slide layout name"), .init(name: "title", type: .string, required: false, help: "Slide title"), .init(name: "body", type: .string, required: false, help: "Slide body text"), .init(name: "notes", type: .string, required: false, help: "Presenter notes"), .init(name: "position", type: .integer, required: false, help: "Insert after this slide index (1-based)")]),
        .init(name: "keynote.edit_slide", application: "Keynote", summary: "Edit an existing slide in a Keynote presentation.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .key file"), .init(name: "slide", type: .integer, required: true, help: "Slide index (1-based)"), .init(name: "title", type: .string, required: false, help: "New title text"), .init(name: "body", type: .string, required: false, help: "New body text"), .init(name: "notes", type: .string, required: false, help: "New presenter notes")]),
        .init(name: "keynote.remove_slide", application: "Keynote", summary: "Remove a slide from a Keynote presentation.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .key file"), .init(name: "slide", type: .integer, required: true, help: "Slide index to remove (1-based)")]),
        .init(name: "keynote.reorder_slides", application: "Keynote", summary: "Move a slide to a new position.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .key file"), .init(name: "from", type: .integer, required: true, help: "Current slide index (1-based)"), .init(name: "to", type: .integer, required: true, help: "Target slide index (1-based)")]),
        .init(name: "keynote.list_slides", application: "Keynote", summary: "List all slides in a Keynote presentation.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .key file")]),
        .init(name: "keynote.list_themes", application: "Keynote", summary: "List all available Keynote themes.", parameters: []),
        .init(name: "keynote.export", application: "Keynote", summary: "Export a Keynote presentation to PDF, PowerPoint, PNG, or JPEG.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .key file"), .init(name: "format", type: .string, required: true, help: "Export format: pdf, pptx, png, jpeg"), .init(name: "dest", type: .string, required: false, help: "Output file or directory path"), .init(name: "slide", type: .integer, required: false, help: "Export only this slide index (1-based, for image formats)")]),
        .init(name: "keynote.info", application: "Keynote", summary: "Get metadata about a Keynote presentation.", parameters: [.init(name: "file", type: .string, required: true, help: "Path to .key file")]),
        .init(name: "notes.folders", application: "Notes", summary: "List all Notes folders grouped by account.", parameters: []),
        .init(name: "notes.list", application: "Notes", summary: "List notes, optionally filtered by folder and account.", parameters: [.init(name: "folder", type: .string, required: false, help: "Folder name"), .init(name: "account", type: .string, required: false, help: "Account name (required when folder is ambiguous)"), .init(name: "limit", type: .integer, required: false, help: "Max results (default: 50)")]),
        .init(name: "notes.search", application: "Notes", summary: "Search notes by title, body, or both.", parameters: [.init(name: "query", type: .string, required: true, help: "Search query"), .init(name: "searchIn", type: .string, required: false, help: "Search titles only. Read a specific note for its body."), .init(name: "limit", type: .integer, required: false, help: "Max results (default: 20)")]),
        .init(name: "notes.read", application: "Notes", summary: "Read a note's full content by ID.", parameters: [.init(name: "id", type: .string, required: true, help: "Note ID (from notes-list or notes-search)"), .init(name: "maxBodyLength", type: .integer, required: false, help: "Max body characters (default: 8000, maximum 8000)")]),
        .init(name: "contacts.groups", application: "Contacts", summary: "List all contact groups with member counts.", parameters: []),
        .init(name: "contacts.search", application: "Contacts", summary: "Search contacts by name, email, or phone.", parameters: [.init(name: "query", type: .string, required: true, help: "Search query"), .init(name: "limit", type: .integer, required: false, help: "Max results (default: 20)")]),
        .init(name: "contacts.read", application: "Contacts", summary: "Read a contact's full details by ID.", parameters: [.init(name: "id", type: .string, required: true, help: "Contact ID (from contacts-search)")]),
    ]
}

enum OrchardDispatch {
    static func call(_ name: String, _ p: [String: JSONValue]) async throws {
        switch name {
        case "calendar.list_calendars":

            await CalendarBridge.listCalendars()
        case "calendar.list_events":
            let start: String = try p.string("start")
            let end: String = try p.string("end")
            let calendar: String? = p["calendar"]?.string
            await CalendarBridge.listEvents(startISO: start, endISO: end, calendarID: calendar)
        case "calendar.search":
            let query: String = try p.string("query")
            let start: String = try p.string("start")
            let end: String = try p.string("end")
            await CalendarBridge.searchEvents(query: query, startISO: start, endISO: end)
        case "mail.accounts":

            MailBridge.listAccounts()
        case "mail.unread":
            let limit: Int = p["limit"]?.integer ?? 10
            MailBridge.unreadSummary(limit: limit)
        case "mail.search":
            let query: String = try p.string("query")
            let account: String? = p["account"]?.string
            let mailbox: String? = p["mailbox"]?.string
            let limit: Int = p["limit"]?.integer ?? 20
            let searchIn: String = p["searchIn"]?.string ?? "all"
            let offset: Int? = p["offset"]?.integer
            MailBridge.search(query: query, account: account, mailbox: mailbox, limit: limit, searchIn: searchIn, offset: offset)
        case "mail.message":
            let id: String = try p.string("id")
            let account: String? = p["account"]?.string
            let mailbox: String? = p["mailbox"]?.string
            let maxBodyLength: Int = p["maxBodyLength"]?.integer ?? 4000
            MailBridge.readMessage(messageId: id, maxBodyLength: maxBodyLength, account: account, mailbox: mailbox)
        case "mail.flagged":
            let limit: Int = p["limit"]?.integer ?? 20
            let offset: Int? = p["offset"]?.integer
            MailBridge.flagged(limit: limit, offset: offset)
        case "mail.create_draft":
            let to: String = try p.string("to")
            let cc: String? = p["cc"]?.string
            let bcc: String? = p["bcc"]?.string
            let subject: String = try p.string("subject")
            let body: String = try p.string("body")
            let account: String? = p["account"]?.string
            let toAddrs = to.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    let ccAddrs = cc?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    let bccAddrs = bcc?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    MailBridge.createDraft(to: toAddrs, cc: ccAddrs, bcc: bccAddrs, subject: subject, body: body, account: account)
        case "mail.save_attachment":
            let id: String = try p.string("id")
            let account: String? = p["account"]?.string
            let mailbox: String? = p["mailbox"]?.string
            let index: Int = try p.int("index")
            let path: String = p["path"]?.string ?? NSHomeDirectory() + "/Downloads"
            MailBridge.saveAttachment(messageId: id, index: index, outputDir: path, account: account, mailbox: mailbox)
        case "reminders.lists":

            await RemindersBridge.listLists()
        case "reminders.list":
            let list: String? = p["list"]?.string
            let filter: String = p["filter"]?.string ?? "incomplete"
            let limit: Int = p["limit"]?.integer ?? 50
            await RemindersBridge.listReminders(listName: list, filter: filter, limit: limit)
        case "reminders.today":

            await RemindersBridge.today()
        case "reminders.create_list":
            let name: String = try p.string("name")
            await RemindersBridge.createList(name: name)
        case "reminders.create":
            let list: String = try p.string("list")
            let title: String = try p.string("title")
            let due: String? = p["due"]?.string
            let priority: Int = p["priority"]?.integer ?? 0
            let notes: String? = p["notes"]?.string
            await RemindersBridge.createReminder(listName: list, title: title, dueDate: due, priority: priority, notes: notes)
        case "reminders.complete":
            let id: String = try p.string("id")
            await RemindersBridge.completeReminder(id: id)
        case "reminders.delete":
            let id: String = try p.string("id")
            await RemindersBridge.deleteReminder(id: id)
        case "reminders.delete_list":
            let id: String = try p.string("id")
            let force: Bool = p["force"]?.boolean ?? false
            await RemindersBridge.deleteList(id: id, force: force)
        case "files.list":
            let path: String = p["path"]?.string ?? "."
            let recursive: Bool = p["recursive"]?.boolean ?? false
            let depth: Int = p["depth"]?.integer ?? 3
            FilesBridge.list(path: path, recursive: recursive, depth: depth)
        case "files.info":
            let path: String = try p.string("path")
            FilesBridge.info(path: path)
        case "files.search":
            let query: String = try p.string("query")
            let kind: String? = p["kind"]?.string
            let scope: String? = p["scope"]?.string
            FilesBridge.search(query: query, kind: kind, scope: scope)
        case "files.read":
            let path: String = try p.string("path")
            FilesBridge.read(path: path)
        case "files.move":
            let items: String = try p.string("items")
            FilesBridge.move(itemsJSON: items)
        case "files.copy":
            let source: String = try p.string("source")
            let dest: String = try p.string("dest")
            FilesBridge.copy(source: source, destination: dest)
        case "files.create_folder":
            let path: String = try p.string("path")
            FilesBridge.createFolder(path: path)
        case "files.trash":
            let path: String = try p.string("path")
            FilesBridge.trash(path: path)
        case "numbers.search":
            let query: String = try p.string("query")
            let limit: Int = p["limit"]?.integer ?? 20
            NumbersBridge.search(query: query, limit: limit)
        case "numbers.read":
            let file: String = try p.string("file")
            let sheet: String? = p["sheet"]?.string
            let table: String? = p["table"]?.string
            let range: String? = p["range"]?.string
            NumbersBridge.read(file: file, sheet: sheet, table: table, range: range)
        case "numbers.write":
            let file: String = try p.string("file")
            let sheet: String? = p["sheet"]?.string
            let table: String? = p["table"]?.string
            let range: String? = p["range"]?.string
            let data: String = try p.string("data")
            NumbersBridge.write(file: file, sheet: sheet, table: table, range: range, dataJSON: data)
        case "numbers.create":
            let file: String = try p.string("file")
            let data: String? = p["data"]?.string
            let template: String? = p["template"]?.string
            NumbersBridge.create(file: file, dataJSON: data, template: template)
        case "numbers.list_sheets":
            let file: String = try p.string("file")
            NumbersBridge.listSheets(file: file)
        case "numbers.add_sheet":
            let file: String = try p.string("file")
            let name: String = try p.string("name")
            NumbersBridge.addSheet(file: file, name: name)
        case "numbers.remove_sheet":
            let file: String = try p.string("file")
            let name: String = try p.string("name")
            NumbersBridge.removeSheet(file: file, name: name)
        case "numbers.get_formulas":
            let file: String = try p.string("file")
            let sheet: String? = p["sheet"]?.string
            let table: String? = p["table"]?.string
            let range: String? = p["range"]?.string
            NumbersBridge.getFormulas(file: file, sheet: sheet, table: table, range: range)
        case "numbers.export":
            let file: String = try p.string("file")
            let format: String = try p.string("format")
            let dest: String? = p["dest"]?.string
            NumbersBridge.export(file: file, format: format, dest: dest)
        case "numbers.info":
            let file: String = try p.string("file")
            NumbersBridge.info(file: file)
        case "pages.search":
            let query: String = try p.string("query")
            let limit: Int = p["limit"]?.integer ?? 20
            PagesBridge.search(query: query, limit: limit)
        case "pages.read":
            let file: String = try p.string("file")
            PagesBridge.read(file: file)
        case "pages.write":
            let file: String = try p.string("file")
            let text: String = try p.string("text")
            PagesBridge.write(file: file, text: text)
        case "pages.create":
            let file: String = try p.string("file")
            let text: String? = p["text"]?.string
            let template: String? = p["template"]?.string
            PagesBridge.create(file: file, text: text, template: template)
        case "pages.find_replace":
            let file: String = try p.string("file")
            let find: String = try p.string("find")
            let replace: String = try p.string("replace")
            let all: Bool = p["all"]?.boolean ?? false
            PagesBridge.findReplace(file: file, find: find, replace: replace, all: all)
        case "pages.insert_table":
            let file: String = try p.string("file")
            let data: String = try p.string("data")
            PagesBridge.insertTable(file: file, dataJSON: data)
        case "pages.list_sections":
            let file: String = try p.string("file")
            PagesBridge.listSections(file: file)
        case "pages.export":
            let file: String = try p.string("file")
            let format: String = try p.string("format")
            let dest: String? = p["dest"]?.string
            PagesBridge.export(file: file, format: format, dest: dest)
        case "pages.info":
            let file: String = try p.string("file")
            PagesBridge.info(file: file)
        case "keynote.search":
            let query: String = try p.string("query")
            let limit: Int = p["limit"]?.integer ?? 20
            KeynoteBridge.search(query: query, limit: limit)
        case "keynote.read":
            let file: String = try p.string("file")
            let slide: Int? = p["slide"]?.integer
            KeynoteBridge.read(file: file, slideIndex: slide)
        case "keynote.create":
            let file: String = try p.string("file")
            let theme: String? = p["theme"]?.string
            KeynoteBridge.create(file: file, theme: theme)
        case "keynote.add_slide":
            let file: String = try p.string("file")
            let layout: String? = p["layout"]?.string
            let title: String? = p["title"]?.string
            let body: String? = p["body"]?.string
            let notes: String? = p["notes"]?.string
            let position: Int? = p["position"]?.integer
            KeynoteBridge.addSlide(file: file, layout: layout, title: title, body: body, notes: notes, position: position)
        case "keynote.edit_slide":
            let file: String = try p.string("file")
            let slide: Int = try p.int("slide")
            let title: String? = p["title"]?.string
            let body: String? = p["body"]?.string
            let notes: String? = p["notes"]?.string
            KeynoteBridge.editSlide(file: file, slideIndex: slide, title: title, body: body, notes: notes)
        case "keynote.remove_slide":
            let file: String = try p.string("file")
            let slide: Int = try p.int("slide")
            KeynoteBridge.removeSlide(file: file, slideIndex: slide)
        case "keynote.reorder_slides":
            let file: String = try p.string("file")
            let from: Int = try p.int("from")
            let to: Int = try p.int("to")
            KeynoteBridge.reorderSlides(file: file, from: from, to: to)
        case "keynote.list_slides":
            let file: String = try p.string("file")
            KeynoteBridge.read(file: file, slideIndex: nil)
        case "keynote.list_themes":

            KeynoteBridge.listThemes()
        case "keynote.export":
            let file: String = try p.string("file")
            let format: String = try p.string("format")
            let dest: String? = p["dest"]?.string
            let slide: Int? = p["slide"]?.integer
            KeynoteBridge.export(file: file, format: format, dest: dest, slideIndex: slide)
        case "keynote.info":
            let file: String = try p.string("file")
            KeynoteBridge.info(file: file)
        case "notes.folders":

            NotesBridge.listFolders()
        case "notes.list":
            let folder: String? = p["folder"]?.string
            let account: String? = p["account"]?.string
            let limit: Int = p["limit"]?.integer ?? 50
            NotesBridge.listNotes(folder: folder, account: account, limit: limit)
        case "notes.search":
            let query: String = try p.string("query")
            let searchIn: String = p["searchIn"]?.string ?? "title"
            let limit: Int = p["limit"]?.integer ?? 20
            NotesBridge.search(query: query, limit: limit, searchIn: searchIn)
        case "notes.read":
            let id: String = try p.string("id")
            let maxBodyLength: Int = p["maxBodyLength"]?.integer ?? 4000
            NotesBridge.readNote(id: id, maxBodyLength: maxBodyLength)
        case "contacts.groups":

            await ContactsBridge.listGroups()
        case "contacts.search":
            let query: String = try p.string("query")
            let limit: Int = p["limit"]?.integer ?? 20
            await ContactsBridge.search(query: query, limit: limit)
        case "contacts.read":
            let id: String = try p.string("id")
            await ContactsBridge.readContact(id: id)
        default: throw JuliaError("Unknown tool: \(name)")
        }
    }
}
