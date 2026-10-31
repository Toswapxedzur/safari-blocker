import AppKit
import SafariServices
import Sparkle

final class SafariVaultUpdates {
    static let shared = SafariVaultUpdates()
    private var controller: SPUStandardUpdaterController?
    var available: Bool { controller != nil }
    var autoInstall: Bool {
        guard let updater = controller?.updater else { return false }
        return updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates
    }
    private init() {}
    func start() {
        guard controller == nil,
              Bundle.main.object(forInfoDictionaryKey: "VaultEnvironment") as? String == "production",
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String == "https://customblocker.com/downloads/updates/safari/appcast.xml" else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
    func setAutoInstall(_ enabled: Bool) {
        guard let updater = controller?.updater else { return }
        if enabled {
            updater.automaticallyChecksForUpdates = true
            updater.automaticallyDownloadsUpdates = true
        } else {
            // Sparkle only permits changing automatic downloads while
            // automatic checks are enabled.
            updater.automaticallyDownloadsUpdates = false
            updater.automaticallyChecksForUpdates = false
        }
    }
    func checkManually() { controller?.checkForUpdates(nil) }
}

final class SafariVaultAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var status: NSTextField!
    private var heartbeat: Timer?
    private var autoUpdateCheckbox: NSButton?
    private let heartbeatGate = SafariHeartbeatGate()
    private var backgroundLaunch: Bool { CommandLine.arguments.contains("--background") }
    private var safariVersionSupported: Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else { return false }
        let version = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return SafariVersionGate.supportsDeveloperIDExtensions(version)
    }
    private var safariRequirementMessage: String {
        SafariNativeLanguage.text("safari.setup.minimumVersion",
                                  fallback: "Safari Vault requires Safari 18.4 or later. Update Safari to enable the extension.")
    }
    private var extensionID: String {
        Bundle.main.object(forInfoDictionaryKey: "VaultExtensionIdentifier") as? String ?? "com.adamancia.vault.safari.extension"
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        SafariVaultUpdates.shared.start()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.pulse() }
        pulse()
        if backgroundLaunch { NSApp.setActivationPolicy(.accessory); return }
        showOnboarding()
    }
    private func showOnboarding() {
        NSApp.setActivationPolicy(.regular)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 530, height: 430), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Safari Vault"
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(calibratedRed: 0.973, green: 0.980, blue: 0.988, alpha: 1)
        window.center()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = SafariNativeLanguage.language == "ar" ? .trailing : .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "Safari Vault")
        title.font = NSFont(name: "Arial Bold", size: 26) ?? .systemFont(ofSize: 26, weight: .semibold)
        let body = NSTextField(wrappingLabelWithString: safariVersionSupported
            ? SafariNativeLanguage.text("safari.setup.body", fallback: "Enable Safari Vault in Safari Extensions, then allow access to all websites. Browser blocking and custom rules work independently. Connect Mac Vault for tagging, shared groups and Activity.")
            : safariRequirementMessage)
        body.font = NSFont(name: "Arial", size: 14) ?? .systemFont(ofSize: 14)
        body.alignment = SafariNativeLanguage.language == "ar" ? .right : .left
        let button = NSButton(title: SafariNativeLanguage.text("safari.setup.open", fallback: "Open Safari Extensions"), target: self, action: #selector(openPreferences))
        button.isEnabled = safariVersionSupported
        button.bezelStyle = .inline
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor(calibratedRed: 0.118, green: 0.227, blue: 0.541, alpha: 1).cgColor
        button.layer?.cornerRadius = 18
        button.font = NSFont(name: "Arial Bold", size: 14)
        button.contentTintColor = .white
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: button.intrinsicContentSize.width + 28).isActive = true
        status = NSTextField(wrappingLabelWithString: "")
        status.font = NSFont(name: "Arial", size: 12) ?? .systemFont(ofSize: 12)
        status.alignment = SafariNativeLanguage.language == "ar" ? .right : .left
        title.textColor = NSColor(calibratedRed: 0.118, green: 0.161, blue: 0.231, alpha: 1)
        body.textColor = title.textColor
        status.textColor = NSColor(calibratedRed: 0.392, green: 0.455, blue: 0.545, alpha: 1)
        let updates = NSStackView()
        updates.orientation = .vertical
        updates.alignment = SafariNativeLanguage.language == "ar" ? .trailing : .leading
        updates.spacing = 10
        let settingsTitle = SafariNativeLanguage.text("safari.updates.settings", fallback: "Settings")
            .replacingOccurrences(of: "…", with: "")
        let updatesTitle = NSTextField(labelWithString: settingsTitle)
        updatesTitle.font = NSFont(name: "Arial Bold", size: 14) ?? .systemFont(ofSize: 14, weight: .semibold)
        updatesTitle.textColor = title.textColor
        let automatic = NSButton(checkboxWithTitle: SafariNativeLanguage.text("safari.updates.auto", fallback: "Auto install updates"),
                                 target: self, action: #selector(toggleAutoUpdates))
        automatic.state = SafariVaultUpdates.shared.autoInstall ? .on : .off
        automatic.isEnabled = SafariVaultUpdates.shared.available
        let manual = NSButton(title: SafariNativeLanguage.text("safari.updates.check", fallback: "Check for updates"),
                              target: self, action: #selector(checkForUpdates))
        manual.bezelStyle = .inline
        manual.isBordered = false
        manual.contentTintColor = NSColor(calibratedRed: 0.118, green: 0.227, blue: 0.541, alpha: 1)
        manual.isEnabled = SafariVaultUpdates.shared.available
        autoUpdateCheckbox = automatic
        updates.addArrangedSubview(updatesTitle)
        updates.addArrangedSubview(automatic)
        updates.addArrangedSubview(manual)
        stack.addArrangedSubview(title); stack.addArrangedSubview(body)
        stack.addArrangedSubview(button); stack.addArrangedSubview(status)
        stack.addArrangedSubview(updates)
        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 28)
        ])
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshState()
    }
    @objc private func openPreferences() {
        guard safariVersionSupported else { status.stringValue = safariRequirementMessage; return }
        SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionID) { [weak self] error in
            DispatchQueue.main.async {
                if error != nil { self?.status.stringValue = SafariNativeLanguage.text("safari.setup.openFailed", fallback: "Safari could not open the extension settings. Open Safari Settings → Extensions.") }
                else { self?.refreshState() }
            }
        }
    }
    @objc func openUpdateSettings() {
        if window == nil { showOnboarding() }
        autoUpdateCheckbox?.state = SafariVaultUpdates.shared.autoInstall ? .on : .off
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func toggleAutoUpdates() {
        SafariVaultUpdates.shared.setAutoInstall(autoUpdateCheckbox?.state == .on)
    }
    @objc private func checkForUpdates() { SafariVaultUpdates.shared.checkManually() }

    private func refreshState() {
        queryState(force: true)
    }
    private func queryState(force: Bool = false) {
        guard safariVersionSupported else { status?.stringValue = ""; return }
        guard let query = heartbeatGate.beginStateQuery(now: ProcessInfo.processInfo.systemUptime, force: force) else { return }
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionID) { [weak self] state, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.heartbeatGate.completeStateQuery(query, enabled: error == nil ? state?.isEnabled : nil)
                self.status?.stringValue = self.heartbeatGate.extensionEnabled == true
                    ? SafariNativeLanguage.text("safari.setup.enabled", fallback: "Safari Vault is enabled. Allow access to all websites in Safari's extension settings.")
                    : SafariNativeLanguage.text("safari.setup.disabled", fallback: "Enable Safari Vault and allow access to all websites in Safari's extension settings.")
                self.pulse()
            }
        }
    }
    private func pulse() {
        let safariRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").isEmpty
        if safariRunning { queryState() }
        // Periodic work may inspect state, but must never dispatch to Safari:
        // dispatchMessage can launch it after an ordinary Quit races this pulse.
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        NSApp.setActivationPolicy(.accessory)
        return false
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        refreshState()
        pulse()
        if !hasVisibleWindows {
            if window == nil { showOnboarding() }
            else { NSApp.setActivationPolicy(.regular); window.makeKeyAndOrderFront(nil) }
        }
        return true
    }
}
@main
struct SafariVaultMain {
    static func main() throws {
        if CommandLine.arguments.contains("--native-connection-state") {
            let environment = Bundle.main.object(forInfoDictionaryKey: "VaultEnvironment") as? String == "development" ? "development" : "production"
            let group = "group.com.adamancia.vault" + (environment == "development" ? ".development" : "")
            let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
            let result: [String: Any] = ["environment": environment, "appGroupAvailable": container != nil,
                                        "proofMaterialAvailable": container.map { FileManager.default.isReadableFile(atPath: $0.appendingPathComponent("safari-local-hub-secret-v4").path) } ?? false]
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            print(String(data: data, encoding: .utf8)!)
            exit(0)
        }
        if CommandLine.arguments.contains("--extension-state") {
            let identifier = Bundle.main.object(forInfoDictionaryKey: "VaultExtensionIdentifier") as? String ?? "com.adamancia.vault.safari.extension"
            SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: identifier) { state, error in
                let result: [String: Any] = ["extension": identifier, "enabled": state?.isEnabled ?? false,
                                            "error": error.map { String(describing: $0) } ?? ""]
                if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
                   let text = String(data: data, encoding: .utf8) { print(text) }
                exit(error == nil ? 0 : 1)
            }
            RunLoop.main.run()
        }
        let application = NSApplication.shared
        // Programmatic AppKit applications need an explicit menu to route ⌘Q.
        // Closing onboarding keeps the independent companion running.
        let delegate = SafariVaultAppDelegate()
        let menu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Safari Vault")
        let quit = NSMenuItem(title: SafariNativeLanguage.text("safari.app.quit", fallback: "Quit Safari Vault"),
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = application
        let settings = NSMenuItem(title: SafariNativeLanguage.text("safari.updates.settings", fallback: "Settings…"),
                                  action: #selector(SafariVaultAppDelegate.openUpdateSettings), keyEquivalent: ",")
        settings.target = delegate
        appMenu.addItem(settings)
        appMenu.addItem(quit)
        appMenuItem.submenu = appMenu
        menu.addItem(appMenuItem)
        application.mainMenu = menu
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
