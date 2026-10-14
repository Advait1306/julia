import SwiftUI

struct PermissionsView: View {
    @ObservedObject var permissions: AppPermissions
    var showsSectionHeaders = true

    var body: some View {
        Form {
            Section {
                permissionRows(required: true)
            } header: {
                if showsSectionHeaders { Text("Required permissions") }
            }
            Section {
                permissionRows(required: false)
            } header: {
                if showsSectionHeaders { Text("Additional controls") }
            }
            if let error = permissions.errorMessage {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .task {
            // Menu-bar apps don't always become active on return from System Settings.
            while !Task.isCancelled {
                await permissions.refresh()
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
            }
        }
    }

    @ViewBuilder
    private func permissionRows(required: Bool) -> some View {
        ForEach(AppPermissions.Permission.allCases.filter { $0.required == required }) { permission in
            LabeledContent {
                if permissions.requesting == permission {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Requesting \(permission.title) access")
                } else {
                    Button(permissions.status(permission) == .allowed ? "Enabled" : "Enable…") {
                        Task { await permissions.request(permission) }
                    }
                    .disabled(permissions.status(permission) == .allowed || permissions.requesting != nil)
                    .accessibilityLabel("\(permissions.status(permission) == .allowed ? "Enabled" : "Enable") \(permission.title)")
                }
            } label: {
                Text(permission.title)
                Text(permission.detail)
            }
        }
    }
}
