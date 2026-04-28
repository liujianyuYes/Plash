import WebKit

/// Plash 专用 WebView，扩展右键菜单、浏览模式标记和每站点缩放记忆。
final class SSWebView: WKWebView {
	/// 允许桌面窗口中的网页在第一次点击时接收鼠标事件。
	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

	private var cancellables = Set<AnyCancellable>()

	private var excludedMenuItems: Set<MenuItemIdentifier> = [
		.downloadImage,
		.downloadLinkedFile,
		.downloadMedia,
		.openLinkInNewWindow,
		.shareMenu,
		.toggleEnhancedFullScreen,
		.toggleFullScreen
	]

	override init(frame: CGRect, configuration: WKWebViewConfiguration) {
		super.init(frame: frame, configuration: configuration)

		Defaults.publisher(.isBrowsingMode)
			.receive(on: DispatchQueue.main)
			.sink { [weak self] _ in
				self?.toggleBrowsingModeClass()
			}
			.store(in: &cancellables)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	/// 在系统右键菜单打开前裁剪不适合 Plash 场景的项目，并加入缩放与保存 URL 操作。
	override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
		for menuItem in menu.items {
			// Debug menu items
			// print("Menu Item:", menuItem.title, menuItem.identifier?.rawValue ?? "")

			if let identifier = MenuItemIdentifier(menuItem) {
				if
					identifier == .openImageInNewWindow
				{
					menuItem.title = "打开图片"
				}

				if
					identifier == .openMediaInNewWindow
				{
					menuItem.title = "打开视频"
				}

				if
					identifier == .openFrameInNewWindow
				{
					menuItem.title = "打开框架"
				}

				if
					identifier == .openLinkInNewWindow
				{
					menuItem.title = "打开链接"
				}
			}
		}

		menu.items.removeAll {
			guard let identifier = MenuItemIdentifier($0) else {
				return false
			}

			return excludedMenuItems.contains(identifier)
		}

		menu.addSeparator()

		menu.addCallbackItem("实际大小", isEnabled: pageZoom != 1) { [weak self] in
			self?.zoomLevelWrapper = 1
		}

		menu.addCallbackItem("放大") { [weak self] in
			self?.zoomLevelWrapper += 0.2
		}

		menu.addCallbackItem("缩小") { [weak self] in
			self?.zoomLevelWrapper -= 0.2
		}

		menu.addSeparator()

		if
			let website = WebsitesController.shared.current,
			let url = url?.normalized(),
			website.url.normalized() != url
		{
			let menuItem = menu.addCallbackItem("将网站更新为当前页面") {
				WebsitesController.shared.all = WebsitesController.shared.all.modifying(elementWithID: website.id) {
					$0.url = url
				}
			}

			menuItem.toolTip = "将保存的网站 URL 更新为当前 URL"
		}

		menu.addSeparator()

		// Move the “Inspect Element” menu item to the end.
		if let menuItem = (menu.items.first { MenuItemIdentifier($0) == .inspectElement }) {
			menu.items = menu.items.movingToEnd(menuItem)
		}

		if Defaults[.hideMenuBarIcon] {
			menu.addCallbackItem("显示菜单栏图标") {
				AppState.shared.handleMenuBarIcon()
			}
		}

		// For the implicit “Services” menu.
		menu.addSeparator()
	}

	/// 按当前浏览模式状态给网页根元素添加或移除 CSS 类。
	func toggleBrowsingModeClass() {
		Task {
			try? await callAsyncJavaScript(
				"document.documentElement.classList[method]('plash-is-browsing-mode')",
				arguments: [
					"method": Defaults[.isBrowsingMode] ? "add" : "remove"
				],
				contentWorld: .page
			)
		}
	}
}

extension SSWebView {
	/// 当前页面缩放级别在 Defaults 中使用的键。
	private var zoomLevelDefaultsKey: Defaults.Key<Double?>? {
		guard let url else {
			return nil
		}

		let keyPart = url
			.normalized(removeFragment: true, removeQuery: true)
			.absoluteString
			.removingSchemeAndWWWFromURL
			.toData
			.base64EncodedString()

		return .init("zoomLevel_\(keyPart)")
	}

	/// 当前页面持久化保存过的缩放级别。
	var zoomLevelDefaultsValue: Double? {
		guard
			let zoomLevelDefaultsKey,
			let zoomLevel = Defaults[zoomLevelDefaultsKey]
		else {
			return nil
		}

		return zoomLevel
	}

	/// 读写页面缩放级别，并按规范化 URL 记住用户设置。
	var zoomLevelWrapper: Double {
		get { zoomLevelDefaultsValue ?? pageZoom }
		set {
			pageZoom = newValue

			if let zoomLevelDefaultsKey {
				Defaults[zoomLevelDefaultsKey] = newValue
			}
		}
	}
}
