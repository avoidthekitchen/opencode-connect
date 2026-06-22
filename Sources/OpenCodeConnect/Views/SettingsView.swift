import OpenCodeConnectCore
import SwiftUI

struct SettingsView: View {
    let coordinator: AccessCoordinator

    @State private var username: String
    @State private var backendPort: String
    @State private var httpsPort: String
    @State private var showingTailnetWarning = false
    @State private var showingDeleteConfirmation = false

    init(coordinator: AccessCoordinator) {
        self.coordinator = coordinator
        _username = State(initialValue: coordinator.settingsViewModel.accessUsername)
        _backendPort = State(initialValue: String(coordinator.settingsViewModel.backendPort))
        _httpsPort = State(initialValue: String(coordinator.settingsViewModel.httpsPort))
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: launchAtLogin)
                Picker("Availability Policy", selection: availabilityPolicy) {
                    Text("On External Power").tag(AvailabilityPolicy.onExternalPower)
                    Text("Always").tag(AvailabilityPolicy.always)
                    Text("Never").tag(AvailabilityPolicy.never)
                }
                Text("Idle-sleep prevention does not guarantee availability while a MacBook lid is closed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Access") {
                Picker("Access mode", selection: accessMode) {
                    Text("Protected Access").tag(AccessMode.protected)
                    Text("Tailnet-Only Access (Advanced)").tag(AccessMode.tailnetOnly)
                }
                Text("Protected Access adds OpenCode Basic Auth to tailnet authorization.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Username", text: $username)
                    .onSubmit { send(.updateUsername(username)) }
                    .disabled(!isEditable || coordinator.settingsViewModel.accessMode != .protected)
            }

            Section("Access Credential") {
                HStack {
                    Button("Rotate Credential") { send(.rotateCredential) }
                    Button("Delete Credential…", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }
                .disabled(!isEditable)
                Text("Rotation requires updating the saved login on your iPhone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Advanced") {
                TextField("OpenCode backend port", text: $backendPort)
                TextField("Serve HTTPS port", text: $httpsPort)
                Button("Apply Ports") {
                    guard let backend = Int(backendPort), let https = Int(httpsPort) else { return }
                    send(.updatePorts(backend: backend, https: https))
                }

                HStack {
                    Button("Choose OpenCode…") { chooseExecutable(for: .openCode) }
                    Button("Choose Tailscale…") { chooseExecutable(for: .tailscale) }
                }
            }
            .disabled(!isEditable)

            Section {
                Button("Reset to Defaults", role: .destructive) { send(.resetToDefaults) }
                    .disabled(!isEditable)
                if let message = coordinator.settingsViewModel.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !isEditable {
                    Text("Stop access before changing operational settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 520, height: 560)
        .navigationTitle("OpenCode Connect Settings")
        .confirmationDialog(
            "Use Tailnet-Only Access?",
            isPresented: $showingTailnetWarning,
            titleVisibility: .visible
        ) {
            Button("Accept Reduced Defense", role: .destructive) {
                send(.confirmTailnetOnlyAccess)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("OpenCode Basic Auth will be disabled. Tailnet policy becomes the only access check. Loopback binding remains enforced and Funnel remains unsupported.")
        }
        .confirmationDialog(
            "Delete the Access Credential?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Credential", role: .destructive) { send(.deleteCredential) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Protected Access will generate a new six-word credential the next time it starts.")
        }
        .onChange(of: coordinator.settingsViewModel) { _, settings in
            username = settings.accessUsername
            backendPort = String(settings.backendPort)
            httpsPort = String(settings.httpsPort)
        }
    }

    private var isEditable: Bool { coordinator.viewModel.desiredState == .disabled }

    private var accessMode: Binding<AccessMode> {
        Binding(
            get: { coordinator.settingsViewModel.accessMode },
            set: { mode in
                if mode == .tailnetOnly {
                    send(.requestAccessMode(.tailnetOnly))
                    showingTailnetWarning = true
                } else {
                    send(.requestAccessMode(.protected))
                }
            }
        )
    }

    private var availabilityPolicy: Binding<AvailabilityPolicy> {
        Binding(
            get: { coordinator.settingsViewModel.availabilityPolicy },
            set: { send(.updateAvailabilityPolicy($0)) }
        )
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { coordinator.settingsViewModel.launchAtLogin },
            set: { send(.updateLaunchAtLogin($0)) }
        )
    }

    private func send(_ event: AccessEvent) {
        Task { await coordinator.handle(event) }
    }

    private func chooseExecutable(for dependency: Dependency) {
        guard let path = ExecutablePicker.chooseFile()?.path else { return }
        switch dependency {
        case .openCode: send(.selectCustomOpenCodePath(path))
        case .tailscale: send(.selectCustomTailscalePath(path))
        }
    }

    private enum Dependency { case openCode, tailscale }
}
