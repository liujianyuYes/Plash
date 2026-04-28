import SwiftUI

/**
TODO macOS 16:
- Use `MenuBarExtra` and afterwards switch to `@Observable`.
- Remove `Combine` and `Defaults.publisher` usage.
- Remove `ensureRunning()` from some intents that don't require Plash to stay open.
- Focus filter support.
- Use SwiftUI for the desktop window and the web view.
*/

/// 应用入口，负责初始化全局配置并声明主窗口与设置窗口。
@main
struct AppMain: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
	@StateObject private var appState = AppState.shared

	/// 在 SwiftUI 场景创建前完成进程级配置。
	init() {
		setUpConfig()
	}

	/// 声明侧边栏主窗口和系统设置窗口两个 SwiftUI 场景。
	var body: some Scene {
		Window("Plash", id: "websites") {
			AppNavigationScreen(initialSelection: .wallpaper)
				.environmentObject(appState)
		}
		.windowToolbarStyle(.unifiedCompact)
		.windowResizability(.contentSize)
		.defaultPosition(.center)
		.defaultLaunchBehavior(.suppressed)
		Settings {
			AppNavigationScreen(initialSelection: .settings)
				.environmentObject(appState)
		}
	}

	/// 注册默认值、崩溃上报、外部事件监听和后台存活策略。
	private func setUpConfig() {
		UserDefaults.standard.register(defaults: [
			"NSApplicationCrashOnExceptions": true
		])

		SSApp.initSentry("https://4ad446a4961b44ff8dc808a08379914e@o844094.ingest.sentry.io/6140750")
		SSApp.setUpExternalEventListeners()
		ProcessInfo.processInfo.disableAutomaticTermination("")
		ProcessInfo.processInfo.disableSuddenTermination()
	}
}

/// 主窗口侧边栏页面。
enum AppNavigationPage: String, CaseIterable, Identifiable {
	case wallpaper
	case apps
	case components
	case settings

	/// 页面唯一标识。
	var id: Self { self }

	/// 侧边栏显示标题。
	var title: String {
		switch self {
		case .wallpaper:
			"壁纸"
		case .apps:
			"应用"
		case .components:
			"组件"
		case .settings:
			"设置"
		}
	}

	/// 侧边栏图标。
	var systemImage: String {
		switch self {
		case .wallpaper:
			"photo.on.rectangle"
		case .apps:
			"app"
		case .components:
			"square.grid.2x2"
		case .settings:
			"gearshape"
		}
	}
}

/// 统一承载网站管理和设置页的侧边栏窗口。
struct AppNavigationScreen: View {
	@State private var selection: AppNavigationPage

	/// 创建侧边栏窗口并指定首次选中的页面。
	init(initialSelection: AppNavigationPage) {
		self._selection = .init(initialValue: initialSelection)
	}

	/// 侧边栏导航和详情页面。
	var body: some View {
		NavigationSplitView {
			List(AppNavigationPage.allCases, selection: $selection) { page in
				NavigationLink(value: page) {
					Label(page.title, systemImage: page.systemImage)
				}
			}
			.listStyle(.sidebar)
			.navigationTitle("Plash")
			.navigationSplitViewColumnWidth(min: 140, ideal: 160, max: 220)
		} detail: {
			switch selection {
			case .wallpaper:
				WallpaperScreen()
					.navigationTitle(AppNavigationPage.wallpaper.title)
			case .apps:
				ApplicationsScreen()
					.navigationTitle(AppNavigationPage.apps.title)
			case .components:
				DesktopComponentsScreen()
					.navigationTitle(AppNavigationPage.components.title)
			case .settings:
				SettingsScreen()
					.navigationTitle(AppNavigationPage.settings.title)
			}
		}
		.frame(width: 760, height: 600)
		.onNotification(.showSettingsPage) { _ in
			selection = .settings
		}
		.onAppear {
			guard let pendingPage = Constants.pendingAppNavigationPage else {
				return
			}

			selection = pendingPage
			Constants.pendingAppNavigationPage = nil
		}
	}
}

/// 右下角的液态玻璃设置入口。
struct FloatingSettingsButton: View {
	let action: () -> Void

	/// 显示齿轮按钮；新系统使用原生 glass，旧系统使用 material 回退。
	var body: some View {
		if #available(macOS 26.0, *) {
			Button(action: action) {
				Image(systemName: "gearshape.fill")
					.font(.system(size: 17, weight: .semibold))
					.frame(width: 34, height: 34)
			}
			.buttonStyle(.glass)
			.help("设置")
			.accessibilityLabel("设置")
		} else {
			Button(action: action) {
				Image(systemName: "gearshape.fill")
					.font(.system(size: 18, weight: .semibold))
					.symbolRenderingMode(.hierarchical)
					.frame(width: 46, height: 46)
					.background(.regularMaterial, in: Circle())
					.overlay {
						Circle()
							.stroke(.white.opacity(0.28), lineWidth: 1)
					}
					.shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
			}
			.buttonStyle(.plain)
			.help("设置")
			.accessibilityLabel("设置")
		}
	}
}

/// 尚未实现的侧边栏页面占位视图。
private struct PlaceholderPage: View {
	let title: String
	let systemImage: String

	/// 显示当前页面名称和待实现状态。
	var body: some View {
		ContentUnavailableView(
			title,
			systemImage: systemImage,
			description: Text("待实现")
		)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}

/// 桥接 AppKit 生命周期，处理 URL 命令注册和重复启动行为。
final class AppDelegate: NSObject, NSApplicationDelegate {
	// Without this, Plash quits when the screen is locked. (macOS 13.2)
	/// 保持菜单栏应用在窗口关闭后继续运行。
	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

	/// 尽早注册 URL Scheme 监听，确保冷启动命令不会丢失。
	func applicationWillFinishLaunching(_ notification: Notification) {
		// It's important that this is here so it's registered in time.
		AppState.shared.setUpURLCommands()
		PlashApplicationController.shared.start()
	}

	// This is only run when the app is started when it's already running.
	/// 用户再次打开已运行的 App 时临时显示菜单栏图标。
	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		AppState.shared.handleAppReopen()
		return false
	}
}
