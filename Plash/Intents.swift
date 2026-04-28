import AppIntents
import AppKit

/// 快捷指令动作：添加一个网站到 Plash。
struct AddWebsiteIntent: AppIntent {
	static let title: LocalizedStringResource = "添加网站"

	static let description = IntentDescription(
		"""
		将网站添加到 Plash。

		返回添加的网站。
		""",
		resultValueName: "添加的网站"
	)

	@Parameter(title: "网址")
	var url: URL

	@Parameter(title: "标题")
	var title: String?

	static var parameterSummary: some ParameterSummary {
		Summary("将 \(\.$url) 添加到 Plash") {
			\.$title
		}
	}

	/// 确保主 App 运行，添加网站并返回对应实体。
	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<WebsiteAppEntity> {
		ensureRunning()
		let website = WebsitesController.shared.add(url, title: title?.nilIfEmptyOrWhitespace).wrappedValue
		return .result(value: .init(website))
	}
}

/// 快捷指令动作：从 Plash 删除指定网站。
struct RemoveWebsitesIntent: AppIntent {
	static let title: LocalizedStringResource = "删除网站"

	static let description = IntentDescription("从 Plash 删除指定网站。")

	@Parameter(title: "网站")
	var websites: [WebsiteAppEntity]

	static var parameterSummary: some ParameterSummary {
		Summary("删除网站 \(\.$websites)")
	}

	/// 删除所有能映射回本地模型的网站实体。
	@MainActor
	func perform() async throws -> some IntentResult {
		ensureRunning()

		for website in websites {
			guard let website = website.toNative else {
				continue
			}

			WebsitesController.shared.remove(website)
		}

		return .result()
	}
}

/// 快捷指令动作：设置或切换 Plash 启用状态。
struct SetEnabledStateIntent: AppIntent {
	static let title: LocalizedStringResource = "设置启用状态"

	static let description = IntentDescription("设置 Plash 的启用状态。")

	@Parameter(
		title: "操作",
		displayName: .init(true: "切换", false: "设置")
	)
	var shouldToggle: Bool

	@Parameter(title: "已启用")
	var isEnabled: Bool

	static var parameterSummary: some ParameterSummary {
		When(\.$shouldToggle, .equalTo, true) {
			Summary("\(\.$shouldToggle) Plash")
		} otherwise: {
			Summary("\(\.$shouldToggle) Plash \(\.$isEnabled)")
		}
	}

	/// 根据参数切换或设置手动停用状态。
	@MainActor
	func perform() async throws -> some IntentResult {
		ensureRunning()

		if shouldToggle {
			AppState.shared.isManuallyDisabled.toggle()
		} else {
			AppState.shared.isManuallyDisabled = !isEnabled
		}

		return .result()
	}
}

/// 快捷指令动作：读取 Plash 当前启用状态。
struct GetEnabledStateIntent: AppIntent {
	static let title: LocalizedStringResource = "获取启用状态"

	static let description = IntentDescription(
		"返回 Plash 当前是否已启用。",
		resultValueName: "启用状态"
	)

	static var parameterSummary: some ParameterSummary {
		Summary("获取 Plash 当前启用状态")
	}

	/// 返回 AppState 当前计算出的启用状态。
	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
		.result(value: AppState.shared.isEnabled)
	}
}

/// 快捷指令动作：获取当前正在显示的网站。
struct GetCurrentWebsiteIntent: AppIntent {
	static let title: LocalizedStringResource = "获取当前网站"

	static let description = IntentDescription(
		"返回 Plash 当前网站。",
		resultValueName: "当前网站"
	)

	/// 返回当前网站实体；没有网站时返回 nil。
	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<WebsiteAppEntity?> {
		ensureRunning()
		return .result(value: WebsitesController.shared.current.flatMap { .init($0) })
	}
}

/// 快捷指令动作：设置当前正在显示的网站。
struct SetCurrentWebsiteIntent: AppIntent {
	static let title: LocalizedStringResource = "设置当前网站"

	static let description = IntentDescription("将 Plash 当前网站设置为指定网站。")

	@Parameter(title: "网站")
	var website: WebsiteAppEntity

	static var parameterSummary: some ParameterSummary {
		Summary("将当前网站设为 \(\.$website)")
	}

	/// 将传入实体映射到本地网站并设为当前项。
	@MainActor
	func perform() async throws -> some IntentResult {
		ensureRunning()
		WebsitesController.shared.current = website.toNative
		return .result()
	}
}

/// 快捷指令动作：重新加载当前网站。
struct ReloadWebsiteIntent: AppIntent {
	static let title: LocalizedStringResource = "重新加载网站"

	static let description = IntentDescription("重新加载 Plash 当前网站。")

	/// 触发当前网站重新加载。
	@MainActor
	func perform() async throws -> some IntentResult {
		ensureRunning()
		AppState.shared.reloadWebsite()
		return .result()
	}
}

/// 快捷指令动作：切换到下一个网站。
struct NextWebsiteIntent: AppIntent {
	static let title: LocalizedStringResource = "切换到下一个网站"

	static let description = IntentDescription("将 Plash 切换到列表中的下一个网站。")

	/// 将网站列表中的下一项设为当前网站。
	@MainActor
	func perform() async throws -> some IntentResult {
		ensureRunning()
		WebsitesController.shared.makeNextCurrent()
		return .result()
	}
}

/// 快捷指令动作：切换到上一个网站。
struct PreviousWebsiteIntent: AppIntent {
	static let title: LocalizedStringResource = "切换到上一个网站"

	static let description = IntentDescription("将 Plash 切换到列表中的上一个网站。")

	/// 将网站列表中的上一项设为当前网站。
	@MainActor
	func perform() async throws -> some IntentResult {
		ensureRunning()
		WebsitesController.shared.makePreviousCurrent()
		return .result()
	}
}

/// 快捷指令动作：随机切换网站。
struct RandomWebsiteIntent: AppIntent {
	static let title: LocalizedStringResource = "切换到随机网站"

	static let description = IntentDescription("将 Plash 切换到列表中的随机网站。")

	/// 随机选择一个网站设为当前网站。
	@MainActor
	func perform() async throws -> some IntentResult {
		ensureRunning()
		WebsitesController.shared.makeRandomCurrent()
		return .result()
	}
}

/// 快捷指令动作：切换浏览模式。
struct ToggleBrowsingModeIntent: AppIntent {
	static let title: LocalizedStringResource = "切换浏览模式"

	static let description = IntentDescription("切换 Plash 的“浏览模式”。")

	/// 切换浏览模式设置。
	@MainActor
	func perform() async throws -> some IntentResult {
		ensureRunning()
		AppState.shared.toggleBrowsingMode()
		return .result()
	}
}

/// 暴露给快捷指令的 Plash 网站实体。
struct WebsiteAppEntity: AppEntity {
	static let typeDisplayRepresentation: TypeDisplayRepresentation = "网站"

	static let defaultQuery = Query()

	let id: UUID

	@Property(title: "标题")
	var title: String

	@Property(title: "网址")
	var url: URL

	@Property(title: "网址主机")
	var urlHost: String

	@Property(title: "当前使用")
	var isCurrent: Bool

	init(_ website: Website) {
		self.id = website.id
		self.title = website.title
		self.url = website.url
		self.urlHost = website.url.host ?? ""
		self.isCurrent = website.isCurrent
	}

	/// 在快捷指令界面展示网站标题和 URL。
	var displayRepresentation: DisplayRepresentation {
		let title = title.nilIfEmptyOrWhitespace
		let urlString = url.absoluteString.removingSchemeAndWWWFromURL
		return .init(
			title: "\(title ?? urlString)",
			subtitle: title != nil ? "\(urlString)" : nil
			// TODO: Show the icon. I must first find a good way to store it to disk.
		)
	}
}

extension WebsiteAppEntity {
	/// 将快捷指令实体映射回当前 Defaults 中的网站模型。
	@MainActor
	var toNative: Website? {
		WebsitesController.shared.all[id: id]
	}
}

extension WebsiteAppEntity {
	/// 支持快捷指令枚举、搜索和按 ID 查找网站实体。
	struct Query: EnumerableEntityQuery, EntityStringQuery {
		static let findIntentDescription = IntentDescription(
			"返回 Plash 中的网站。",
			resultValueName: "网站"
		)

		/// 返回所有网站实体。
		func allEntities() async -> [WebsiteAppEntity] {
			await WebsitesController.shared.all.map(WebsiteAppEntity.init)
		}

		/// 给快捷指令参数选择器提供建议网站。
		func suggestedEntities() async throws -> [WebsiteAppEntity] {
			await allEntities()
		}

		/// 按实体 ID 查找网站。
		func entities(for identifiers: [WebsiteAppEntity.ID]) async throws -> [WebsiteAppEntity] {
			await allEntities().filter { identifiers.contains($0.id) }
		}

		/// 按标题或 URL 模糊搜索网站。
		func entities(matching query: String) async throws -> [WebsiteAppEntity] {
			await allEntities().filter {
				$0.title.localizedCaseInsensitiveContains(query)
					|| $0.url.absoluteString.localizedCaseInsensitiveContains(query)
			}
		}
	}
}

/// 在快捷指令冷启动主 App 时保持应用运行。
func ensureRunning() {
	// It's `prohibited` if the app was not already launched.
	// We activate it so that it will not quit right away if it was not already launched. (macOS 13.4)
	// We don't use `static let openAppWhenRun = true` as it activates (and steals focus) even if the app is already launched.
	if NSApp.activationPolicy() == .prohibited {
		SSApp.url.open()
	}
}
