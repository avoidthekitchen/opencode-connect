import AppKit
import CoreImage.CIFilterBuiltins
import OpenCodeConnectCore
import SwiftUI

struct MenuPopoverView: View {
    let coordinator: AccessCoordinator
    @State private var showingEnrollment = false
    @State private var showingDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(coordinator.viewModel.observedState.title)
                    .font(.headline)
                Text(coordinator.viewModel.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let warning = coordinator.viewModel.availabilityWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 8) {
                ForEach(coordinator.viewModel.components, id: \.name) { component in
                    HStack {
                        Image(systemName: component.status == .ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(component.status == .ready ? .green : .orange)
                        Text(component.name)
                        Spacer()
                        Text(component.detail)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Button(primaryActionTitle) {
                    Task { await performPrimaryAction() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                if coordinator.viewModel.observedState == .error
                    || (coordinator.viewModel.observedState == .conflict
                        && coordinator.viewModel.desiredState == .enabled)
                {
                    Button("Stop") { Task { await coordinator.handle(.stop) } }
                        .controlSize(.large)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("iPhone Enrollment")
                    .font(.subheadline.weight(.semibold))
                HStack {
                    Button("Show QR Code") { showingEnrollment = true }
                    Button("Copy URL") {
                        Task { await coordinator.handle(.copyEndpoint) }
                    }
                    Button("Open Endpoint") {
                        Task { await coordinator.handle(.openEndpoint) }
                    }
                }
                .disabled(coordinator.viewModel.enrollment.endpoint == nil)

                if coordinator.viewModel.enrollment.endpoint == nil {
                    Text("Available after the Endpoint is verified.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let warning = coordinator.viewModel.enrollment.endpointChangeWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            HStack {
                Button("Choose OpenCode…") { chooseExecutable(for: .openCode) }
                    .disabled(coordinator.viewModel.desiredState != .disabled)
                Button("Choose Tailscale…") { chooseExecutable(for: .tailscale) }
                    .disabled(coordinator.viewModel.desiredState != .disabled)
                SettingsLink { Text("Settings…") }
                Button("Diagnostics…") {
                    Task {
                        await coordinator.handle(.reviewDiagnostics)
                        showingDiagnostics = true
                    }
                }
            }

            HStack {
                Text("Tailscale is also required on your iPhone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 390)
        .sheet(isPresented: $showingEnrollment) {
            EnrollmentView(
                enrollment: coordinator.viewModel.enrollment,
                revealCredential: { Task { await coordinator.handle(.revealCredential) } },
                copyCredential: { Task { await coordinator.handle(.copyCredential) } }
            )
        }
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsReviewView(
                review: coordinator.viewModel.diagnosticsReview,
                copy: { Task { await coordinator.handle(.copyDiagnostics) } }
            )
        }
    }

    private var primaryActionTitle: String {
        switch coordinator.viewModel.primaryAction {
        case .start: "Start"
        case .stop: "Stop"
        case .retry: "Retry"
        case .retryReadiness: "Retry"
        case .retryConflict: "Retry Inspection"
        case .completeTailscaleSetup: "Complete Tailscale Setup"
        }
    }

    private func performPrimaryAction() async {
        switch coordinator.viewModel.primaryAction {
        case .start:
            await coordinator.handle(.start)
        case .stop:
            await coordinator.handle(.stop)
        case .retry:
            await coordinator.handle(.retry)
        case .retryReadiness:
            await coordinator.handle(.evaluateReadiness)
        case .retryConflict:
            await coordinator.handle(.retryConflict)
        case .completeTailscaleSetup:
            await coordinator.handle(.completeTailscaleSetup)
        }
    }

    private func chooseExecutable(for dependency: Dependency) {
        guard let url = ExecutablePicker.chooseFile() else { return }
        Task {
            switch dependency {
            case .openCode:
                await coordinator.handle(.selectCustomOpenCodePath(url.path))
            case .tailscale:
                await coordinator.handle(.selectCustomTailscalePath(url.path))
            }
        }
    }

    private enum Dependency {
        case openCode
        case tailscale
    }
}

struct DiagnosticsReviewView: View {
    let review: DiagnosticsReview?
    let copy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Diagnostics").font(.title2.weight(.semibold))
            if let review {
                Label(review.warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                ScrollView {
                    Text(review.text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Copy Diagnostics", action: copy)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 620, height: 520)
    }
}

struct EnrollmentView: View {
    let enrollment: EnrollmentViewState
    let revealCredential: () -> Void
    let copyCredential: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enroll an iPhone")
                .font(.title2.weight(.semibold))

            if let payload = enrollment.qrPayload, let image = qrCode(for: payload) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
                    .accessibilityLabel("Verified Endpoint QR code")
            }

            if let username = enrollment.username {
                LabeledContent("Username", value: username)
                HStack {
                    if let credential = enrollment.revealedCredential {
                        Text(credential)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .accessibilityLabel("Revealed Access Credential")
                    } else {
                        Text("•••••• •••••• •••••• •••••• •••••• ••••••")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Access Credential hidden")
                    }
                    Spacer()
                    Button("Reveal Password", action: revealCredential)
                    Button("Copy Password", action: copyCredential)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(enrollment.guidance.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.callout)
        }
        .padding(20)
        .frame(width: 460)
    }

    private func qrCode(for payload: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else {
            return nil
        }
        let representation = NSCIImageRep(ciImage: output)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}

private extension ObservedState {
    var title: String {
        switch self {
        case .stopped: "Stopped"
        case .needsSetup: "Needs Setup"
        case .starting: "Starting"
        case .available: "Available"
        case .degraded: "Degraded"
        case .stopping: "Stopping"
        case .conflict: "Conflict"
        case .error: "Error"
        }
    }
}
