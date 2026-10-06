import AppKit
import SafariServices

final class SafariVaultAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var status: NSTextField!
    private var heartbeat: Timer?
    private var ruleActivity: NSObjectProtocol?
    private let heartbeatGate = SafariHeartbeatGate()
    private var backgroundLaunch: Bool { CommandLine.arguments.contains("--background") }
    private var extensionID: String {
        Bundle.main.object(forInfoDictionaryKey: "VaultExtensionIdentifier") as? String ?? "com.adamancia.vault.safari.extension"
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.pulse() }
        pulse()
        if backgroundLaunch { NSApp.setActivationPolicy(.accessory); return }
        showOnboarding()
    }
    private func showOnboarding() {
        NSApp.setActivationPolicy(.regular)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 530, height: 380), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
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
        let body = NSTextField(wrappingLabelWithString: SafariNativeLanguage.text("safari.setup.body", fallback: "Enable Safari Vault in Safari Extensions, then allow access to all websites. Browser blocking and custom rules work independently. Connect Mac Vault for tagging, shared groups and Activity."))
        body.font = NSFont(name: "Arial", size: 14) ?? .systemFont(ofSize: 14)
        body.alignment = SafariNativeLanguage.language == "ar" ? .right : .left
        let button = NSButton(title: SafariNativeLanguage.text("safari.setup.open", fallback: "Open Safari Extensions"), target: self, action: #selector(openPreferences))
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
        stack.addArrangedSubview(title); stack.addArrangedSubview(body)
        stack.addArrangedSubview(button); stack.addArrangedSubview(status)
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
        SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionID) { [weak self] error in
            DispatchQueue.main.async {
                if error != nil { self?.status.stringValue = SafariNativeLanguage.text("safari.setup.openFailed", fallback: "Safari could not open the extension settings. Open Safari Settings → Extensions.") }
                else { self?.refreshState() }
            }
        }
    }
    private func refreshState() {
        queryState(force: true)
    }
    private func queryState(force: Bool = false) {
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
        let active = heartbeatGate.isActive(safariRunning: safariRunning)
        if active, ruleActivity == nil {
            // User-enabled custom timers must continue with every browser
            // window hidden. Allow ordinary system sleep while avoiding App
            // Nap's deferred timers during the user's active browser session.
            ruleActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                                reason: "Safari Vault custom rule timers")
        } else if !active, let activity = ruleActivity {
            ProcessInfo.processInfo.endActivity(activity)
            ruleActivity = nil
        }
        guard let dispatch = heartbeatGate.beginDispatch(safariRunning: safariRunning) else { return }
        // Apple's dispatch API can launch Safari. Checking its process first
        // ensures quitting the browser does not cause it to be reopened.
        SFSafariApplication.dispatchMessage(withName: "safari-lifecycle-tick", toExtensionWithIdentifier: extensionID,
                                           userInfo: ["type": "safari-lifecycle-tick"]) { [weak self] _ in
            DispatchQueue.main.async { self?.heartbeatGate.completeDispatch(dispatch) }
        }
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
    func applicationWillTerminate(_ notification: Notification) {
        if let activity = ruleActivity { ProcessInfo.processInfo.endActivity(activity) }
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
        // Closing onboarding still keeps the existing background heartbeat.
        let menu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Safari Vault")
        let quit = NSMenuItem(title: SafariNativeLanguage.text("safari.app.quit", fallback: "Quit Safari Vault"),
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = application
        appMenu.addItem(quit)
        appMenuItem.submenu = appMenu
        menu.addItem(appMenuItem)
        application.mainMenu = menu
        let delegate = SafariVaultAppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
