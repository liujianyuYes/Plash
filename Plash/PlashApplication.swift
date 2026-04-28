import Foundation

/// Plash 内部应用的运行状态。
enum PlashApplicationStatus: String, Codable, Sendable {
	case enabled
	case disabled
	case running
	case failed

	/// 面向用户的状态名称。
	var title: String {
		switch self {
		case .enabled:
			"已启用"
		case .disabled:
			"已禁用"
		case .running:
			"运行中"
		case .failed:
			"出错"
		}
	}
}

/// 单个后台任务的持久化运行信息。
struct PlashApplicationBackgroundTaskState: Hashable, Codable, Sendable {
	var id: String
	var isRunning = false
	var lastRunDate: Date?
	var nextRunDate: Date?
	var lastError: String?
}

/// 单个内部应用的持久化状态。
struct PlashApplicationState: Hashable, Codable, Identifiable, Sendable, Defaults.Serializable {
	var id: String
	var isEnabled: Bool
	var status: PlashApplicationStatus
	var lastRunDate: Date?
	var lastStorageResetDate: Date?
	var lastError: String?
	var backgroundTaskStates: [String: PlashApplicationBackgroundTaskState]
}

/// 内部应用提供给桌面组件系统的组件定义。
struct PlashApplicationComponentDefinition: Hashable, Identifiable, Sendable {
	let id: String
	let applicationID: String
	let kind: DesktopComponentKind
	let defaultSize: DesktopComponentSize

	/// 组件标题。
	var title: String { kind.title }

	/// 组件图标。
	var systemImage: String { kind.systemImage }
}

/// 内部应用声明的后台任务。
struct PlashApplicationBackgroundTaskDefinition: Identifiable {
	let id: String
	let title: String
	let interval: TimeInterval
	let action: @MainActor (PlashApplicationContext) async throws -> Void
}

/// 内部应用声明的设置项。
struct PlashApplicationSettingDefinition: Hashable, Identifiable, Sendable {
	let id: String
	let title: String
	let detail: String
}

/// 一个可由 Plash 管理生命周期、存储、组件和后台任务的内部应用。
struct PlashApplicationDefinition: Identifiable {
	let id: String
	let title: String
	let subtitle: String
	let systemImage: String
	let version: String
	let isEnabledByDefault: Bool
	let components: [PlashApplicationComponentDefinition]
	let backgroundTasks: [PlashApplicationBackgroundTaskDefinition]
	let settings: [PlashApplicationSettingDefinition]
}

/// 提供给内部应用运行时使用的受控上下文。
struct PlashApplicationContext {
	let applicationID: String
	let storage: PlashApplicationStorage
}

/// 每个内部应用独立的文件存储空间。
final class PlashApplicationStorage {
	let applicationID: String

	/// 应用存储根目录。
	var directoryURL: URL {
		baseDirectoryURL.appendingPathComponent(applicationID, isDirectory: true)
	}

	private var baseDirectoryURL: URL {
		let applicationSupportURL = try? FileManager.default.url(
			for: .applicationSupportDirectory,
			in: .userDomainMask,
			appropriateFor: nil,
			create: true
		)

		return (applicationSupportURL ?? FileManager.default.temporaryDirectory)
			.appendingPathComponent("Plash", isDirectory: true)
			.appendingPathComponent("Applications", isDirectory: true)
	}

	/// 创建指定应用的存储空间访问器。
	init(applicationID: String) {
		self.applicationID = applicationID
	}

	/// 读取指定键的 Codable 值。
	func value<Value: Decodable>(_ type: Value.Type, forKey key: String) throws -> Value? {
		let url = fileURL(forKey: key)

		guard FileManager.default.fileExists(atPath: url.path) else {
			return nil
		}

		let data = try Data(contentsOf: url)

		return try JSONDecoder().decode(Value.self, from: data)
	}

	/// 写入或删除指定键的 Codable 值。
	func set<Value: Encodable>(_ value: Value?, forKey key: String) throws {
		try FileManager.default.createDirectory(
			at: directoryURL,
			withIntermediateDirectories: true
		)

		let url = fileURL(forKey: key)

		guard let value else {
			try? FileManager.default.removeItem(at: url)
			return
		}

		let data = try JSONEncoder().encode(value)
		try data.write(to: url, options: .atomic)
	}

	/// 删除该应用的全部存储。
	func removeAll() throws {
		guard FileManager.default.fileExists(atPath: directoryURL.path) else {
			return
		}

		try FileManager.default.removeItem(at: directoryURL)
	}

	/// 估算该应用存储空间的字节数。
	func byteSize() -> Int {
		guard let enumerator = FileManager.default.enumerator(
			at: directoryURL,
			includingPropertiesForKeys: [
				.fileSizeKey,
				.isRegularFileKey
			]
		) else {
			return 0
		}

		return enumerator.compactMap { item -> Int? in
			guard let url = item as? URL else {
				return nil
			}

			let values = try? url.resourceValues(forKeys: [
				.fileSizeKey,
				.isRegularFileKey
			])

			guard values?.isRegularFile == true else {
				return nil
			}

			return values?.fileSize
		}
		.reduce(0, +)
	}

	private func fileURL(forKey key: String) -> URL {
		let allowedCharacters = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
		let fileName = key.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? key

		return directoryURL.appendingPathComponent("\(fileName).json")
	}
}

/// 内置应用注册中心。第一版只注册随 Plash 一起发布的应用。
@MainActor
final class PlashApplicationRegistry {
	static let shared = PlashApplicationRegistry()

	let applications: [PlashApplicationDefinition]

	/// 所有应用声明的桌面组件。
	var componentDefinitions: [PlashApplicationComponentDefinition] {
		applications.flatMap(\.components)
	}

	private init() {
		self.applications = Self.makeBuiltInApplications()
	}

	/// 查找应用定义。
	func application(withID id: String) -> PlashApplicationDefinition? {
		applications.first { $0.id == id }
	}

	/// 查找指定桌面组件类型对应的应用组件定义。
	func componentDefinition(for kind: DesktopComponentKind) -> PlashApplicationComponentDefinition? {
		componentDefinitions.first { $0.kind == kind }
	}

	private static func makeBuiltInApplications() -> [PlashApplicationDefinition] {
		[
			.init(
				id: "clock",
				title: "时钟",
				subtitle: "提供桌面时钟组件。",
				systemImage: "clock",
				version: "1.0",
				isEnabledByDefault: true,
				components: [
					.init(
						id: "clock.widget",
						applicationID: "clock",
						kind: .clock,
						defaultSize: .oneByOne
					)
				],
				backgroundTasks: [],
				settings: []
			),
			.init(
				id: "calendar",
				title: "日历",
				subtitle: "提供桌面日历组件。",
				systemImage: "calendar",
				version: "1.0",
				isEnabledByDefault: true,
				components: [
					.init(
						id: "calendar.widget",
						applicationID: "calendar",
						kind: .calendar,
						defaultSize: .twoByTwo
					)
				],
				backgroundTasks: [],
				settings: []
			),
			.init(
				id: "notes",
				title: "便签",
				subtitle: "提供桌面便签组件。",
				systemImage: "note.text",
				version: "1.0",
				isEnabledByDefault: true,
				components: [
					.init(
						id: "notes.widget",
						applicationID: "notes",
						kind: .note,
						defaultSize: .oneByTwo
					)
				],
				backgroundTasks: [],
				settings: [
					.init(
						id: "autosave",
						title: "自动保存",
						detail: "便签内容由桌面组件系统统一保存。"
					)
				]
			),
			.init(
				id: "websites",
				title: "网站",
				subtitle: "管理网站能力，并维护网站图标缓存。",
				systemImage: "globe",
				version: "1.0",
				isEnabledByDefault: true,
				components: [],
				backgroundTasks: [
					.init(
						id: "prewarm-thumbnails",
						title: "预热网站图标缓存",
						interval: 30 * 60
					) { context in
						let keys = WebsitesController.shared.all.map(\.thumbnailCacheKey)
						WebsitesController.shared.thumbnailCache.prewarmCacheFromDisk(for: keys)
						try context.storage.set(Date(), forKey: "lastThumbnailPrewarm")
					}
				],
				settings: [
					.init(
						id: "external-links",
						title: "外部链接",
						detail: "外部链接打开方式仍在全局设置中管理。"
					)
				]
			)
		]
	}
}

/// 管理内部应用状态、存储清理、组件启停和后台任务调度。
@MainActor
final class PlashApplicationController {
	static let shared = PlashApplicationController()

	private var backgroundTimers = [String: Timer]()

	private var registry: PlashApplicationRegistry { .shared }

	/// 当前可添加的组件定义。
	var enabledComponentDefinitions: [PlashApplicationComponentDefinition] {
		registry.componentDefinitions.filter { isEnabled(applicationID: $0.applicationID) }
	}

	private init() {}

	/// 启动应用框架，并为已启用应用安排后台任务。
	func start() {
		normalizeStoredStates()
		refreshBackgroundTasks()
	}

	/// 返回指定应用状态。
	func state(
		for application: PlashApplicationDefinition,
		in states: [PlashApplicationState]? = nil
	) -> PlashApplicationState {
		normalizedStates(from: states ?? Defaults[.plashApplicationStates])
			.first { $0.id == application.id } ?? defaultState(for: application)
	}

	/// 设置指定应用是否启用。
	func setEnabled(_ isEnabled: Bool, for application: PlashApplicationDefinition) {
		updateState(for: application.id) { state in
			state.isEnabled = isEnabled
			state.status = isEnabled ? .enabled : .disabled
			state.lastError = nil

			if !isEnabled {
				state.backgroundTaskStates = state.backgroundTaskStates.mapValues {
					var taskState = $0
					taskState.isRunning = false
					taskState.nextRunDate = nil
					return taskState
				}
			}
		}

		if isEnabled {
			refreshBackgroundTasks()
		} else {
			stopBackgroundTasks(for: application)
		}

		AppState.shared.syncDesktopComponentWindows()
	}

	/// 清除指定应用的独立存储空间。
	func clearStorage(for application: PlashApplicationDefinition) throws {
		try PlashApplicationStorage(applicationID: application.id).removeAll()

		updateState(for: application.id) { state in
			state.lastStorageResetDate = Date()
			state.lastError = nil
		}
	}

	/// 指定桌面组件对应的应用是否启用。
	func isComponentEnabled(_ component: DesktopComponent) -> Bool {
		guard let definition = registry.componentDefinition(for: component.kind) else {
			return true
		}

		return isEnabled(applicationID: definition.applicationID)
	}

	/// 指定应用是否启用。
	func isEnabled(applicationID: String) -> Bool {
		guard let application = registry.application(withID: applicationID) else {
			return true
		}

		return state(for: application).isEnabled
	}

	/// 重新安排所有已启用应用的后台任务。
	func refreshBackgroundTasks() {
		backgroundTimers.values.forEach { $0.invalidate() }
		backgroundTimers.removeAll()

		for application in registry.applications where state(for: application).isEnabled {
			startBackgroundTasks(for: application)
		}
	}

	private func startBackgroundTasks(for application: PlashApplicationDefinition) {
		guard !application.backgroundTasks.isEmpty else {
			return
		}

		updateState(for: application.id) { state in
			state.status = .running
		}

		for task in application.backgroundTasks {
			let key = timerKey(applicationID: application.id, taskID: task.id)
			backgroundTimers[key] = Timer.scheduledTimer(withTimeInterval: task.interval, repeats: true) { [weak self] _ in
				Task { @MainActor in
					await self?.runBackgroundTask(task, for: application)
				}
			}

			Task { @MainActor in
				await runBackgroundTask(task, for: application)
			}
		}
	}

	private func stopBackgroundTasks(for application: PlashApplicationDefinition) {
		for (key, timer) in backgroundTimers where key.hasPrefix("\(application.id)::") {
			timer.invalidate()
			backgroundTimers[key] = nil
		}
	}

	private func runBackgroundTask(
		_ task: PlashApplicationBackgroundTaskDefinition,
		for application: PlashApplicationDefinition
	) async {
		let currentState = state(for: application)

		guard
			currentState.isEnabled,
			currentState.backgroundTaskStates[task.id]?.isRunning != true
		else {
			return
		}

		updateState(for: application.id) { state in
			var taskState = state.backgroundTaskStates[task.id] ?? .init(id: task.id)
			taskState.isRunning = true
			taskState.nextRunDate = Date().addingTimeInterval(task.interval)
			taskState.lastError = nil
			state.backgroundTaskStates[task.id] = taskState
			state.status = .running
			state.lastError = nil
		}

		let context = PlashApplicationContext(
			applicationID: application.id,
			storage: .init(applicationID: application.id)
		)

		do {
			try await task.action(context)

			updateState(for: application.id) { state in
				var taskState = state.backgroundTaskStates[task.id] ?? .init(id: task.id)
				taskState.isRunning = false
				taskState.lastRunDate = Date()
				taskState.nextRunDate = Date().addingTimeInterval(task.interval)
				taskState.lastError = nil
				state.backgroundTaskStates[task.id] = taskState
				state.status = .running
				state.lastRunDate = taskState.lastRunDate
				state.lastError = nil
			}
		} catch {
			updateState(for: application.id) { state in
				var taskState = state.backgroundTaskStates[task.id] ?? .init(id: task.id)
				taskState.isRunning = false
				taskState.lastRunDate = Date()
				taskState.nextRunDate = Date().addingTimeInterval(task.interval)
				taskState.lastError = error.localizedDescription
				state.backgroundTaskStates[task.id] = taskState
				state.status = .failed
				state.lastRunDate = taskState.lastRunDate
				state.lastError = error.localizedDescription
			}
		}
	}

	private func normalizeStoredStates() {
		Defaults[.plashApplicationStates] = normalizedStates(from: Defaults[.plashApplicationStates])
	}

	private func normalizedStates(from states: [PlashApplicationState]) -> [PlashApplicationState] {
		let storedStates = Dictionary(uniqueKeysWithValues: states.map { ($0.id, $0) })

		return registry.applications.map { application in
			var state = storedStates[application.id] ?? defaultState(for: application)
			state.backgroundTaskStates = normalizedTaskStates(for: application, currentStates: state.backgroundTaskStates)

			if !state.isEnabled {
				state.status = .disabled
			}

			return state
		}
	}

	private func normalizedTaskStates(
		for application: PlashApplicationDefinition,
		currentStates: [String: PlashApplicationBackgroundTaskState]
	) -> [String: PlashApplicationBackgroundTaskState] {
		Dictionary(
			uniqueKeysWithValues: application.backgroundTasks.map { task in
				(task.id, currentStates[task.id] ?? .init(id: task.id))
			}
		)
	}

	private func defaultState(for application: PlashApplicationDefinition) -> PlashApplicationState {
		.init(
			id: application.id,
			isEnabled: application.isEnabledByDefault,
			status: application.isEnabledByDefault ? .enabled : .disabled,
			lastRunDate: nil,
			lastStorageResetDate: nil,
			lastError: nil,
			backgroundTaskStates: normalizedTaskStates(for: application, currentStates: [:])
		)
	}

	private func updateState(for applicationID: String, update: (inout PlashApplicationState) -> Void) {
		var states = normalizedStates(from: Defaults[.plashApplicationStates])

		guard let index = states.firstIndex(where: { $0.id == applicationID }) else {
			return
		}

		update(&states[index])
		Defaults[.plashApplicationStates] = states
	}

	private func timerKey(applicationID: String, taskID: String) -> String {
		"\(applicationID)::\(taskID)"
	}
}
