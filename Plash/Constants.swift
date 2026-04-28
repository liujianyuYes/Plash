import SwiftUI
import KeyboardShortcuts

/// 跨页面共享的窗口入口、Defaults 键和通知名。
enum Constants {
	/// 主窗口打开后需要优先显示的页面。
	@MainActor
	static var pendingAppNavigationPage: AppNavigationPage?

	/// 当前网站管理窗口实例。
	@MainActor
	static var websitesWindow: NSWindow? {
		NSApp.windows.first { $0.identifier?.rawValue == "websites" }
	}

	/// 激活 App 并打开网站管理窗口。
	@MainActor
	static func openWebsitesWindow() {
		SSApp.forceActivate()
		EnvironmentValues().openWindow(id: "websites")
	}

	/// 打开主窗口并切换到设置页。
	@MainActor
	static func openSettingsInWebsitesWindow() {
		pendingAppNavigationPage = .settings
		openWebsitesWindow()

		DispatchQueue.main.async {
			NotificationCenter.default.post(name: .showSettingsPage, object: nil)
		}
	}
}

extension Defaults.Keys {
	/// 用户保存的网站列表。
	static let websites = Key<[Website]>("websites", default: [])
	/// 用户添加到 Plash 桌面窗口上的组件。
	static let desktopComponents = Key<[DesktopComponent]>("desktopComponents", default: DesktopComponent.defaults)
	/// 内置应用的启用状态、后台任务状态和最近错误。
	static let plashApplicationStates = Key<[PlashApplicationState]>("plashApplicationStates", default: [])
	/// 壁纸来源、多显示器和媒体播放配置。
	static let wallpaperSettings = Key<WallpaperSettings>("wallpaperSettings", default: .init())
	/// 是否使用液态玻璃风格的桌面组件背景。
	static let useLiquidGlassComponentBackground = Key<Bool>("useLiquidGlassComponentBackground", default: false)
	/// 当前是否处于可交互的浏览模式。
	static let isBrowsingMode = Key<Bool>("isBrowsingMode", default: false)

	// Settings
	/// 是否隐藏菜单栏图标。
	static let hideMenuBarIcon = Key<Bool>("hideMenuBarIcon", default: false)
	/// 是否在主窗口右下角显示悬浮设置入口。
	static let showFloatingSettingsButton = Key<Bool>("showFloatingSettingsButton", default: true)
	/// 桌面网页的不透明度。
	static let opacity = Key<Double>("opacity", default: 1)
	/// 自动重新加载间隔，单位为秒；为 nil 时关闭。
	static let reloadInterval = Key<Double?>("reloadInterval")
	/// 当前选择的目标显示器。
	static let display = Key<Display?>("display")
	/// 是否在所有显示器显示。
	static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
	/// 使用电池时是否自动停用。
	static let deactivateOnBattery = Key<Bool>("deactivateOnBattery", default: false)
	/// 是否跨所有 Space 显示。
	static let showOnAllSpaces = Key<Bool>("showOnAllSpaces", default: false)
	/// 浏览模式下是否置于其他窗口前方。
	static let bringBrowsingModeToFront = Key<Bool>("bringBrowsingModeToFront", default: false)
	/// 外部域名链接是否交给默认浏览器打开。
	static let openExternalLinksInBrowser = Key<Bool>("openExternalLinksInBrowser", default: false)
	/// 是否静音网页音频。
	static let muteAudio = Key<Bool>("muteAudio", default: true)

	/// 是否把网页窗口延伸到菜单栏下方。
	static let extendPlashBelowMenuBar = Key<Bool>("extendPlashBelowMenuBar", default: false)
}

extension KeyboardShortcuts.Name {
	/// 切换浏览模式快捷键名。
	static let toggleBrowsingMode = Self("toggleBrowsingMode")
	/// 切换启用状态快捷键名。
	static let toggleEnabled = Self("toggleEnabled")
	/// 重新加载快捷键名。
	static let reload = Self("reload")
	/// 切换到下一个网站快捷键名。
	static let nextWebsite = Self("nextWebsite")
	/// 切换到上一个网站快捷键名。
	static let previousWebsite = Self("previousWebsite")
	/// 随机切换网站快捷键名。
	static let randomWebsite = Self("randomWebsite")
}

extension Notification.Name {
	/// 请求主窗口切换到设置页。
	static let showSettingsPage = Self("showSettingsPage")
}
