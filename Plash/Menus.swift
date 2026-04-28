import Cocoa

extension AppState {
	/// 在菜单顶部显示当前网站标题和提示信息。
	private func addInfoMenuItem() {
		guard let website = WebsitesController.shared.current else {
			return
		}

		var url = website.url
		do {
			url = try replacePlaceholders(of: url) ?? url
		} catch {
			error.presentAsModal()
			return
		}

		let maxLength = 30

		if !website.menuTitle.isEmpty {
			let menuItem = menu.addDisabled(website.menuTitle.truncating(to: maxLength))
			menuItem.toolTip = website.tooltip
		}
	}

	/// 创建用于切换当前网站的子菜单。
	private func createSwitchMenu() -> SSMenu {
		let menu = SSMenu()

		for website in WebsitesController.shared.all {
			let menuItem = menu.addCallbackItem(
				website.menuTitle.truncating(to: 40),
				isChecked: website.isCurrent
			) {
				website.makeCurrent()
			}

			menuItem.toolTip = website.tooltip
		}

		return menu
	}

	/// 添加当前网站相关的菜单项，如重载、浏览模式、编辑和切换。
	private func addWebsiteItems() {
		if let webViewError {
			menu.addDisabled("错误：\(webViewError.localizedDescription)".wordWrapped(atLength: 36).toNSAttributedString)
			menu.addSeparator()
		}

		guard !WebsitesController.shared.all.isEmpty else {
			return
		}

		addInfoMenuItem()

		menu.addSeparator()

		menu.addCallbackItem(
			"重新加载",
			isEnabled: WebsitesController.shared.current != nil
		) { [weak self] in
			self?.reloadWebsite()
		}
		.setShortcut(for: .reload)

		// TODO: DRY this up with the one in SSWebView when everything is in SwiftUI.
		if
			let website = WebsitesController.shared.current,
			let url = webViewController.webView.url?.normalized(),
			website.url.normalized() != url
		{
			let menuItem = menu.addCallbackItem("将网站更新为当前页面") {
				WebsitesController.shared.all = WebsitesController.shared.all.modifying(elementWithID: website.id) {
					$0.url = url
				}
			}

			menuItem.toolTip = "将保存的网站 URL 更新为当前 URL"
		}

		menu.addCallbackItem(
			"浏览模式",
			isEnabled: WebsitesController.shared.current != nil,
			isChecked: Defaults[.isBrowsingMode]
		) {
			Defaults[.isBrowsingMode].toggle()

			SSApp.runOnce(identifier: "activatedBrowsingMode") {
				DispatchQueue.main.async {
					NSAlert.showModal(
						title: "浏览模式可让你临时与网页交互。例如登录账号或滚动到网页中的指定位置。",
						message: "如果当前看不到网页，可能需要隐藏一些窗口以露出桌面。"
					)
				}
			}
		}
		.setShortcut(for: .toggleBrowsingMode)

		if WebsitesController.shared.all.count > 1 {
			menu.addSeparator()

			menu.addCallbackItem("下一个") {
				WebsitesController.shared.makeNextCurrent()
			}
			.setShortcut(for: .nextWebsite)

			menu.addCallbackItem("上一个") {
				WebsitesController.shared.makePreviousCurrent()
			}
			.setShortcut(for: .previousWebsite)

			menu.addCallbackItem("随机") {
				WebsitesController.shared.makeRandomCurrent()
			}
			.setShortcut(for: .randomWebsite)

			menu.addItem("切换")
				.withSubmenu(createSwitchMenu())
		}
	}

	/// 按当前启用状态和网站列表重建菜单栏菜单。
	func updateMenu() {
		menu.removeAllItems()

		if (isEnabled || isManuallyDisabled) || (!Defaults[.deactivateOnBattery] && powerSourceWatcher?.powerSource.isUsingBattery == false) {
			menu.addCallbackItem(
				isManuallyDisabled ? "启用" : "停用"
			) { [self] in
				isManuallyDisabled.toggle()
			}
		}

		menu.addSeparator()

		if isEnabled {
			let itemCount = menu.items.count
			addWebsiteItems()

			if menu.items.count > itemCount {
				menu.addSeparator()
			}
		} else if !isManuallyDisabled {
			menu.addDisabled("使用电池时已停用")
			menu.addSeparator()
		}

		menu.addSettingsItem()

		menu.addQuitItem()
	}
}
