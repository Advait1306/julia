import SwiftUI
import Combine
import AppKit
import JuliaKit

private enum Palette {
    static let surface = Color(red: 0.12, green: 0.12, blue: 0.13)
    static let inset = Color(red: 0.16, green: 0.16, blue: 0.17)
    static let ink = Color(red: 0.94, green: 0.94, blue: 0.95)
    static let muted = Color(red: 0.57, green: 0.57, blue: 0.61)
    static let accent = Color(red: 0.59, green: 0.64, blue: 0.95)
}

struct ContentView: View {
    @ObservedObject var assistant: AssistantState
    @FocusState private var inputFocused: Bool
    @State private var showTrace = false
    @State private var selectedEvent: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: "command")
                    .font(.system(size: 23, weight: .medium)).foregroundStyle(Palette.accent)
                    .frame(width: 42, height: 42)
                    .background(Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                TextField("What can I do for you?", text: $assistant.input)
                    .textFieldStyle(.plain).font(.system(size: 22)).foregroundStyle(Palette.ink)
                    .focused($inputFocused).onSubmit { assistant.submit() }.accessibilityLabel("Command")
                if assistant.busy {
                    Button { assistant.cancel() } label: { Image(systemName: "stop.fill").font(.system(size: 13)) }
                        .buttonStyle(.plain).foregroundStyle(Palette.muted).help("Stop command").accessibilityLabel("Stop command")
                } else {
                    Button { assistant.submit() } label: { Image(systemName: "arrow.turn.down.left").font(.system(size: 17)) }
                        .buttonStyle(.plain).foregroundStyle(Palette.muted)
                        .disabled(assistant.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).help("Run command")
                }
            }.padding(.horizontal, 24).padding(.vertical, 23)
            Divider()
            if showTrace { traceView }
            else if !assistant.answer.isEmpty || assistant.busy || assistant.error != nil { responseView }
            else { suggestions }
            Divider()
            footer
        }
        .background(Palette.surface).clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .preferredColorScheme(.dark).frame(width: 740, height: 490)
        .onAppear { inputFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .juliaPanelOpened)) { _ in inputFocused = true }
        .onExitCommand { NSApp.keyWindow?.orderOut(nil) }
    }
    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("A little help, right here.").font(.system(size: 13, weight: .medium))
                Spacer()
                Text("On your Mac").font(.system(size: 12))
            }.foregroundStyle(Palette.muted).padding(.horizontal, 13).padding(.bottom, 13)
            suggestion("What's on my calendar today?", symbol: "calendar", app: "Calendar")
            suggestion("Show my reminders due today", symbol: "checklist", app: "Reminders")
            suggestion("List the files in my Downloads folder", symbol: "folder", app: "Files")
            suggestion("Find notes about my projects", symbol: "note.text", app: "Notes")
            Spacer(minLength: 6)
            if !assistant.ready {
                HStack(spacing: 9) {
                    if assistant.preparing { ProgressView().controlSize(.small).scaleEffect(0.75) }
                    Text(assistant.status).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Spacer()
                    if let progress = assistant.downloadProgress {
                        Text("\(Int(progress * 100))%").font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted)
                    }
                }.padding(.horizontal, 13)
                if let progress = assistant.downloadProgress { ProgressView(value: progress).tint(Palette.accent).padding(.horizontal, 13) }
            }
        }.padding(18).frame(maxHeight: .infinity)
    }
    private func suggestion(_ text: String, symbol: String, app: String) -> some View {
        SuggestionRow(text: text, symbol: symbol, application: app) { assistant.input = text; assistant.submit() }
    }
    private var responseView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !assistant.lastCommand.isEmpty { Text(assistant.lastCommand).font(.system(size: 13)).foregroundStyle(Palette.muted) }
                if assistant.busy {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(assistant.status).font(.system(size: 14)).foregroundStyle(Palette.ink)
                    }.padding(.vertical, 8)
                    if let progress = assistant.downloadProgress { ProgressView(value: progress).tint(Palette.accent) }
                }
                if !assistant.answer.isEmpty {
                    Text(assistant.answer).font(.system(size: 16)).lineSpacing(6).foregroundStyle(Palette.ink)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error = assistant.error {
                    Label(error, systemImage: "exclamationmark.circle").font(.system(size: 14))
                        .foregroundStyle(Color(red: 0.98, green: 0.72, blue: 0.52)).textSelection(.enabled)
                    if !assistant.ready { Button("Retry model setup") { assistant.retryPreparation() }.buttonStyle(.bordered) }
                }
                if !assistant.usedApplications.isEmpty {
                    HStack(spacing: 7) {
                        ForEach(assistant.usedApplications, id: \.self) { app in
                            Text(app).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(Palette.inset, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }.padding(27).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxHeight: .infinity)
    }
    private var traceView: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(assistant.events.reversed()) { event in
                        Button { selectedEvent = event.id } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.kind).font(.system(size: 12, weight: .medium))
                                Text(event.payload["name"].string ?? event.payload["application"].string ?? "Step \(event.step.map(String.init) ?? "—")")
                                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                            }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedEvent == event.id ? Palette.inset : .clear, in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain)
                    }
                }.padding(8)
            }.frame(width: 210)
            Divider()
            ScrollView([.vertical, .horizontal]) {
                if let event = assistant.events.first(where: { $0.id == selectedEvent }) ?? assistant.events.last {
                    Text(pretty(event.payload)).font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                } else { Text("Model requests and tool calls appear here.").font(.system(size: 13)).foregroundStyle(Palette.muted).padding(20) }
            }
        }.frame(maxHeight: .infinity)
    }
    private func pretty(_ value: JSONValue) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? String(decoding: encoder.encode(value), as: UTF8.self)) ?? value.json
    }
    private var footer: some View {
        HStack(spacing: 9) {
            Circle().fill(assistant.ready ? Color(red: 0.48, green: 0.73, blue: 0.59) : Palette.muted).frame(width: 5, height: 5)
            Text("Qwen 3.5 0.8B").font(.system(size: 11, weight: .medium))
            Text("Local").font(.system(size: 10)).foregroundStyle(Palette.muted)
            Spacer()
            Button { assistant.newConversation(); inputFocused = true } label: { Image(systemName: "plus") }
                .help("New conversation (⌘N)").keyboardShortcut("n").disabled(assistant.busy)
            Button { showTrace.toggle() } label: {
                HStack(spacing: 5) { Image(systemName: "text.alignleft"); Text(showTrace ? "Assistant" : "Trace") }
            }.keyboardShortcut("l").help("Show trace (⌘L)")
            Button { assistant.revealLog() } label: { Image(systemName: "folder") }.help("Reveal log file")
            Text("esc").font(.system(size: 10)).padding(.horizontal, 5).padding(.vertical, 3)
                .background(Palette.inset, in: RoundedRectangle(cornerRadius: 4))
        }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.muted)
            .padding(.horizontal, 23).padding(.vertical, 13)
    }
}

private struct SuggestionRow: View {
    let text: String
    let symbol: String
    let application: String
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(Palette.muted).frame(width: 24)
                Text(text).font(.system(size: 14)).foregroundStyle(Palette.ink)
                Spacer()
                Text(application).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }.padding(.horizontal, 13).padding(.vertical, 13)
                .background(hovered ? Palette.inset : .clear, in: RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }
    }
}
