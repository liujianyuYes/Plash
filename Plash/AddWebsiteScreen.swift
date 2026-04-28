import SwiftUI
import LinkPresentation

/// 添加或编辑网站的表单页面。
struct AddWebsiteScreen: View {
	@Environment(\.dismiss) private var dismiss
	@State private var hostingWindow: NSWindow?
	@State private var isFetchingTitle = false
	@State private var isApplyConfirmationPresented = false
	@State private var originalWebsite: Website?
	@State private var urlString = ""

	@State private var newWebsite = Website(
		id: UUID(),
		isCurrent: true,
		url: ".",
		usePrintStyles: false
	)

	/// 当前 URL 字段和模型 URL 是否都合法。
	private var isURLValid: Bool {
		URL.isValid(string: urlString)
			&& website.wrappedValue.url.isValid
	}

	/// 编辑模式下判断当前表单是否相对原始网站有变更。
	private var hasChanges: Bool { website.wrappedValue != originalWebsite }

	private let isEditing: Bool

	// TODO: `@OptionalBinding` extension?
	private var existingWebsite: Binding<Website>?

	/// 编辑时使用外部绑定，添加时使用临时新网站状态。
	private var website: Binding<Website> { existingWebsite ?? $newWebsite }

	/// 创建添加或编辑页面，并在编辑模式中初始化原始状态。
	init(
		isEditing: Bool,
		website: Binding<Website>?
	) {
		self.isEditing = isEditing
		self.existingWebsite = website
		self._originalWebsite = .init(wrappedValue: website?.wrappedValue)

		if isEditing {
			self._urlString = .init(wrappedValue: website?.wrappedValue.url.absoluteString ?? "")
		}
	}

	/// 网站表单主体，包括 URL/标题输入、首次启动提示和编辑选项。
	var body: some View {
		Form {
			topView
			if SSApp.isFirstLaunch, !isEditing {
				firstLaunchView
			}
			if isEditing {
				editingView
			}
		}
		.formStyle(.grouped)
		.frame(width: 500)
		.fixedSize()
		.bindHostingWindow($hostingWindow)
		// Note: Current only works when a text field is focused. (macOS 11.3)
		.onExitCommand {
			guard
				isEditing,
				hasChanges
			else {
				dismiss()
				return
			}

			isApplyConfirmationPresented = true
		}
		.onSubmit {
			submit()
		}
		.confirmationDialog2(
			"保留更改？",
			isPresented: $isApplyConfirmationPresented
		) {
			Button("保留") {
				dismiss()
			}
			Button("不保留", role: .destructive) {
				revert()
				dismiss()
			}
			Button("取消", role: .cancel) {}
		}
		.toolbar {
			if isEditing {
				ToolbarItem {
					Button("还原") {
						revert()
					}
					.disabled(!hasChanges)
				}
			} else {
				ToolbarItem(placement: .cancellationAction) {
					Button("取消") {
						dismiss()
					}
				}
			}
			ToolbarItem(placement: .confirmationAction) {
				Button(isEditing ? "完成" : "添加") {
					submit()
				}
				.disabled(!isURLValid)
			}
		}
		.task {
			guard isEditing else {
				return
			}

			website.wrappedValue.makeCurrent()
		}
	}

	/// 首次启动时显示的示例网站提示。
	private var firstLaunchView: some View {
		Section {
			HStack {
				HStack(spacing: 3) {
					Text("你可以例如")
					Button("显示时间。") {
						urlString = "https://time.pablopunk.com/?seconds&fg=white&bg=transparent"
					}
					.buttonStyle(.link)
				}
				Spacer()
				Link("更多灵感", destination: "https://github.com/sindresorhus/Plash/discussions/136")
					.buttonStyle(.link)
			}
		}
	}

	/// URL、标题和本地网站选择区域。
	private var topView: some View {
		Section {
			TextField("网址", text: $urlString)
				.textContentType(.URL)
				.lineLimit(1)
				// This change listener is used to respond to URL changes from the outside, like the "Revert" button or the Shortcuts actions.
				.onChange(of: website.wrappedValue.url) { _, url in
					guard
						url.absoluteString != "-",
						url.absoluteString != urlString
					else {
						return
					}

					urlString = url.absoluteString
				}
				.onChange(of: urlString) {
					guard let url = URL(humanString: urlString) else {
						// Makes the “Revert” button work if the user clears the URL field.
						if urlString.trimmed.isEmpty {
							website.wrappedValue.url = "-"
						} else if
							let url = URL(string: urlString, encodingInvalidCharacters: false),
							url.isValid
						{
							website.wrappedValue.url = url
						}

						return
					}

					guard url.isValid else {
						return
					}

					website.wrappedValue.url = url
						.normalized(
							removeDefaultPort: false, // We need to allow typing `http://172.16.0.100:8080`.
							removeWWW: false // Some low-quality sites don't work without this.
						)
				}
				.debouncingTask(id: website.wrappedValue.url, interval: .seconds(0.5)) {
					await fetchTitle()
				}
			TextField("标题", text: website.title)
				.lineLimit(1)
				.disabled(isFetchingTitle)
				.overlay(alignment: .leading) {
					if isFetchingTitle {
						ProgressView()
							.controlSize(.small)
							.offset(x: 50)
					}
				}
		} footer: {
			Button("本地网站…") {
				Task {
					guard let url = await chooseLocalWebsite() else {
						return
					}

					urlString = url.absoluteString
				}
			}
			.controlSize(.small)
		}
	}

	/// 编辑已有网站时可用的高级渲染选项。
	@ViewBuilder
	private var editingView: some View {
		Section {
			EnumPicker("反转颜色", selection: website.invertColors2) {
				Text($0.title)
			}
			.help("为没有原生深色模式的网站创建伪深色模式，方法是反转网站的所有颜色。")
			Toggle("使用打印样式", isOn: website.usePrintStyles)
				.help("如果网站提供打印样式（“@media print”），强制使用它。有些网站的打印版更简洁，例如 Google 日历。")
			let cssHelpText = "你可以用 CSS 修改网站，例如调整颜色或隐藏不需要的元素。"
			VStack(alignment: .leading) {
				HStack {
					Text("CSS")
					Spacer()
					InfoPopoverButton(cssHelpText)
						.controlSize(.small)
				}
				ScrollableTextView(
					text: website.css,
					font: .monospacedSystemFont(ofSize: 11, weight: .regular),
					isAutomaticQuoteSubstitutionEnabled: false,
					isAutomaticDashSubstitutionEnabled: false,
					isAutomaticTextReplacementEnabled: false,
					isAutomaticSpellingCorrectionEnabled: false
				)
				.frame(height: 70)
			}
			.accessibilityElement(children: .combine)
			.accessibilityLabel("CSS")
			.accessibilityHint(Text(cssHelpText))
			let javaScriptHelpText = "你可以用 JavaScript 修改网站。尽量优先使用 CSS。可以在顶层使用“await”。"
			VStack(alignment: .leading) {
				HStack {
					Text("JavaScript")
					Spacer()
					InfoPopoverButton(javaScriptHelpText)
						.controlSize(.small)
				}
				ScrollableTextView(
					text: website.javaScript,
					font: .monospacedSystemFont(ofSize: 11, weight: .regular),
					isAutomaticQuoteSubstitutionEnabled: false,
					isAutomaticDashSubstitutionEnabled: false,
					isAutomaticTextReplacementEnabled: false,
					isAutomaticSpellingCorrectionEnabled: false
				)
				.frame(height: 70)
			}
			.accessibilityElement(children: .combine)
			.accessibilityLabel("JavaScript")
			.accessibilityHint(Text(javaScriptHelpText))
		}
		Section("高级") {
			Toggle("允许自签名证书", isOn: website.allowSelfSignedCertificate)
		}
	}

	/// 提交表单；编辑模式关闭窗口，添加模式写入网站列表。
	private func submit() {
		guard isURLValid else {
			return
		}

		if isEditing {
			dismiss()
		} else {
			add()
		}
	}

	/// 恢复编辑前的网站配置。
	private func revert() {
		guard let originalWebsite else {
			return
		}

		website.wrappedValue = originalWebsite
	}

	/// 将新网站添加到全局列表，并在首次使用时提示双击编辑。
	private func add() {
		WebsitesController.shared.add(website.wrappedValue)
		dismiss()

		SSApp.runOnce(identifier: "editWebsiteTip") {
			// TODO: Find a better way to inform the user about this.
			Task {
				await NSAlert.show(
					title: "双击列表中的网站即可编辑、切换深色模式、添加自定义 CSS/JavaScript 等。"
				)
			}
		}
	}

	/// 打开目录选择器，选择包含 `index.html` 的本地网站目录。
	private func chooseLocalWebsite() async -> URL? {
//		guard let hostingWindow else {
//			return nil
//		}

		let panel = NSOpenPanel()
		panel.canChooseFiles = false
		panel.canChooseDirectories = true
		panel.canCreateDirectories = false
		panel.title = "选择本地网站"
		panel.message = "请选择包含“index.html”文件的目录。"
		panel.prompt = "选择"

		// Ensure it's above the window when in "Browsing Mode".
		panel.level = .modalPanel

		let url = website.wrappedValue.url

		if
			isEditing,
			url.isFileURL
		{
			panel.directoryURL = url
		}

		// TODO: Make it a sheet instead when targeting the macOS bug is fixed. (macOS 15.3)
//		let result = await panel.beginSheet(hostingWindow)
		let result = await panel.begin()

		guard
			result == .OK,
			let url = panel.url
		else {
			return nil
		}

		guard url.appendingPathComponent("index.html", isDirectory: false).exists else {
			await NSAlert.show(title: "请选择包含“index.html”文件的目录。")
			return await chooseLocalWebsite()
		}

		do {
			try SecurityScopedBookmarkManager.saveBookmark(for: url)
		} catch {
			await error.present()
			return nil
		}

		return url
	}

	/// 在 URL 改变后尝试抓取网页标题，避免覆盖用户手动填写的标题。
	private func fetchTitle() async {
		// Ensure we don't erase a user's existing title.
		if
			isEditing,
			!website.title.wrappedValue.isEmpty
		{
			return
		}

		let url = website.wrappedValue.url

		guard url.isValid else {
			website.wrappedValue.title = ""
			return
		}

		withAnimation {
			isFetchingTitle = true
		}

		defer {
			withAnimation {
				isFetchingTitle = false
			}
		}

		let metadataProvider = LPMetadataProvider()
		metadataProvider.shouldFetchSubresources = false
		metadataProvider.timeout = 5

		guard
			let metadata = try? await metadataProvider.startFetchingMetadata(for: url),
			let title = metadata.title
		else {
			if !isEditing || website.wrappedValue.title.isEmpty {
				website.wrappedValue.title = ""
			}

			return
		}

		website.wrappedValue.title = title
	}
}
