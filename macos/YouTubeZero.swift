import AppKit
import WebKit

let projectRoot = Bundle.main.object(forInfoDictionaryKey: "YouTubeZeroRoot") as! String
let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/YouTube Zero.log")
let mist = NSColor(srgbRed: 0xe6 / 255, green: 0xea / 255, blue: 0xee / 255, alpha: 1)
let pageStyle = """
    <style>
    html { background: #e6eaee; color: #15202a; font: 16px/1.5 -apple-system, sans-serif; }
    body { display: grid; place-items: center; height: 100vh; margin: 0; }
    p { max-width: 32em; padding: 0 24px; }
    </style>
    """

func findUV() -> String? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return ["/opt/homebrew/bin/uv", "/usr/local/bin/uv", "\(home)/.local/bin/uv", "\(home)/.cargo/bin/uv"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
}

func escapeHTML(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var server: Process?
    var serverURL: URL?
    var recentOutput = ""
    var log: FileHandle?
    var quitting = false
    var titleObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMenu()

        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = true
        config.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.underPageBackgroundColor = mist
        webView.loadHTMLString(pageStyle, baseURL: nil)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "YouTube Zero"
        window.backgroundColor = mist
        window.contentMinSize = NSSize(width: 380, height: 420)
        window.contentView = webView
        window.center()
        window.setFrameAutosaveName("Main")
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(webView)
        titleObservation = webView.observe(\.title) { [weak self] view, _ in
            guard let title = view.title, !title.isEmpty else { return }
            self?.window.title = title
        }
        startServer()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        quitting = true
        guard let server, server.isRunning else { return }
        server.terminate()
        // The server cancels downloads and deletes their partial files before exiting.
        let deadline = Date().addingTimeInterval(3)
        while server.isRunning && Date() < deadline { usleep(50_000) }
    }

    func startServer() {
        guard let uv = findUV() else {
            return showMessage("YouTube Zero needs uv. Install it with <code>brew install uv</code>, then open the app again.")
        }
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        log = try? FileHandle(forWritingTo: logURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: uv)
        process.arguments = ["run", "server.py"]
        process.currentDirectoryURL = URL(fileURLWithPath: projectRoot)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        env["YOUTUBE_ZERO_NO_BROWSER"] = "1"
        env["YOUTUBE_ZERO_PARENT_PID"] = String(getpid())
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async { self?.received(data) }
        }
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async { self?.serverStopped(process.terminationStatus) }
        }
        do {
            try process.run()
            server = process
        } catch {
            showMessage("The server could not start. \(escapeHTML(error.localizedDescription))")
        }
    }

    func received(_ data: Data) {
        log?.write(data)
        recentOutput = String((recentOutput + String(decoding: data, as: UTF8.self)).suffix(4000))
        guard serverURL == nil,
              let range = recentOutput.range(of: #"http://127\.0\.0\.1:\d+/"#, options: .regularExpression),
              let url = URL(string: String(recentOutput[range])) else { return }
        serverURL = url
        webView.load(URLRequest(url: url))
    }

    func serverStopped(_ status: Int32) {
        guard !quitting else { return }
        let tail = recentOutput.split(separator: "\n").suffix(6).joined(separator: "\n")
        showMessage("""
            The server stopped with exit status \(status). Quit YouTube Zero and open it again.
            The full log is in ~/Library/Logs/YouTube Zero.log.
            <pre>\(escapeHTML(tail))</pre>
            """)
    }

    func showMessage(_ html: String) {
        webView.loadHTMLString("\(pageStyle)<p>\(html)</p>", baseURL: nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url, let scheme = url.scheme {
            let web = ["http", "https"].contains(scheme)
            if (web && url.host != "127.0.0.1") || (!web && !["about", "data", "blob"].contains(scheme)) {
                NSWorkspace.shared.open(url)
                return decisionHandler(.cancel)
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if serverURL != nil { webView.reload() }
    }

    @objc func reload(_ sender: Any?) {
        if serverURL != nil { webView.reload() }
    }

    func makeMenu() -> NSMenu {
        let bar = NSMenu()
        func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let holder = NSMenuItem()
            holder.submenu = menu
            bar.addItem(holder)
            return menu
        }
        func item(_ title: String, _ action: Selector, _ key: String,
                  _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            return item
        }
        _ = menu("YouTube Zero", [
            item("About YouTube Zero", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
            .separator(),
            item("Hide YouTube Zero", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:)), ""),
            .separator(),
            item("Quit YouTube Zero", #selector(NSApplication.terminate(_:)), "q"),
        ])
        _ = menu("Edit", [
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        _ = menu("View", [
            item("Reload", #selector(reload(_:)), "r"),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ])
        NSApp.windowsMenu = menu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:)), ""),
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ])
        return bar
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
