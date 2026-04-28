import Cocoa

extension AppState {
	/// 首次启动时展示欢迎提示，并引导用户添加第一个网站。
	func showWelcomeScreenIfNeeded() {
		guard SSApp.isFirstLaunch else {
			return
		}

		SSApp.forceActivate()

		NSAlert.showModal(
			title: "欢迎使用 Plash！",
			message:
				"""
				Plash 位于菜单栏中（屏幕右上角的水滴图标）。在“网站”页面中点击右上角的加号开始使用。

				如果需要登录网站或以其他方式与网站交互，请使用“浏览模式”。

				你可以在设置中选择让 Plash 显示在单个显示器或所有已连接的显示器上。
				""",
			buttonTitles: [
				"继续"
			],
			defaultButtonIndex: -1
		)

		// Does not work on macOS 11 or later.
//		statusItemButton.playRainbowAnimation()

		delay(.seconds(1)) { [self] in
			statusItemButton.performClick(nil)
		}

		guard Defaults[.websites].isEmpty else {
			return
		}

		Constants.openWebsitesWindow()
	}
}
