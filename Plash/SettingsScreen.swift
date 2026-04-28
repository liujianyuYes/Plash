import SwiftUI
import LaunchAtLogin
import KeyboardShortcuts

/// 设置窗口根页面，用小标题整合常规、快捷键和高级设置。
struct SettingsScreen: View {
	/// 设置窗口的单页表单布局。
	var body: some View {
		Form {
			Section("常规") {
				LaunchAtLogin.Toggle("登录时启动")
				ReloadIntervalSetting()
				OpacitySetting()
				ShowOnAllDisplaysSetting()
				DisplaySetting()
				ShowOnAllSpacesSetting()
				Defaults.Toggle("显示悬浮设置入口", key: .showFloatingSettingsButton)
			}

			Section("快捷键") {
				KeyboardShortcuts.Recorder("切换启用状态", name: .toggleEnabled)
				KeyboardShortcuts.Recorder("切换浏览模式", name: .toggleBrowsingMode)
				KeyboardShortcuts.Recorder("重新加载网站", name: .reload)
				KeyboardShortcuts.Recorder("下一个网站", name: .nextWebsite)
				KeyboardShortcuts.Recorder("上一个网站", name: .previousWebsite)
				KeyboardShortcuts.Recorder("随机网站", name: .randomWebsite)
			}

			Section("高级") {
				BringBrowsingModeToFrontSetting()
				Defaults.Toggle("使用电池时停用", key: .deactivateOnBattery)
				OpenExternalLinksInBrowserSetting()
				HideMenuBarIconSetting()
				Defaults.Toggle("静音", key: .muteAudio)
				Divider()
				ClearWebsiteDataSetting()
					.controlSize(.small)
			}
		}
		.formStyle(.grouped)
		.frame(width: 460, height: 560)
		.windowLevel(.floating + 1) // To ensure it's always above the Plash browser window.
	}
}

/// 控制 Plash 是否在所有显示器上显示。
private struct ShowOnAllDisplaysSetting: View {
	/// 多显示器开关。
	var body: some View {
		Defaults.Toggle(
			"在所有显示器上显示",
			key: .showOnAllDisplays
		)
	}
}

/// 控制 Plash 是否跨所有 Space 显示。
private struct ShowOnAllSpacesSetting: View {
	/// 所有 Space 开关。
	var body: some View {
		Defaults.Toggle(
			"在所有空间显示",
			key: .showOnAllSpaces
		)
		.help("关闭时，Plash 只会在启动时处于活跃状态的空间中显示网站。")
	}
}

/// 控制浏览模式下窗口是否置于其他窗口前方。
private struct BringBrowsingModeToFrontSetting: View {
	/// 浏览模式置顶开关。
	var body: some View {
		// TODO: Find a better title for this.
		Defaults.Toggle(
			"浏览模式置于最前",
			key: .bringBrowsingModeToFront
		)
		.help("启用浏览模式时，让网页保持在所有窗口上方。")
	}
}

/// 控制站点跳转到其他域名时是否交给默认浏览器。
private struct OpenExternalLinksInBrowserSetting: View {
	/// 外部链接打开方式开关。
	var body: some View {
		Defaults.Toggle(
			"用默认浏览器打开外部链接",
			key: .openExternalLinksInBrowser
		)
		.help("如果网站需要登录，登录时建议关闭此设置；否则网站跳转到其他页面时，可能会在浏览器中打开，而不是在 Plash 中打开。")
	}
}

/// 调整桌面网页不透明度。
private struct OpacitySetting: View {
	@Default(.opacity) private var opacity

	/// 不透明度滑块。
	var body: some View {
		Slider(
			value: $opacity,
			in: 0.1...1,
			step: 0.1
		) {
			Text("不透明度")
		}
		.help("浏览模式始终使用完全不透明。")
	}
}

/// 配置自动重新加载间隔。
private struct ReloadIntervalSetting: View {
	private static let defaultReloadInterval = 60.0
	private static let minimumReloadInterval = 0.1

	@Default(.reloadInterval) private var reloadInterval
	@FocusState private var isTextFieldFocused: Bool

	// TODO: Improve VoiceOver accessibility for this control.
	/// 重新加载间隔输入、步进器和启用开关。
	var body: some View {
		LabeledContent("每隔") {
			HStack {
				TextField(
					"",
					value: reloadIntervalInMinutes,
					format: .number.grouping(.never).precision(.fractionLength(1))
				)
				.labelsHidden()
				.focused($isTextFieldFocused)
				.frame(width: 40)
				.disabled(reloadInterval == nil)
				Stepper(
					"",
					value: reloadIntervalInMinutes.didSet { _ in
						// We have to unfocus the text field because sometimes it's in a state where it does not update the value. Some kind of bug with the formatter. (macOS 12.4)
						isTextFieldFocused = false
					},
					in: Self.minimumReloadInterval...(.greatestFiniteMagnitude),
					step: 1
				)
				.labelsHidden()
				.disabled(reloadInterval == nil)
				Text("分钟")
					.textSelection(.disabled)
			}
			.contentShape(.rect)
			Toggle("定时重新加载", isOn: $reloadInterval.isNotNil(trueSetValue: Self.defaultReloadInterval))
				.labelsHidden()
				.controlSize(.mini)
				.toggleStyle(.switch)
		}
		.accessibilityLabel("重新加载间隔，单位为分钟")
		.contentShape(.rect)
	}

	/// 将秒级 Defaults 值映射为分钟级 UI 绑定。
	private var reloadIntervalInMinutes: Binding<Double> {
		$reloadInterval.withDefaultValue(Self.defaultReloadInterval).secondsToMinutes
	}

	// TODO: We don't use this binding as it causes the toggle to not always work because of some weirdities with the formatter. (macOS 12.4)
//	private var hasInterval: Binding<Bool> {
//		$reloadInterval.isNotNil(trueSetValue: Self.defaultReloadInterval)
//	}
}

/// 控制菜单栏图标隐藏，并在启用时提示恢复方式。
private struct HideMenuBarIconSetting: View {
	@State private var isShowingAlert = false

	/// 菜单栏图标隐藏开关和提示弹窗。
	var body: some View {
		Defaults.Toggle("隐藏菜单栏图标", key: .hideMenuBarIcon)
			.onChange {
				isShowingAlert = $0
			}
			.alert2(
				"如果需要打开 Plash 菜单，请再次启动 App，菜单栏图标会显示 5 秒。",
				isPresented: $isShowingAlert
			)
	}
}

/// 选择 Plash 显示在哪个显示器上。
private struct DisplaySetting: View {
	@ObservedObject private var displayWrapper = Display.observable
	@Default(.display) private var chosenDisplay
	@Default(.showOnAllDisplays) private var showOnAllDisplays

	/// 显示器选择器；启用所有显示器时禁用。
	var body: some View {
		Picker(
			selection: $chosenDisplay.getMap(\.?.withFallbackToMain)
		) {
			ForEach(displayWrapper.wrappedValue.all) { display in
				Text(display.localizedName)
					.tag(display)
					// A view cannot have multiple tags, otherwise, this would have been the best solution.
//					.if(display == .main) {
//						$0.tag(nil as Display?)
//					}
			}
		} label: {
			Text("显示在")
			Link("多显示器支持 ›", destination: "https://github.com/sindresorhus/Plash/issues/2")
		}
		.disabled(showOnAllDisplays)
		.task(id: chosenDisplay) {
			guard chosenDisplay == nil else {
				return
			}

			chosenDisplay = .main
		}
	}
}

/// 清除所有网站数据和图标缓存。
private struct ClearWebsiteDataSetting: View {
	@State private var hasCleared = false

	/// 清除数据按钮。
	var body: some View {
		// Not marked as destructive as it should mostly be used when it's together with other buttons.
		Button("清除所有网站数据") {
			Task {
				hasCleared = true
				WebsitesController.shared.thumbnailCache.removeAllImages()
				await AppState.shared.clearWebsiteData()
			}
		}
		.help("清除所有 Cookie、本地存储、缓存等。")
		.disabled(hasCleared)
	}
}

#Preview {
	SettingsScreen()
}
