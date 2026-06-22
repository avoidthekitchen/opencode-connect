import AppKit

@MainActor
enum ExecutablePicker {
    static func chooseFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Executable"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
