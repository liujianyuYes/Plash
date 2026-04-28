import Cocoa
@preconcurrency import Combine
import WebKit

/// 负责创建和管理网页视图，处理加载、导航、弹窗、下载和用户脚本注入。
final class WebViewController: NSViewController {
	private var popupWindow: NSWindow?
	private let didLoadSubject = PassthroughSubject<Void, Error>()
	private var currentDownloadFile: URL?

	/**
	Publishes when the web view finishes loading a page.
	*/
	lazy var didLoadPublisher = didLoadSubject.eraseToAnyPublisher()

	var response: HTTPURLResponse?

	/// 根据当前网站和全局设置创建一套新的 WKWebView 配置。
	private func createWebView() -> SSWebView {
		let configuration = WKWebViewConfiguration()
		configuration.allowsAirPlayForMediaPlayback = false
		configuration.applicationNameForUserAgent = "\(SSApp.name)/\(SSApp.version)"

		// TODO: Enable this again when https://github.com/sindresorhus/Plash/issues/9 is fixed.
//		configuration.suppressesIncrementalRendering = true

		let userContentController = WKUserContentController()
		configuration.userContentController = userContentController

		if Defaults[.muteAudio] {
			userContentController.muteAudio()
		}

		let preferences = WKPreferences()
		preferences.javaScriptCanOpenWindowsAutomatically = false
		preferences.isDeveloperExtrasEnabled = true
		preferences.isElementFullscreenEnabled = true
		configuration.preferences = preferences

		let webView = SSWebView(frame: .zero, configuration: configuration)
		webView.navigationDelegate = self
		webView.uiDelegate = self
		webView.allowsBackForwardNavigationGestures = true
		webView.allowsMagnification = true
		webView.customUserAgent = SSWebView.safariUserAgent
		webView.drawsBackground = false

		userContentController.addJavaScript("document.documentElement.classList.add('is-plash-app')")

		if let website = WebsitesController.shared.current {
			if website.invertColors2 != .never {
				userContentController.invertColors(
					onlyWhenInDarkMode: website.invertColors2 == .darkMode
				)
			}

			if website.usePrintStyles {
				webView.mediaType = "print"
			}

			if !website.css.trimmed.isEmpty {
				userContentController.addCSS(website.css)
			}

			if !website.javaScript.trimmed.isEmpty {
				userContentController.addJavaScript(
					"""
					try {
						\(website.javaScript)
					} catch (error) {
						alert(`Custom JavaScript threw an error:\n\n${error}`);
						throw error;
					}
					"""
				)
			}

			// Google Sheets shows an error message when we use the Safari or Chrome user agent.
			if website.url.hasDomain("google.com") {
				webView.customUserAgent = ""
			}
		}

		return webView
	}

	/// 丢弃旧 WebView 并使用当前设置创建新实例。
	func recreateWebView() {
		webView = createWebView()
		view = webView
	}

	/// 重新加载当前页面，保留 WebView 当前 URL。
	func reloadCurrentPage() {
		webView.reload()
	}

	/// 从源站重新加载当前页面，绕过可能的缓存副本。
	func reloadCurrentPageFromOrigin() {
		webView.reloadFromOrigin()
	}

	private(set) lazy var webView = createWebView()

	override func loadView() {
		view = webView
	}

	// TODO: When Swift 6 is out, make this async and throw instead of using `onLoaded` handler.
	/// 加载远程 URL 或本地网站目录。
	func loadURL(_ url: URL) {
		guard !url.isFileURL else {
			_ = url.accessSandboxedURLByPromptingIfNeeded()
			webView.loadFileURL(url.appendingPathComponent("index.html", isDirectory: false), allowingReadAccessTo: url)

			return
		}

		var request = URLRequest(url: url)
		request.cachePolicy = .reloadIgnoringLocalCacheData
		webView.load(request)
	}

	/// 统一处理页面加载完成或失败后的浏览模式标记和错误发布。
	private func internalOnLoaded(_ error: Error?) {
		// TODO: A minor improvement would be to inject this on `DOMContentLoaded` using `WKScriptMessageHandler`.
		webView.toggleBrowsingModeClass()

		if let error {
			guard !WKWebView.canIgnoreError(error) else {
				didLoadSubject.send()
				return
			}

			didLoadSubject.send(completion: .failure(error))
			return
		}

		didLoadSubject.send()
	}
}

extension WebViewController: WKNavigationDelegate {
	/// 决定链接点击、下载和外部浏览器打开策略。
	func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
		if
			Defaults[.openExternalLinksInBrowser],
			navigationAction.navigationType == .linkActivated,
			let originalURL = webView.url,
			let newURL = navigationAction.request.url,
			originalURL.host != newURL.host
		{
			// Hide Plash if it's in front of everything.
			if Defaults[.isBrowsingMode], Defaults[.bringBrowsingModeToFront] {
				Defaults[.isBrowsingMode] = false
			}

			newURL.open()

			return .cancel
		}

		if navigationAction.shouldPerformDownload {
			return .download
		}

		// Fix signing into Google Account. Google has some stupid protection against fake user agents for "accounts.google.com" and "docs.google.com".
		if let host = navigationAction.request.url?.host {
			let useBlankUserAgent = host == "google.com" || host.hasSuffix(".google.com")
			webView.customUserAgent = useBlankUserAgent ? "" : SSWebView.safariUserAgent
		}

		return .allow
	}

	/// 记录主文档响应，并把不可展示内容转为下载。
	func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
		if
			navigationResponse.isForMainFrame,
			let response = navigationResponse.response as? HTTPURLResponse
		{
			self.response = response
		}

		return navigationResponse.canShowMIMEType ? .allow : .download
	}

	/// 页面加载完成后对单图页面做适配，并发布加载成功事件。
	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		webView.centerAndAspectFillImage(mimeType: response?.mimeType)

		internalOnLoaded(nil)
	}

	/// 处理已开始导航后的加载失败。
	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		internalOnLoaded(error)
	}

	/// 处理主文档提交前的加载失败。
	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		internalOnLoaded(error)
	}

	/// 处理认证挑战，按网站设置决定是否允许自签名证书。
	func webView(_ webView: WKWebView, respondTo challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
		// We're intentionally allowing this in non-browsing mode as loading the URL would fail otherwise.
		await webView.defaultAuthChallengeHandler(
			challenge: challenge,
			allowSelfSignedCertificate: WebsitesController.shared.current?.allowSelfSignedCertificate ?? false
		)
	}

	/// 导航请求转为下载时绑定下载代理。
	func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
		download.delegate = self
	}

	/// 响应内容转为下载时绑定下载代理。
	func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
		download.delegate = self
	}
}

extension WebViewController: WKUIDelegate {
	/// 处理网页请求打开新窗口的场景，非浏览模式下回落到当前 WebView。
	func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
		guard
			AppState.shared.isBrowsingMode,
			NSEvent.modifiers != .option
		else {
			// This makes it so that requests to open something in a new window just opens in the existing web view.
			if navigationAction.targetFrame == nil {
				webView.load(navigationAction.request)
			}

			return nil
		}

		let webView = WKWebView(frame: .zero, configuration: configuration)
		webView.navigationDelegate = self
		webView.uiDelegate = self
		webView.customUserAgent = WKWebView.safariUserAgent

		var styleMask: NSWindow.StyleMask = [
			.titled,
			.closable,
			.resizable
		]

		// We default the window to be resizable to make it user-friendly.
		if windowFeatures.allowsResizing?.boolValue == false {
			styleMask.remove(.resizable)
		}

		let window = NSWindow(
			contentRect: CGRect(origin: .zero, size: windowFeatures.size),
			styleMask: styleMask,
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false // Since we manually release it.
		window.contentView = webView
		view.window?.addChildWindow(window, ordered: .above)
		window.center()
		window.makeKeyAndOrderFront(self)
		popupWindow = window

		webView.bind(\.title, to: window, at: \.title, default: "")
			.store(forTheLifetimeOf: webView)

		return webView
	}


	/// 只在浏览模式下允许 JavaScript confirm 对话框。
	func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
		guard AppState.shared.isBrowsingMode else {
			return false
		}

		return await webView.defaultConfirmHandler(message: message)
	}

	/// 只在浏览模式下允许 JavaScript prompt 对话框。
	func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
		guard AppState.shared.isBrowsingMode else {
			return nil
		}

		return await webView.defaultPromptHandler(prompt: prompt, defaultText: defaultText)
	}

	// swiftlint:disable:next discouraged_optional_collection
	/// 只在浏览模式下允许网页打开文件选择面板。
	func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
		guard AppState.shared.isBrowsingMode else {
			return nil
		}

		return await webView.defaultUploadPanelHandler(parameters: parameters)
	}

	/// 关闭由网页创建的子窗口。
	func webViewDidClose(_ webView: WKWebView) {
		if webView.window == popupWindow {
			popupWindow?.close()
			popupWindow = nil
		}
	}
}

extension WebViewController: WKDownloadDelegate {
	/// 决定下载目标路径，并避免覆盖已有文件。
	func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
		let url = URL.downloadsDirectory.appendingPathComponent(suggestedFilename).incrementalFilename()
		currentDownloadFile = url
		return url
	}

	/// 下载完成后在 Dock 中提示下载目录。
	func downloadDidFinish(_ download: WKDownload) {
		guard let currentDownloadFile else {
			return
		}

		NSWorkspace.shared.bounceDownloadsFolderInDock(for: currentDownloadFile)
	}

	/// 下载失败时向用户展示错误。
	func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
		error.presentAsModal()
	}
}
