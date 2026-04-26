import SwiftUI

@MainActor
private final class DesktopSurface {
	let display: Display
	let webViewController: WebViewController
	let desktopWindow: DesktopWindow
	var cancellables = Set<AnyCancellable>()

	init(display: Display) {
		self.display = display
		self.webViewController = WebViewController()
		self.desktopWindow = DesktopWindow(display: display)
		self.desktopWindow.contentView = webViewController.webView
		self.desktopWindow.contentView?.isHidden = true
	}

	func recreateWebView() {
		webViewController.recreateWebView()
		desktopWindow.contentView = webViewController.webView
	}
}

@MainActor
final class AppState: ObservableObject {
	static let shared = AppState()

	var cancellables = Set<AnyCancellable>()

	let menu = SSMenu()
	let powerSourceWatcher = PowerSourceWatcher()

	private(set) lazy var statusItem = with(NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)) {
		$0.isVisible = true
		$0.behavior = []
		$0.menu = menu
		let image = NSImage.menuBarIcon.copy() as? NSImage
		image?.isTemplate = true
		image?.size = .init(width: 18, height: 18)
		$0.button!.image = image
		$0.button!.imagePosition = .imageOnly
		$0.button!.setAccessibilityTitle(SSApp.name)
	}

	private(set) lazy var statusItemButton = statusItem.button!

	private var desktopSurfaces = [Display.ID: DesktopSurface]()

	var webViewController: WebViewController {
		primaryDesktopSurface.webViewController
	}

	var desktopWindow: DesktopWindow {
		primaryDesktopSurface.desktopWindow
	}

	var isBrowsingMode = false {
		didSet {
			guard isEnabled else {
				return
			}

			for surface in desktopSurfaces.values {
				surface.desktopWindow.isInteractive = isBrowsingMode
				surface.desktopWindow.alphaValue = isBrowsingMode ? 1 : Defaults[.opacity]
			}

			resetTimer()
		}
	}

	var isEnabled = true {
		didSet {
			resetTimer()
			statusItemButton.appearsDisabled = !isEnabled

			if isEnabled {
				loadUserURL()
				showDesktopWindow()
			} else {
				// TODO: Properly unload the web view instead of just clearing and hiding it.
				for surface in desktopSurfaces.values {
					surface.desktopWindow.orderOut(self)
				}

				loadURL("about:blank")
			}
		}
	}

	var isScreenLocked = false

	var isManuallyDisabled = false {
		didSet {
			setEnabledStatus()
		}
	}

	var reloadTimer: Timer?

	var webViewError: Error? {
		didSet {
			if let webViewError {
				statusItemButton.toolTip = "Error: \(webViewError.localizedDescription)"

				// TODO: There's a macOS bug that makes it black instead of a color.
//				statusItemButton.contentTintColor = .systemRed

				// TODO: Also present the error when the user just added it from the input box as then it's also "interactive".
				if
					isBrowsingMode,
					!webViewError.localizedDescription.contains("No internet connection")
				{
					webViewError.presentAsModal()
				}

				return
			}

			statusItemButton.contentTintColor = nil
		}
	}

	private init() {
		DispatchQueue.main.async { [self] in
			didLaunch()
		}
	}

	private func didLaunch() {
		_ = statusItemButton
		syncDesktopSurfaces()
		setUpEvents()
		handleMenuBarIcon()
		let isFirstLaunch = SSApp.isFirstLaunch
		showWelcomeScreenIfNeeded()
		loadUserURL()
		showDesktopWindow()

		if !isFirstLaunch, Defaults[.websites].isEmpty {
			Constants.openWebsitesWindow()
		}

		#if DEBUG
//		SSApp.showSettingsWindow()
//		Constants.openWebsitesWindow()
		#endif
	}

	private func showDesktopWindow() {
		for surface in desktopSurfaces.values {
			if isBrowsingMode {
				surface.desktopWindow.makeKeyAndOrderFront(self)
			} else {
				surface.desktopWindow.orderBack(self)
			}
		}
	}

	func handleMenuBarIcon() {
		statusItem.isVisible = true

		delay(.seconds(5)) { [self] in
			guard Defaults[.hideMenuBarIcon] else {
				return
			}

			statusItem.isVisible = false
		}
	}

	func handleAppReopen() {
		handleMenuBarIcon()
	}

	func setEnabledStatus() {
		isEnabled = !isManuallyDisabled && !isScreenLocked && !(Defaults[.deactivateOnBattery] && powerSourceWatcher?.powerSource.isUsingBattery == true)
	}

	func resetTimer() {
		reloadTimer?.invalidate()
		reloadTimer = nil

		guard
			isEnabled,
			!isBrowsingMode,
			let reloadInterval = Defaults[.reloadInterval]
		else {
			return
		}

		reloadTimer = Timer.scheduledTimer(withTimeInterval: reloadInterval, repeats: true) { [self] _ in
			Task { @MainActor in
				reloadWebsite()
			}
		}
	}

	private var targetDisplays: [Display] {
		if Defaults[.showOnAllDisplays] {
			return Display.all
		}

		return (Defaults[.display]?.withFallbackToMain ?? .main).map { [$0] } ?? []
	}

	private var primaryDesktopSurface: DesktopSurface {
		syncDesktopSurfaces()

		if
			let firstDisplay = targetDisplays.first,
			let surface = desktopSurfaces[firstDisplay.id]
		{
			return surface
		}

		guard let surface = desktopSurfaces.values.first else {
			fatalError("Plash could not find any connected displays.")
		}

		return surface
	}

	func syncDesktopSurfaces() {
		let displays = targetDisplays
		let displayIDs = Set(displays.map(\.id))

		for (id, surface) in desktopSurfaces where !displayIDs.contains(id) {
			surface.desktopWindow.orderOut(self)
			surface.desktopWindow.contentView = nil
		}

		desktopSurfaces = desktopSurfaces.filter { displayIDs.contains($0.key) }

		for display in displays {
			if let surface = desktopSurfaces[display.id] {
				surface.desktopWindow.targetDisplay = display
				continue
			}

			let surface = makeDesktopSurface(for: display)
			desktopSurfaces[display.id] = surface

			if isEnabled {
				loadUserURL(on: surface)

				if isBrowsingMode {
					surface.desktopWindow.makeKeyAndOrderFront(self)
				} else {
					surface.desktopWindow.orderBack(self)
				}
			} else {
				surface.desktopWindow.orderOut(self)
			}
		}

		for surface in desktopSurfaces.values {
			surface.desktopWindow.alphaValue = isBrowsingMode ? 1 : Defaults[.opacity]
			surface.desktopWindow.collectionBehavior.toggleExistence(.canJoinAllSpaces, shouldExist: Defaults[.showOnAllSpaces])
			surface.desktopWindow.isInteractive = isBrowsingMode
		}
	}

	func setDesktopSurfacesOpacity(_ opacity: Double) {
		for surface in desktopSurfaces.values {
			surface.desktopWindow.alphaValue = isBrowsingMode ? 1 : opacity
		}
	}

	func setDesktopSurfacesShowOnAllSpaces(_ shouldShowOnAllSpaces: Bool) {
		for surface in desktopSurfaces.values {
			surface.desktopWindow.collectionBehavior.toggleExistence(.canJoinAllSpaces, shouldExist: shouldShowOnAllSpaces)
		}
	}

	func refreshDesktopSurfaceWindowLevels() {
		for surface in desktopSurfaces.values {
			surface.desktopWindow.isInteractive = surface.desktopWindow.isInteractive
		}
	}

	private func makeDesktopSurface(for display: Display) -> DesktopSurface {
		let surface = DesktopSurface(display: display)

		surface.webViewController.didLoadPublisher
			.convertToResult()
			.sink { [weak self, weak surface] result in
				guard
					let self,
					let surface
				else {
					return
				}

				switch result {
				case .success:
					// Set the persisted zoom level.
					// This must be here as `webView.url` needs to have been set.
					let zoomLevel = surface.webViewController.webView.zoomLevelWrapper
					if zoomLevel != 1 {
						surface.webViewController.webView.zoomLevelWrapper = zoomLevel
					}

					self.statusItemButton.toolTip = WebsitesController.shared.current?.tooltip
				case .failure(let error):
					self.webViewError = error
				}
			}
			.store(in: &surface.cancellables)

		return surface
	}

	func recreateWebView() {
		for surface in desktopSurfaces.values {
			surface.recreateWebView()
		}
	}

	func recreateWebViewAndReload() {
		recreateWebView()
		loadUserURL()
	}

	func reloadWebsite() {
		// We always load the website the user specified in case it's a redirect that may change on each call.
		loadUserURL()

//		webViewController.reloadCurrentPageFromOrigin()
	}

	func loadUserURL() {
		for surface in desktopSurfaces.values {
			loadUserURL(on: surface)
		}
	}

	func toggleBrowsingMode() {
		Defaults[.isBrowsingMode].toggle()
	}

	private func loadUserURL(on surface: DesktopSurface) {
		loadURL(WebsitesController.shared.current?.url, on: surface)
	}

	func loadURL(_ url: URL?) {
		webViewError = nil

		for surface in desktopSurfaces.values {
			loadURL(url, on: surface)
		}
	}

	private func loadURL(_ url: URL?, on surface: DesktopSurface) {
		webViewError = nil

		guard
			var url,
			url.isValid
		else {
			return
		}

		do {
			url = try replacePlaceholders(of: url, for: surface.display.screen) ?? url
		} catch {
			error.presentAsModal()
			return
		}

		surface.webViewController.loadURL(url)

		// TODO: Add a callback to `loadURL` when it's done loading instead.
		// TODO: Fade in the web view.
		delay(.seconds(1)) {
			surface.desktopWindow.contentView?.isHidden = false
		}
	}

	/**
	Replaces app-specific placeholder strings in the given URL with a corresponding value.
	*/
	func replacePlaceholders(of url: URL) throws -> URL? {
		// Here we swap out `[[screenWidth]]` and `[[screenHeight]]` for their actual values.
		// We proceed only if we have an `NSScreen` to work with.
		guard let screen = desktopWindow.targetDisplay?.screen ?? .primary else {
			return nil
		}

		return try replacePlaceholders(of: url, for: screen)
	}

	private func replacePlaceholders(of url: URL, for screen: NSScreen?) throws -> URL? {
		guard let screen else {
			return nil
		}

		return try url
			.replacingPlaceholder("[[screenWidth]]", with: String(format: "%.0f", screen.frameWithoutStatusBar.width))
			.replacingPlaceholder("[[screenHeight]]", with: String(format: "%.0f", screen.frameWithoutStatusBar.height))
	}

	func clearWebsiteData() async {
		for surface in desktopSurfaces.values {
			await surface.webViewController.webView.clearWebsiteData()
		}
	}
}
