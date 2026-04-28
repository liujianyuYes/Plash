import AVKit
import CoreImage
import SwiftUI

/// 某个显示器上的桌面承载面，由窗口和 WebView 控制器组成。
@MainActor
private final class DesktopSurface {
	let display: Display
	let webViewController: WebViewController
	let desktopWindow: DesktopWindow
	let settingsButtonWindow: DesktopSettingsButtonWindow
	let componentDropWindow: DesktopComponentDropWindow
	var componentWindows = [DesktopComponent.ID: DesktopComponentWindow]()
	var cancellables = Set<AnyCancellable>()
	private let wallpaperContainer = NSView()
	private let emptyWallpaperView = NSView()
	private let imageContainer = NSView()
	private let imageBackgroundView = NSImageView()
	private let imageForegroundView = NSImageView()
	private let videoPlayerView = AVPlayerView()
	private var videoPlayer: AVPlayer?
	private var videoEndObserver: NSObjectProtocol?
	private var imageSlideshowTimer: Timer?
	private var imageSlideshowIndex = 0

	/// 为指定显示器创建隐藏的桌面窗口和对应 WebView。
	init(display: Display) {
		self.display = display
		self.webViewController = WebViewController()
		self.desktopWindow = DesktopWindow(display: display)
		self.settingsButtonWindow = DesktopSettingsButtonWindow(display: display)
		self.componentDropWindow = DesktopComponentDropWindow(display: display)
		self.wallpaperContainer.wantsLayer = true
		self.wallpaperContainer.layer?.backgroundColor = NSColor.black.cgColor
		self.emptyWallpaperView.wantsLayer = true
		self.emptyWallpaperView.layer?.backgroundColor = NSColor.black.cgColor
		self.desktopWindow.contentView = wallpaperContainer
		self.desktopWindow.contentView?.isHidden = true
	}

	/// 重新创建 WebView，并把新的视图挂回桌面窗口。
	func recreateWebView() {
		webViewController.recreateWebView()
	}

	/// 清理媒体播放和轮播资源。
	func tearDown() {
		stopMediaPlayback()
	}

	/// 显示网站壁纸承载视图。
	func showWebsiteWallpaper() {
		stopMediaPlayback()
		setWallpaperContentView(webViewController.webView)
	}

	/// 显示视频壁纸。
	func showVideoWallpaper(_ settings: WallpaperVideoSettings) {
		stopMediaPlayback()

		guard let url = settings.selectedURL else {
			showEmptyWallpaper()
			return
		}

		let player = AVPlayer(url: url)
		player.isMuted = settings.isMuted
		player.actionAtItemEnd = settings.shouldLoop ? .none : .pause
		videoPlayer = player
		videoPlayerView.player = player
		videoPlayerView.controlsStyle = settings.showsControls ? .floating : .none
		videoPlayerView.videoGravity = videoGravity(for: settings.fillMode)
		setWallpaperContentView(videoPlayerView)

		if settings.shouldLoop {
			videoEndObserver = NotificationCenter.default.addObserver(
				forName: .AVPlayerItemDidPlayToEndTime,
				object: player.currentItem,
				queue: .main
			) { [weak player] _ in
				player?.seek(to: .zero)
				if settings.startsAutomatically {
					player?.playImmediately(atRate: Float(settings.playbackRate))
				}
			}
		}

		if settings.startsAutomatically {
			player.playImmediately(atRate: Float(settings.playbackRate))
		}
	}

	/// 显示图片壁纸，并在需要时启动轮播。
	func showImageWallpaper(_ settings: WallpaperImageSettings) {
		stopMediaPlayback()
		imageSlideshowIndex = settings.selectedIndex
		setWallpaperContentView(imageContainer)
		configureImageViews(settings: settings)
		showImage(at: imageSlideshowIndex, settings: settings)

		guard
			settings.isSlideshowEnabled,
			settings.urls.count > 1
		else {
			return
		}

		imageSlideshowTimer = Timer.scheduledTimer(
			withTimeInterval: max(5, settings.slideshowInterval),
			repeats: true
		) { [weak self] _ in
			Task { @MainActor in
				self?.advanceImageSlideshow(settings: settings)
			}
		}
	}

	/// 显示空壁纸，通常用于尚未选择本地媒体的情况。
	func showEmptyWallpaper() {
		stopMediaPlayback()
		setWallpaperContentView(emptyWallpaperView)
	}

	private func stopMediaPlayback() {
		imageSlideshowTimer?.invalidate()
		imageSlideshowTimer = nil

		videoPlayer?.pause()
		videoPlayer = nil
		videoPlayerView.player = nil

		if let videoEndObserver {
			NotificationCenter.default.removeObserver(videoEndObserver)
			self.videoEndObserver = nil
		}
	}

	private func setWallpaperContentView(_ view: NSView) {
		wallpaperContainer.subviews.forEach { $0.removeFromSuperview() }
		view.frame = wallpaperContainer.bounds
		view.autoresizingMask = [
			.width,
			.height
		]
		wallpaperContainer.addSubview(view)
		desktopWindow.contentView?.isHidden = false
	}

	private func configureImageViews(settings: WallpaperImageSettings) {
		imageContainer.subviews.forEach { $0.removeFromSuperview() }
		imageContainer.wantsLayer = true
		imageContainer.layer?.backgroundColor = NSColor.black.cgColor

		imageBackgroundView.frame = imageContainer.bounds
		imageBackgroundView.autoresizingMask = [
			.width,
			.height
		]
		imageBackgroundView.imageScaling = .scaleAxesIndependently
		imageBackgroundView.alphaValue = settings.usesBlurredBackground ? 0.55 : 0
		if settings.usesBlurredBackground, let filter = CIFilter(name: "CIGaussianBlur") {
			filter.setValue(24, forKey: kCIInputRadiusKey)
			imageBackgroundView.contentFilters = [
				filter
			]
		} else {
			imageBackgroundView.contentFilters = []
		}

		imageForegroundView.frame = imageContainer.bounds
		imageForegroundView.autoresizingMask = [
			.width,
			.height
		]
		applyImageFillMode(settings.fillMode)

		imageContainer.addSubview(imageBackgroundView)
		imageContainer.addSubview(imageForegroundView)
	}

	private func showImage(at index: Int, settings: WallpaperImageSettings) {
		guard !settings.urls.isEmpty else {
			imageBackgroundView.image = nil
			imageForegroundView.image = nil
			return
		}

		let clampedIndex = min(max(index, 0), settings.urls.count - 1)
		let image = NSImage(contentsOf: settings.urls[clampedIndex])
		imageBackgroundView.image = image
		imageForegroundView.image = image
	}

	private func advanceImageSlideshow(settings: WallpaperImageSettings) {
		guard !settings.urls.isEmpty else {
			return
		}

		if settings.isRandomOrder {
			imageSlideshowIndex = Int.random(in: settings.urls.indices)
		} else {
			imageSlideshowIndex = (imageSlideshowIndex + 1) % settings.urls.count
		}

		showImage(at: imageSlideshowIndex, settings: settings)
	}

	private func applyImageFillMode(_ fillMode: WallpaperFillMode) {
		imageForegroundView.wantsLayer = true

		switch fillMode {
		case .fill:
			imageForegroundView.imageScaling = .scaleProportionallyUpOrDown
			imageForegroundView.layer?.contentsGravity = .resizeAspectFill
		case .fit:
			imageForegroundView.imageScaling = .scaleProportionallyUpOrDown
			imageForegroundView.layer?.contentsGravity = .resizeAspect
		case .stretch:
			imageForegroundView.imageScaling = .scaleAxesIndependently
			imageForegroundView.layer?.contentsGravity = .resize
		case .center:
			imageForegroundView.imageScaling = .scaleNone
			imageForegroundView.layer?.contentsGravity = .center
		}
	}

	private func videoGravity(for fillMode: WallpaperFillMode) -> AVLayerVideoGravity {
		switch fillMode {
		case .fill:
			.resizeAspectFill
		case .fit, .center:
			.resizeAspect
		case .stretch:
			.resize
		}
	}

	/// 按当前组件列表创建、更新或移除组件窗口。
	func syncComponentWindows(
		display: Display,
		isVisible: Bool,
		isBrowsingMode: Bool
	) {
		let components = Defaults[.desktopComponents]
			.filter {
				DesktopComponentsController.shared.isComponentAvailable($0)
			}
		let componentIDs = Set(components.map(\.id))

		for (id, window) in componentWindows where !componentIDs.contains(id) {
			window.orderOut(nil)
		}

		componentWindows = componentWindows.filter { componentIDs.contains($0.key) }

		for component in components {
			if let window = componentWindows[component.id] {
				window.update(component: component, display: display)
				window.refreshLevel(isBrowsingMode: isBrowsingMode)
				window.setComponentVisible(isVisible)
				continue
			}

			let window = DesktopComponentWindow(component: component, display: display)
			window.collectionBehavior.toggleExistence(.canJoinAllSpaces, shouldExist: Defaults[.showOnAllSpaces])
			window.refreshLevel(isBrowsingMode: isBrowsingMode)
			window.setComponentVisible(isVisible)
			componentWindows[component.id] = window
		}
	}

	/// 隐藏所有组件窗口。
	func hideComponentWindows() {
		setComponentWindowsVisible(false)
	}

	/// 批量设置组件窗口显示状态。
	func setComponentWindowsVisible(_ isVisible: Bool) {
		for window in componentWindows.values {
			window.setComponentVisible(isVisible)
		}
	}

	/// 显示或隐藏组件拖到桌面时的透明投放目标。
	func setComponentDropTargetVisible(_ isVisible: Bool) {
		componentDropWindow.collectionBehavior.toggleExistence(.canJoinAllSpaces, shouldExist: Defaults[.showOnAllSpaces])
		componentDropWindow.setDropTargetVisible(isVisible)
	}
}

/// 应用级状态中心，协调菜单栏、桌面窗口、网站加载、设置监听和系统事件。
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
	private var isDesktopComponentDropModeEnabled = false

	/// 当前主显示器对应的 WebView 控制器。
	var webViewController: WebViewController {
		primaryDesktopSurface.webViewController
	}

	/// 当前主显示器对应的桌面窗口。
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
				surface.settingsButtonWindow.refreshLevel(isBrowsingMode: isBrowsingMode)

				for window in surface.componentWindows.values {
					window.refreshLevel(isBrowsingMode: isBrowsingMode)
				}
			}

			resetTimer()
		}
	}

	var isEnabled = true {
		didSet {
			resetTimer()
			statusItemButton.appearsDisabled = !isEnabled

			if isEnabled {
				reloadWallpaper()
				showDesktopWindow()
			} else {
				// TODO: Properly unload the web view instead of just clearing and hiding it.
				for surface in desktopSurfaces.values {
					surface.desktopWindow.orderOut(self)
					surface.settingsButtonWindow.orderOut(self)
					surface.componentDropWindow.orderOut(self)
					surface.hideComponentWindows()
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
				statusItemButton.toolTip = "错误：\(webViewError.localizedDescription)"

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

	/// 延迟到主线程执行启动流程，避免初始化单例时触发过早的 AppKit 操作。
	private init() {
		DispatchQueue.main.async { [self] in
			didLaunch()
		}
	}

	/// 完成启动后的状态绑定、菜单栏准备、欢迎页展示和首次网站加载。
	private func didLaunch() {
		_ = statusItemButton
		syncDesktopSurfaces()
		setUpEvents()
		handleMenuBarIcon()
		let isFirstLaunch = SSApp.isFirstLaunch
		showWelcomeScreenIfNeeded()
		reloadWallpaper()
		showDesktopWindow()

		if !isFirstLaunch, Defaults[.websites].isEmpty {
			Constants.openWebsitesWindow()
		}

		#if DEBUG
//		SSApp.showSettingsWindow()
//		Constants.openWebsitesWindow()
		#endif
	}

	/// 根据浏览模式把桌面窗口放到桌面后方或前台可交互层级。
	private func showDesktopWindow() {
		for surface in desktopSurfaces.values {
			if isBrowsingMode {
				surface.desktopWindow.makeKeyAndOrderFront(self)
			} else {
				surface.desktopWindow.orderBack(self)
			}

			surface.settingsButtonWindow.setSettingsButtonVisible(shouldShowDesktopSettingsButton)
			surface.setComponentWindowsVisible(shouldShowDesktopComponents)
		}
	}

	/// 根据设置显示菜单栏图标；隐藏时仍会短暂显示，方便用户重新打开菜单。
	func handleMenuBarIcon() {
		statusItem.isVisible = true

		delay(.seconds(5)) { [self] in
			guard Defaults[.hideMenuBarIcon] else {
				return
			}

			statusItem.isVisible = false
		}
	}

	/// 处理用户再次启动 App 的行为。
	func handleAppReopen() {
		handleMenuBarIcon()
	}

	/// 综合手动停用、锁屏和电池策略，计算 App 当前是否应该启用。
	func setEnabledStatus() {
		isEnabled = !isManuallyDisabled && !isScreenLocked && !(Defaults[.deactivateOnBattery] && powerSourceWatcher?.powerSource.isUsingBattery == true)
	}

	/// 根据当前设置重建自动刷新计时器。
	func resetTimer() {
		reloadTimer?.invalidate()
		reloadTimer = nil

		guard
			isEnabled,
			!isBrowsingMode,
			Defaults[.wallpaperSettings].usesWebsiteSource(for: targetDisplays),
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

	/// 返回当前设置要求覆盖的显示器集合。
	private var targetDisplays: [Display] {
		if Defaults[.showOnAllDisplays] {
			return Display.all
		}

		return (Defaults[.display]?.withFallbackToMain ?? .main).map { [$0] } ?? []
	}

	/// 获取主桌面承载面，并在需要时先同步显示器状态。
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

	/// 根据当前显示器和设置创建、移除或更新桌面承载面。
	func syncDesktopSurfaces() {
		let displays = targetDisplays
		let displayIDs = Set(displays.map(\.id))

		for (id, surface) in desktopSurfaces where !displayIDs.contains(id) {
			surface.tearDown()
			surface.desktopWindow.orderOut(self)
			surface.settingsButtonWindow.orderOut(self)
			surface.componentDropWindow.orderOut(self)
			surface.hideComponentWindows()
			surface.desktopWindow.contentView = nil
		}

		desktopSurfaces = desktopSurfaces.filter { displayIDs.contains($0.key) }

		for display in displays {
			if let surface = desktopSurfaces[display.id] {
				surface.desktopWindow.targetDisplay = display
				surface.settingsButtonWindow.targetDisplay = display
				surface.componentDropWindow.targetDisplay = display
				surface.syncComponentWindows(
					display: display,
					isVisible: shouldShowDesktopComponents,
					isBrowsingMode: isBrowsingMode
				)
				continue
			}

			let surface = makeDesktopSurface(for: display)
			desktopSurfaces[display.id] = surface

			if isEnabled {
				reloadWallpaper(on: surface)

				if isBrowsingMode {
					surface.desktopWindow.makeKeyAndOrderFront(self)
				} else {
					surface.desktopWindow.orderBack(self)
				}

				surface.settingsButtonWindow.setSettingsButtonVisible(shouldShowDesktopSettingsButton)
				surface.setComponentDropTargetVisible(isDesktopComponentDropModeEnabled)
				surface.syncComponentWindows(
					display: display,
					isVisible: shouldShowDesktopComponents,
					isBrowsingMode: isBrowsingMode
				)
			} else {
				surface.desktopWindow.orderOut(self)
				surface.settingsButtonWindow.orderOut(self)
				surface.componentDropWindow.orderOut(self)
				surface.hideComponentWindows()
			}
		}

		for surface in desktopSurfaces.values {
			surface.desktopWindow.alphaValue = isBrowsingMode ? 1 : Defaults[.opacity]
			surface.desktopWindow.collectionBehavior.toggleExistence(.canJoinAllSpaces, shouldExist: Defaults[.showOnAllSpaces])
			surface.desktopWindow.isInteractive = isBrowsingMode
			surface.settingsButtonWindow.collectionBehavior.toggleExistence(.canJoinAllSpaces, shouldExist: Defaults[.showOnAllSpaces])
			surface.settingsButtonWindow.refreshLevel(isBrowsingMode: isBrowsingMode)
			surface.settingsButtonWindow.setSettingsButtonVisible(shouldShowDesktopSettingsButton)
			surface.setComponentDropTargetVisible(isDesktopComponentDropModeEnabled)
			surface.syncComponentWindows(
				display: surface.display,
				isVisible: shouldShowDesktopComponents,
				isBrowsingMode: isBrowsingMode
			)
		}
	}

	/// 是否应该在桌面壁纸窗口右下角显示设置入口。
	private var shouldShowDesktopSettingsButton: Bool {
		isEnabled && Defaults[.showFloatingSettingsButton]
	}

	/// 是否应该显示桌面组件。
	private var shouldShowDesktopComponents: Bool {
		isEnabled
	}

	/// 更新所有桌面设置入口的显示状态。
	func updateDesktopSettingsButtons() {
		for surface in desktopSurfaces.values {
			surface.settingsButtonWindow.setSettingsButtonVisible(shouldShowDesktopSettingsButton)
		}
	}

	/// 根据 Defaults 中的组件列表同步所有桌面组件窗口。
	func syncDesktopComponentWindows() {
		for surface in desktopSurfaces.values {
			surface.syncComponentWindows(
				display: surface.display,
				isVisible: shouldShowDesktopComponents,
				isBrowsingMode: isBrowsingMode
			)
		}
	}

	/// 设置从组件页拖到桌面时的接收模式。
	func setDesktopComponentDropMode(_ isEnabled: Bool) {
		isDesktopComponentDropModeEnabled = isEnabled && self.isEnabled

		for surface in desktopSurfaces.values {
			surface.setComponentDropTargetVisible(isDesktopComponentDropModeEnabled)
		}
	}

	/// 更新所有桌面窗口的不透明度，浏览模式始终保持完全不透明。
	func setDesktopSurfacesOpacity(_ opacity: Double) {
		for surface in desktopSurfaces.values {
			surface.desktopWindow.alphaValue = isBrowsingMode ? 1 : opacity
		}
	}

	/// 更新所有桌面窗口是否跨 Space 显示。
	func setDesktopSurfacesShowOnAllSpaces(_ shouldShowOnAllSpaces: Bool) {
		for surface in desktopSurfaces.values {
			surface.desktopWindow.collectionBehavior.toggleExistence(.canJoinAllSpaces, shouldExist: shouldShowOnAllSpaces)
			surface.settingsButtonWindow.collectionBehavior.toggleExistence(.canJoinAllSpaces, shouldExist: shouldShowOnAllSpaces)
			surface.componentDropWindow.collectionBehavior.toggleExistence(.canJoinAllSpaces, shouldExist: shouldShowOnAllSpaces)

			for window in surface.componentWindows.values {
				window.collectionBehavior.toggleExistence(.canJoinAllSpaces, shouldExist: shouldShowOnAllSpaces)
			}
		}
	}

	/// 在“浏览模式置于最前”变更后刷新窗口层级。
	func refreshDesktopSurfaceWindowLevels() {
		for surface in desktopSurfaces.values {
			surface.desktopWindow.isInteractive = surface.desktopWindow.isInteractive
			surface.settingsButtonWindow.refreshLevel(isBrowsingMode: isBrowsingMode)

			for window in surface.componentWindows.values {
				window.refreshLevel(isBrowsingMode: isBrowsingMode)
			}
		}
	}

	/// 创建显示器承载面，并把 WebView 加载结果同步到菜单状态。
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

	/// 重新创建所有 WebView，用于需要重建配置的设置变更。
	func recreateWebView() {
		for surface in desktopSurfaces.values {
			surface.recreateWebView()
		}
	}

	/// 重新创建所有 WebView 后加载当前网站。
	func recreateWebViewAndReload() {
		recreateWebView()
		reloadWallpaper()
	}

	/// 重新加载用户保存的当前网站 URL。
	func reloadWebsite() {
		reloadWallpaper()

//		webViewController.reloadCurrentPageFromOrigin()
	}

	/// 在所有目标显示器上加载当前网站。
	func loadUserURL() {
		reloadWallpaper()
	}

	/// 按当前壁纸配置重新加载所有目标显示器。
	func reloadWallpaper() {
		for surface in desktopSurfaces.values {
			reloadWallpaper(on: surface)
		}
	}

	/// 切换浏览模式设置，实际窗口状态由 Defaults 监听处理。
	func toggleBrowsingMode() {
		Defaults[.isBrowsingMode].toggle()
	}

	/// 在指定显示器承载面上加载当前网站。
	private func loadUserURL(on surface: DesktopSurface) {
		surface.showWebsiteWallpaper()
		loadURL(WebsitesController.shared.current?.url, on: surface)
	}

	/// 在指定显示器上应用当前壁纸来源配置。
	private func reloadWallpaper(on surface: DesktopSurface) {
		let configuration = Defaults[.wallpaperSettings].configuration(for: surface.display)

		switch configuration.sourceKind {
		case .website:
			loadUserURL(on: surface)
		case .video:
			surface.showVideoWallpaper(configuration.video)
			statusItemButton.toolTip = configuration.video.selectedURL?.lastPathComponent ?? "未选择视频"
		case .image:
			surface.showImageWallpaper(configuration.image)
			statusItemButton.toolTip = configuration.image.selectedURL?.lastPathComponent ?? "未选择图片"
		}
	}

	/// 在所有目标显示器上加载指定 URL。
	func loadURL(_ url: URL?) {
		webViewError = nil

		for surface in desktopSurfaces.values {
			loadURL(url, on: surface)
		}
	}

	/// 在指定显示器承载面上加载 URL，并按显示器尺寸替换占位符。
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

	/// 使用主显示器尺寸替换 URL 中的 Plash 占位符。
	func replacePlaceholders(of url: URL) throws -> URL? {
		// Here we swap out `[[screenWidth]]` and `[[screenHeight]]` for their actual values.
		// We proceed only if we have an `NSScreen` to work with.
		guard let screen = desktopWindow.targetDisplay?.screen ?? .primary else {
			return nil
		}

		return try replacePlaceholders(of: url, for: screen)
	}

	/// 使用指定屏幕尺寸替换 URL 中的 `[[screenWidth]]` 和 `[[screenHeight]]`。
	private func replacePlaceholders(of url: URL, for screen: NSScreen?) throws -> URL? {
		guard let screen else {
			return nil
		}

		return try url
			.replacingPlaceholder("[[screenWidth]]", with: String(format: "%.0f", screen.frameWithoutStatusBar.width))
			.replacingPlaceholder("[[screenHeight]]", with: String(format: "%.0f", screen.frameWithoutStatusBar.height))
	}

	/// 清除所有 WebView 的 Cookie、本地存储和缓存数据。
	func clearWebsiteData() async {
		for surface in desktopSurfaces.values {
			await surface.webViewController.webView.clearWebsiteData()
		}
	}
}
