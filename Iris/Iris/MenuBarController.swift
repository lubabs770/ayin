import Cocoa
import AVFoundation
import ServiceManagement
import Sparkle

class MenuBarController: NSObject {

    // MARK: - Properties
    private var statusItem: NSStatusItem?
    private weak var circularWindow: CircularWindow?
    private var cameraManager: CameraManager
    private var hotkeyRecorderPanel: NSPanel?
    var updaterController: SPUStandardUpdaterController?

    // MARK: - Initialization
    init(cameraManager: CameraManager) {
        self.cameraManager = cameraManager
        super.init()

        // Observe camera device changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(devicesDidChange),
            name: .AVCaptureDeviceWasConnected,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(devicesDidChange),
            name: .AVCaptureDeviceWasDisconnected,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup
    func setupMenuBar() {
        debugLog("setupMenuBar() called")

        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        debugLog("statusItem created: \(statusItem != nil)")

        guard let statusItem = statusItem else {
            debugLog("ERROR - statusItem is nil!")
            return
        }
        guard let button = statusItem.button else {
            debugLog("ERROR - button is nil!")
            return
        }
        debugLog("button obtained")

        updateMenuBarIcon()

        // Set tooltip
        button.toolTip = "Iris - Click to toggle, right-click for menu"

        // Handle clicks manually (not setting menu allows us to differentiate click types)
        button.action = #selector(statusItemClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Don't set menu directly - we'll show it programmatically on right-click
        // statusItem.menu = nil
    }

    func setWindow(_ window: CircularWindow) {
        self.circularWindow = window
    }

    // MARK: - Icon Creation

    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }

        let image = createConcentricRingsIcon()
        image.isTemplate = true
        button.image = image
    }

    private func createConcentricRingsIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let outerRadius: CGFloat = 8.0
            let middleRadius: CGFloat = 5.0
            let innerRadius: CGFloat = 2.0

            NSColor.black.setStroke()
            NSColor.black.setFill()

            // Draw outer circle
            let outerCircle = NSBezierPath(
                ovalIn: NSRect(
                    x: center.x - outerRadius,
                    y: center.y - outerRadius,
                    width: outerRadius * 2,
                    height: outerRadius * 2
                )
            )
            outerCircle.lineWidth = 1.2
            outerCircle.stroke()

            // Draw middle circle (iris)
            let middleCircle = NSBezierPath(
                ovalIn: NSRect(
                    x: center.x - middleRadius,
                    y: center.y - middleRadius,
                    width: middleRadius * 2,
                    height: middleRadius * 2
                )
            )
            middleCircle.lineWidth = 1.0
            middleCircle.stroke()

            // Draw inner circle (pupil) - filled
            let innerCircle = NSBezierPath(
                ovalIn: NSRect(
                    x: center.x - innerRadius,
                    y: center.y - innerRadius,
                    width: innerRadius * 2,
                    height: innerRadius * 2
                )
            )
            innerCircle.fill()

            return true
        }
        return image
    }

    // MARK: - Menu Creation
    func createMenu() -> NSMenu {
        let menu = NSMenu()

        // Toggle window item
        let toggleTitle: String
        if circularWindow == nil {
            toggleTitle = "Show Window (Loading...)"
        } else if circularWindow?.isVisible == true {
            toggleTitle = "Hide Window"
        } else {
            toggleTitle = "Show Window"
        }

        let toggleItem = NSMenuItem(
            title: toggleTitle,
            action: #selector(toggleWindow),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.isEnabled = circularWindow != nil
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        // Camera selection submenu
        let cameraMenuItem = NSMenuItem(title: "Camera", action: nil, keyEquivalent: "")
        let cameraSubmenu = createCameraSubmenu()
        cameraMenuItem.submenu = cameraSubmenu
        menu.addItem(cameraMenuItem)

        // Mirror View toggle
        let mirrorItem = NSMenuItem(
            title: "Mirror View",
            action: #selector(toggleMirrorView),
            keyEquivalent: ""
        )
        mirrorItem.target = self
        mirrorItem.state = PreferencesManager.shared.mirrorView ? .on : .off
        menu.addItem(mirrorItem)

        menu.addItem(NSMenuItem.separator())

        // Launch at login
        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchItem)

        let hotkeyMenuItem = NSMenuItem(title: "Toggle Hotkey", action: nil, keyEquivalent: "")
        let hotkeySubmenu = createHotkeySubmenu()
        hotkeyMenuItem.submenu = hotkeySubmenu
        menu.addItem(hotkeyMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Check for updates (Sparkle)
        if let updaterController {
            let updateItem = NSMenuItem(
                title: "Check for Updates…",
                action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                keyEquivalent: ""
            )
            updateItem.target = updaterController
            menu.addItem(updateItem)
        }

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Iris",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func createCameraSubmenu() -> NSMenu {
        let menu = NSMenu()

        let cameras = CameraManager.availableCameras()

        if cameras.isEmpty {
            let noCamera = NSMenuItem(title: "No Camera Available", action: nil, keyEquivalent: "")
            noCamera.isEnabled = false
            menu.addItem(noCamera)
            return menu
        }

        let currentDevice = cameraManager.currentDevice

        for camera in cameras {
            let item = NSMenuItem(
                title: camera.localizedName,
                action: #selector(selectCamera(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = camera

            // Checkmark for current camera
            if camera.uniqueID == currentDevice?.uniqueID {
                item.state = .on
            }

            menu.addItem(item)
        }

        return menu
    }

    private func createHotkeySubmenu() -> NSMenu {
        let menu = NSMenu()

        let isEnabled = PreferencesManager.shared.toggleHotkeyEnabled
        let currentHotkey = HotkeyManager.shared.currentHotkeyDisplayString()

        let enabledItem = NSMenuItem(
            title: isEnabled ? "Enabled (\(currentHotkey))" : "Disabled",
            action: #selector(toggleHotkeyEnabled),
            keyEquivalent: ""
        )
        enabledItem.target = self
        enabledItem.state = isEnabled ? .on : .off
        menu.addItem(enabledItem)

        menu.addItem(NSMenuItem.separator())

        let recordItem = NSMenuItem(
            title: "Record Hotkey...",
            action: #selector(showHotkeyRecorderPanel),
            keyEquivalent: ""
        )
        recordItem.target = self
        menu.addItem(recordItem)

        return menu
    }

    // MARK: - Actions
    @objc func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            toggleWindow()
            return
        }

        if event.type == .rightMouseUp {
            // Right-click: show menu
            showMenu()
        } else {
            // Left-click: toggle window
            toggleWindow()
        }
    }

    private func showMenu() {
        guard let button = statusItem?.button else { return }
        let menu = createMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    @objc func toggleWindow() {
        guard let window = circularWindow else {
            // Window not ready yet
            return
        }

        if window.isVisible {
            window.hide()
        } else {
            window.show()
        }
    }

    @objc func selectCamera(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? AVCaptureDevice else { return }

        Task {
            do {
                try await cameraManager.switchToCamera(device)
            } catch {
                // Show error alert on main thread
                await MainActor.run {
                    self.showError("Failed to switch camera: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc func toggleMirrorView() {
        let newValue = !PreferencesManager.shared.mirrorView
        PreferencesManager.shared.mirrorView = newValue

        // Update the window
        circularWindow?.setMirrored(newValue)
    }

    @objc func toggleHotkeyEnabled() {
        let newValue = !PreferencesManager.shared.toggleHotkeyEnabled
        PreferencesManager.shared.toggleHotkeyEnabled = newValue
        if newValue {
            HotkeyManager.shared.startMonitoring()
        } else {
            HotkeyManager.shared.stopMonitoring()
        }
    }

    @objc func showHotkeyRecorderPanel() {
        // Close existing panel if any
        hotkeyRecorderPanel?.close()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Record Hotkey"
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.center()

        // Retain the panel
        hotkeyRecorderPanel = panel

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))

        let label = NSTextField(labelWithString: "Press a key combination:")
        label.frame = NSRect(x: 20, y: 80, width: 280, height: 20)
        contentView.addSubview(label)

        let recorderView = HotkeyRecorderView(frame: NSRect(x: 20, y: 35, width: 280, height: 35))
        recorderView.setDisplayString(HotkeyManager.shared.currentHotkeyDisplayString())
        recorderView.onHotkeyRecorded = { [weak self, weak panel] keyCode, modifiers in
            // Temporarily save the new hotkey settings
            let oldKeyCode = PreferencesManager.shared.toggleHotkeyKeyCode
            let oldModifiers = PreferencesManager.shared.toggleHotkeyModifiers
            let wasEnabled = PreferencesManager.shared.toggleHotkeyEnabled

            PreferencesManager.shared.toggleHotkeyKeyCode = keyCode
            PreferencesManager.shared.toggleHotkeyModifiers = modifiers.rawValue
            PreferencesManager.shared.toggleHotkeyEnabled = true

            // Attempt to register the hotkey
            let success = HotkeyManager.shared.restartMonitoring()

            if success {
                // Registration succeeded, close panel after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    panel?.close()
                    self?.hotkeyRecorderPanel = nil
                }
            } else {
                // Registration failed, revert to old settings
                PreferencesManager.shared.toggleHotkeyKeyCode = oldKeyCode
                PreferencesManager.shared.toggleHotkeyModifiers = oldModifiers
                PreferencesManager.shared.toggleHotkeyEnabled = wasEnabled
                if wasEnabled {
                    HotkeyManager.shared.restartMonitoring()
                }

                // Show error to user
                self?.showError("Could not register hotkey. It may be in use by another application.")
                recorderView.setDisplayString(HotkeyManager.shared.currentHotkeyDisplayString())
            }
        }
        recorderView.onRecordingCancelled = { [weak self, weak panel] in
            panel?.close()
            self?.hotkeyRecorderPanel = nil
        }
        contentView.addSubview(recorderView)

        panel.contentView = contentView
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(recorderView)
    }

    @objc func toggleLaunchAtLogin() {
        if isLaunchAtLoginEnabled() {
            disableLaunchAtLogin()
        } else {
            enableLaunchAtLogin()
        }
    }

    @objc func quit() {
        // Clean up camera resources
        cameraManager.stopSession()

        // Quit app
        NSApplication.shared.terminate(nil)
    }

    @objc func devicesDidChange() {
        // Menu will be refreshed on next right-click
    }

    // MARK: - Launch at Login
    private func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return PreferencesManager.shared.launchAtLogin
        }
    }

    private func enableLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
                PreferencesManager.shared.launchAtLogin = true
            } catch {
                showError("Failed to enable launch at login: \(error.localizedDescription)")
            }
        } else {
            // Fallback for older macOS versions
            PreferencesManager.shared.launchAtLogin = true
            showError("Launch at login requires macOS 13 or later.")
        }
    }

    private func disableLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.unregister()
                PreferencesManager.shared.launchAtLogin = false
            } catch {
                showError("Failed to disable launch at login: \(error.localizedDescription)")
            }
        } else {
            PreferencesManager.shared.launchAtLogin = false
        }
    }

    // MARK: - Error Handling
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func debugLog(_ message: String) {
        let logMessage = "[\(Date())] MenuBar: \(message)\n"
        let logPath = "/tmp/iris_debug.log"

        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logPath, contents: data, attributes: nil)
            }
        }
    }
}
