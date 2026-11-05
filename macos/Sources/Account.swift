import SwiftUI
import WebKit

/// The YouTube session kept in the app's own WebKit storage.
enum Session {
    static let signInURL = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&uilel=3&passive=true"
        + "&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26app%3Ddesktop"
        + "%26next%3Dhttps%253A%252F%252Fwww.youtube.com%252F")!
    /// Google refuses sign-in from browsers it does not recognize, so the web
    /// views present themselves as Safari, which runs the same engine.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    @MainActor static func cookies() async -> [HTTPCookie] {
        await WKWebsiteDataStore.default().httpCookieStore.allCookies()
    }

    static func isSignedIn(_ cookies: [HTTPCookie]) -> Bool {
        cookies.contains { $0.domain.hasSuffix("youtube.com") && ($0.name == "SAPISID" || $0.name == "__Secure-3PAPISID") }
    }

    @MainActor static func signOut() async {
        await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                      modifiedSince: .distantPast)
    }
}

/// Loads YouTube in a hidden web view so Google can rotate the session cookies.
@MainActor
final class SessionKeeper: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, Never>?

    func refresh() async {
        guard webView == nil else { return }
        let view = WKWebView(frame: .zero)
        view.customUserAgent = Session.userAgent
        view.navigationDelegate = self
        webView = view
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            view.load(URLRequest(url: URL(string: "https://www.youtube.com/")!, timeoutInterval: 20))
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in self?.finish() }
        }
    }

    private func finish() {
        continuation?.resume()
        continuation = nil
        webView?.stopLoading()
        webView = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish() }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish() }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish()
    }
}

struct SignInSheet: View {
    @EnvironmentObject var library: Library

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to YouTube").font(rubik(17, 600))
                Spacer()
                PillButton(title: "Cancel", background: Palette.mist, foreground: Palette.ink,
                           hoverBackground: Palette.hover, hoverForeground: Palette.ink, height: 30) {
                    library.showSignIn = false
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(Palette.paper)
            SignInWebView { library.finishSignIn() }
        }
        .frame(width: 520, height: 680)
    }
}

struct SignInWebView: NSViewRepresentable {
    let onSignedIn: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSignedIn: onSignedIn) }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.customUserAgent = Session.userAgent
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: Session.signInURL))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let onSignedIn: () -> Void
        private var done = false

        init(onSignedIn: @escaping () -> Void) { self.onSignedIn = onSignedIn }

        /// Sign-in ends on youtube.com once YouTube has set its session cookies.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !done, webView.url?.host?.hasSuffix("youtube.com") == true else { return }
            Task {
                guard !done, Session.isSignedIn(await Session.cookies()) else { return }
                done = true
                onSignedIn()
            }
        }
    }
}
