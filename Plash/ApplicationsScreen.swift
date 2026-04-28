import SwiftUI

/// 应用管理页面，展示内置应用及其状态、组件、后台任务和独立存储。
struct ApplicationsScreen: View {
	@Default(.plashApplicationStates) private var applicationStates
	@State private var selectedApplicationID: String?
	@State private var storageError: String?

	private var applications: [PlashApplicationDefinition] {
		PlashApplicationRegistry.shared.applications
	}

	private var selectedApplication: PlashApplicationDefinition? {
		if let selectedApplicationID {
			return applications.first { $0.id == selectedApplicationID }
		}

		return applications.first
	}

	/// 应用列表和详情区域。
	var body: some View {
		HStack(spacing: 0) {
			applicationList
				.frame(width: 220)

			Divider()

			detail
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.frame(maxWidth: .infinity, minHeight: 540, maxHeight: .infinity)
		.onAppear {
			PlashApplicationController.shared.start()

			if selectedApplicationID == nil {
				selectedApplicationID = applications.first?.id
			}
		}
	}

	private var applicationList: some View {
		List(selection: $selectedApplicationID) {
			ForEach(applications) { application in
				ApplicationRow(
					application: application,
					state: state(for: application),
					isEnabled: enabledBinding(for: application)
				)
				.tag(application.id)
			}
		}
		.listStyle(.sidebar)
	}

	@ViewBuilder
	private var detail: some View {
		if let selectedApplication {
			ApplicationDetailView(
				application: selectedApplication,
				state: state(for: selectedApplication),
				isEnabled: enabledBinding(for: selectedApplication),
				storageError: $storageError
			)
		} else {
			ContentUnavailableView("没有应用", systemImage: "app")
		}
	}

	private func state(for application: PlashApplicationDefinition) -> PlashApplicationState {
		PlashApplicationController.shared.state(for: application, in: applicationStates)
	}

	private func enabledBinding(for application: PlashApplicationDefinition) -> Binding<Bool> {
		.init {
			state(for: application).isEnabled
		} set: {
			PlashApplicationController.shared.setEnabled($0, for: application)
		}
	}
}

/// 应用列表中的单行。
private struct ApplicationRow: View {
	let application: PlashApplicationDefinition
	let state: PlashApplicationState
	@Binding var isEnabled: Bool

	/// 应用图标、名称、状态和启用开关。
	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: application.systemImage)
				.symbolRenderingMode(.hierarchical)
				.font(.title3)
				.frame(width: 26)

			VStack(alignment: .leading, spacing: 3) {
				Text(application.title)
					.font(.headline)
					.lineLimit(1)
				Text(application.subtitle)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(2)
				ApplicationStatusBadge(status: state.status)
			}

			Spacer(minLength: 8)

			Toggle("", isOn: $isEnabled)
				.labelsHidden()
				.toggleStyle(.switch)
		}
		.padding(.vertical, 8)
	}
}

/// 应用详情区域。
private struct ApplicationDetailView: View {
	let application: PlashApplicationDefinition
	let state: PlashApplicationState
	@Binding var isEnabled: Bool
	@Binding var storageError: String?

	/// 应用的状态、能力、后台任务和存储管理。
	var body: some View {
		Form {
			Section {
				HStack(alignment: .top, spacing: 14) {
					Image(systemName: application.systemImage)
						.symbolRenderingMode(.hierarchical)
						.font(.system(size: 34))
						.frame(width: 44, height: 44)

					VStack(alignment: .leading, spacing: 6) {
						HStack {
							Text(application.title)
								.font(.title3.weight(.semibold))
							ApplicationStatusBadge(status: state.status)
						}

						Text(application.subtitle)
							.foregroundStyle(.secondary)
						Text("版本 \(application.version)")
							.font(.caption)
							.foregroundStyle(.tertiary)
					}

					Spacer()

					Toggle("启用", isOn: $isEnabled)
						.toggleStyle(.switch)
				}
				.padding(.vertical, 6)
			}

			Section("能力") {
				ApplicationMetricRow(title: "组件", value: "\(application.components.count)")
				ApplicationMetricRow(title: "后台任务", value: "\(application.backgroundTasks.count)")
				ApplicationMetricRow(title: "存储", value: storageSizeText)
			}

			if !application.components.isEmpty {
				Section("组件") {
					ForEach(application.components) { component in
						LabeledContent {
							Text(component.defaultSize.title)
								.foregroundStyle(.secondary)
						} label: {
							Label(component.title, systemImage: component.systemImage)
						}
					}
				}
			}

			if !application.backgroundTasks.isEmpty {
				Section("后台任务") {
					ForEach(application.backgroundTasks) { task in
						BackgroundTaskRow(
							task: task,
							state: state.backgroundTaskStates[task.id]
						)
					}
				}
			}

			if !application.settings.isEmpty {
				Section("设置") {
					ForEach(application.settings) { setting in
						VStack(alignment: .leading, spacing: 4) {
							Text(setting.title)
							Text(setting.detail)
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						.padding(.vertical, 2)
					}
				}
			}

			Section("存储") {
				ApplicationMetricRow(title: "位置", value: storage.directoryURL.path)
				Button("清除应用数据", role: .destructive) {
					do {
						try PlashApplicationController.shared.clearStorage(for: application)
						storageError = nil
					} catch {
						storageError = error.localizedDescription
					}
				}

				if let storageError {
					Text(storageError)
						.font(.caption)
						.foregroundStyle(.red)
				}
			}
		}
		.formStyle(.grouped)
	}

	private var storage: PlashApplicationStorage {
		.init(applicationID: application.id)
	}

	private var storageSizeText: String {
		ByteCountFormatter.string(
			fromByteCount: Int64(storage.byteSize()),
			countStyle: .file
		)
	}
}

/// 后台任务状态行。
private struct BackgroundTaskRow: View {
	let task: PlashApplicationBackgroundTaskDefinition
	let state: PlashApplicationBackgroundTaskState?

	/// 任务名称、周期和最近运行状态。
	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack {
				Label(task.title, systemImage: state?.isRunning == true ? "arrow.triangle.2.circlepath" : "clock.arrow.circlepath")
				Spacer()
				Text(intervalText)
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
			}

			ApplicationMetricRow(title: "上次运行", value: formattedDate(state?.lastRunDate))
			ApplicationMetricRow(title: "下次运行", value: formattedDate(state?.nextRunDate))

			if let lastError = state?.lastError {
				Text(lastError)
					.font(.caption)
					.foregroundStyle(.red)
			}
		}
		.padding(.vertical, 3)
	}

	private var intervalText: String {
		let minutes = max(1, Int(task.interval / 60))

		if minutes >= 60, minutes.isMultiple(of: 60) {
			return "\(minutes / 60) 小时"
		}

		return "\(minutes) 分钟"
	}

	private func formattedDate(_ date: Date?) -> String {
		guard let date else {
			return "未运行"
		}

		return date.formatted(date: .abbreviated, time: .shortened)
	}
}

/// 名称和值形式的紧凑信息行。
private struct ApplicationMetricRow: View {
	let title: String
	let value: String

	/// 左侧标题，右侧值。
	var body: some View {
		LabeledContent(title) {
			Text(value)
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.truncationMode(.middle)
		}
	}
}

/// 应用状态胶囊。
private struct ApplicationStatusBadge: View {
	let status: PlashApplicationStatus

	/// 彩色状态标签。
	var body: some View {
		Text(status.title)
			.font(.caption2.weight(.medium))
			.foregroundStyle(color)
			.padding(.horizontal, 7)
			.padding(.vertical, 3)
			.background(color.opacity(0.12), in: Capsule())
	}

	private var color: Color {
		switch status {
		case .enabled:
			.secondary
		case .disabled:
			.gray
		case .running:
			.green
		case .failed:
			.red
		}
	}
}

#Preview {
	ApplicationsScreen()
}
