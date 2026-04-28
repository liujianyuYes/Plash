import Cocoa
import SwiftUI

extension NSPasteboard.PasteboardType {
	/// 设置页组件拖到桌面时使用的自定义拖拽类型。
	static let desktopComponent = Self(DesktopComponentDragPayload.typeIdentifier)
}

/// 管理桌面组件的增删改和持久化。
@MainActor
final class DesktopComponentsController {
	static let shared = DesktopComponentsController()

	private init() {}

	/// 返回指定 ID 的当前组件。
	func component(withID id: DesktopComponent.ID) -> DesktopComponent? {
		Defaults[.desktopComponents].first { $0.id == id }
	}

	/// 新增一个指定类型的组件。
	func add(_ kind: DesktopComponentKind) {
		add(kind, at: defaultPosition(forComponentCount: Defaults[.desktopComponents].count))
	}

	/// 在指定槽位新增一个组件。
	func add(_ kind: DesktopComponentKind, at position: DesktopComponentPosition) {
		var components = Defaults[.desktopComponents]
		let component = DesktopComponent(
			kind: kind,
			size: defaultSize(for: kind),
			position: position,
			noteText: kind == .note ? "新便签" : ""
		)

		components.append(component)
		Defaults[.desktopComponents] = components
	}

	/// 按屏幕坐标自动匹配显示器并放置拖来的组件。
	@discardableResult
	func drop(_ dragItem: DesktopComponentDragItem, at screenPoint: CGPoint) -> Bool {
		guard let screen = NSScreen.screens.first(where: { $0.frame.contains(screenPoint) }) ?? .primary else {
			return false
		}

		let screenFrame = Defaults[.extendPlashBelowMenuBar] ? screen.frame : screen.frameWithoutStatusBar
		guard screenFrame.contains(screenPoint) else {
			return false
		}

		drop(dragItem, at: screenPoint, in: screenFrame)

		return true
	}

	/// 把设置页拖来的组件放到指定屏幕坐标。
	func drop(_ dragItem: DesktopComponentDragItem, at screenPoint: CGPoint, in screenFrame: CGRect) {
		switch dragItem {
		case .new(let kind):
			let size = defaultSize(for: kind)
			let position = DesktopComponentGrid.position(centeredAt: screenPoint, size: size, in: screenFrame)
			add(kind, at: position)
		case .existing(let id):
			guard var component = component(withID: id) else {
				return
			}

			component.position = DesktopComponentGrid.position(centeredAt: screenPoint, size: component.size, in: screenFrame)
			update(component)
		}
	}

	/// 删除指定组件。
	func remove(_ component: DesktopComponent) {
		var components = Defaults[.desktopComponents]
		components.removeAll { $0.id == component.id }
		Defaults[.desktopComponents] = components
	}

	/// 更新指定组件。
	func update(_ component: DesktopComponent) {
		var components = Defaults[.desktopComponents]

		guard let index = components.firstIndex(where: { $0.id == component.id }) else {
			return
		}

		guard components[index] != component else {
			return
		}

		components[index] = component
		Defaults[.desktopComponents] = components
	}

	/// 更新组件占用尺寸。
	func updateSize(of component: DesktopComponent, to size: DesktopComponentSize) {
		var component = component
		component.size = size
		update(component)
	}

	/// 更新组件网格位置。
	func updatePosition(
		of component: DesktopComponent,
		to position: DesktopComponentPosition,
		in screenFrame: CGRect? = nil
	) {
		var component = component
		component.position = if let screenFrame {
			DesktopComponentGrid.clamped(position, size: component.size, in: screenFrame)
		} else {
			.init(
				column: max(0, position.column),
				row: max(0, position.row)
			)
		}
		update(component)
	}

	/// 更新便签内容。
	func updateNoteText(of component: DesktopComponent, to text: String) {
		var component = self.component(withID: component.id) ?? component
		component.noteText = text
		update(component)
	}

	/// 组件类型默认尺寸。
	func defaultSize(for kind: DesktopComponentKind) -> DesktopComponentSize {
		if let componentDefinition = PlashApplicationRegistry.shared.componentDefinition(for: kind) {
			return componentDefinition.defaultSize
		}

		switch kind {
		case .clock:
			return .oneByOne
		case .calendar:
			return .twoByTwo
		case .note:
			return .oneByTwo
		}
	}

	/// 指定组件所属应用当前是否启用。
	func isComponentAvailable(_ component: DesktopComponent) -> Bool {
		PlashApplicationController.shared.isComponentEnabled(component)
	}

	/// 按当前数量生成默认落点。
	private func defaultPosition(forComponentCount count: Int) -> DesktopComponentPosition {
		.init(
			column: (count % 3) * 2,
			row: (count / 3) * 2
		)
	}
}

/// 桌面上的单个组件窗口。
final class DesktopComponentWindow: NSWindow {
	override var canBecomeKey: Bool { true }
	override var canBecomeMain: Bool { false }

	private var component: DesktopComponent
	private var cancellables = Set<AnyCancellable>()
	private var dragStartFrame: NSRect?
	private var dragMouseOffset = CGSize.zero

	var targetDisplay: Display?

	/// 创建一个只覆盖组件槽位区域的透明窗口。
	init(component: DesktopComponent, display: Display) {
		self.component = component

		super.init(
			contentRect: .zero,
			styleMask: [
				.borderless
			],
			backing: .buffered,
			defer: false
		)

		self.targetDisplay = display
		self.isOpaque = false
		self.backgroundColor = .clear
		self.hasShadow = false
		self.isMovable = true
		self.isRestorable = false
		self.canHide = false
		self.displaysWhenScreenProfileChanges = true
		self.collectionBehavior = [
			.stationary,
			.ignoresCycle,
			.fullScreenNone
		]

		refreshLevel(isBrowsingMode: Defaults[.isBrowsingMode])
		disableSnapshotRestoration()
		refreshContent()
		setComponentFrame()

		NSScreen.publisher
			.sink { [weak self] in
				self?.setComponentFrame()
			}
			.store(in: &cancellables)

		Defaults.publisher(.extendPlashBelowMenuBar)
			.sink { [weak self] _ in
				self?.setComponentFrame()
			}
			.store(in: &cancellables)
	}

	/// 刷新组件数据、目标显示器和位置。
	func update(component: DesktopComponent, display: Display) {
		let oldComponent = self.component
		let shouldRefreshContent = oldComponent.kind != component.kind || oldComponent.size != component.size
		let shouldUpdateFrame = targetDisplay?.id != display.id || oldComponent.size != component.size || oldComponent.position != component.position
		self.component = component
		self.targetDisplay = display

		if shouldRefreshContent {
			refreshContent()
		}

		if shouldUpdateFrame && dragStartFrame == nil {
			setComponentFrame()
		}
	}

	/// 根据浏览模式刷新窗口层级。
	func refreshLevel(isBrowsingMode: Bool) {
		if isBrowsingMode {
			level = Defaults[.bringBrowsingModeToFront] ? .floating + 1 : .desktopIcon + 2
		} else {
			level = .desktopIcon
		}
	}

	/// 显示或隐藏组件窗口。
	func setComponentVisible(_ isVisible: Bool) {
		if isVisible {
			if !self.isVisible {
				orderFrontRegardless()
			}
		} else if self.isVisible {
			orderOut(nil)
		}
	}

	/// 开始拖动组件窗口。
	func beginDrag() {
		dragStartFrame = frame
		let mouseLocation = NSEvent.mouseLocation
		dragMouseOffset = .init(
			width: mouseLocation.x - frame.minX,
			height: mouseLocation.y - frame.minY
		)
	}

	/// 拖动中按全局鼠标位置直接移动窗口，让组件紧跟鼠标。
	func drag(to mouseLocation: NSPoint) {
		if dragStartFrame == nil {
			beginDrag()
		}

		guard
			let dragStartFrame,
			currentScreenFrame != .zero
		else {
			return
		}

		let screenFrame = currentScreenFrame
		let metrics = DesktopComponentGrid.metrics(in: screenFrame)
		let minX = metrics.origin.x
		let maxX = max(minX, metrics.origin.x + metrics.gridSize.width - dragStartFrame.width)
		let minY = metrics.origin.y - metrics.gridSize.height
		let maxY = max(minY, metrics.origin.y - dragStartFrame.height)
		let origin = NSPoint(
			x: min(max(mouseLocation.x - dragMouseOffset.width, minX), maxX),
			y: min(max(mouseLocation.y - dragMouseOffset.height, minY), maxY)
		)

		setFrameOrigin(origin)
	}

	/// 结束拖动后吸附到最近槽位，并只保存一次最终位置。
	func endDrag() {
		guard dragStartFrame != nil else {
			return
		}

		let position = gridPosition(for: frame)
		dragStartFrame = nil
		dragMouseOffset = .zero

		var updatedComponent = DesktopComponentsController.shared.component(withID: component.id) ?? component
		updatedComponent.position = position
		component = updatedComponent
		setComponentFrame()
		DesktopComponentsController.shared.update(updatedComponent)
	}

	/// 更新 SwiftUI 组件内容。
	private func refreshContent() {
		let hostingView = NSHostingView(
			rootView: DesktopComponentView(
				component: component,
				isEditable: true,
				onBeginDrag: { [weak self] in
					self?.beginDrag()
				},
				onDrag: { [weak self] mouseLocation in
					self?.drag(to: mouseLocation)
				},
				onEndDrag: { [weak self] in
					self?.endDrag()
				}
			)
		)
		hostingView.wantsLayer = true
		hostingView.layer?.isOpaque = false
		hostingView.layer?.backgroundColor = NSColor.clear.cgColor
		contentView = hostingView
	}

	/// 计算当前可用屏幕区域。
	private var currentScreenFrame: CGRect {
		guard let screen = targetDisplay?.screen ?? .primary else {
			return .zero
		}

		return Defaults[.extendPlashBelowMenuBar] ? screen.frame : screen.frameWithoutStatusBar
	}

	/// 根据组件槽位设置窗口位置。
	private func setComponentFrame() {
		let screenFrame = currentScreenFrame
		guard screenFrame != .zero else {
			return
		}

		let metrics = DesktopComponentGrid.metrics(in: screenFrame)
		let size = DesktopComponentGrid.pixelSize(for: component.size, metrics: metrics)
		let position = DesktopComponentGrid.clamped(
			component.position,
			size: component.size,
			in: screenFrame
		)
		let frame = NSRect(
			x: metrics.origin.x + (Double(position.column) * metrics.pitch),
			y: metrics.origin.y - size.height - (Double(position.row) * metrics.pitch),
			width: size.width,
			height: size.height
		)

		setFrame(frame, display: true, animate: false)
	}

	/// 将当前窗口位置转换为最近的组件槽位。
	private func gridPosition(for frame: CGRect) -> DesktopComponentPosition {
		let screenFrame = currentScreenFrame
		let metrics = DesktopComponentGrid.metrics(in: screenFrame)
		let column = Int(((frame.minX - metrics.origin.x) / metrics.pitch).rounded())
		let row = Int(((metrics.origin.y - frame.height - frame.minY) / metrics.pitch).rounded())

		return DesktopComponentGrid.clamped(
			.init(column: column, row: row),
			size: component.size,
			in: screenFrame
		)
	}
}

/// 桌面组件窗口里的 SwiftUI 内容，也用于设置页组件库预览。
struct DesktopComponentView: View {
	@Default(.useLiquidGlassComponentBackground) private var useLiquidGlassComponentBackground

	let component: DesktopComponent
	var isEditable = true
	var onBeginDrag: (() -> Void)?
	var onDrag: ((NSPoint) -> Void)?
	var onEndDrag: (() -> Void)?

	/// 组件卡片内容。
	@ViewBuilder
	var body: some View {
		if isEditable {
			componentBody
				.contextMenu {
					sizeMenu
					Button("删除", role: .destructive) {
						DesktopComponentsController.shared.remove(component)
					}
				}
		} else {
			componentBody
		}
	}

	/// 组件卡片主体。
	private var componentBody: some View {
		VStack(alignment: .leading, spacing: 0) {
			header
			Divider()
				.opacity(0.32)
			componentContent
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.background {
			componentBackground
		}
		.clipShape(componentShape)
		.overlay {
			componentShape
				.stroke(.white.opacity(useLiquidGlassComponentBackground ? 0.42 : 0.28), lineWidth: 1)
		}
		.shadow(color: .black.opacity(useLiquidGlassComponentBackground ? 0.18 : 0.08), radius: useLiquidGlassComponentBackground ? 24 : 10, y: 8)
	}

	/// 组件卡片外形。
	private var componentShape: RoundedRectangle {
		RoundedRectangle(cornerRadius: 22, style: .continuous)
	}

	/// 组件背景材质。
	@ViewBuilder
	private var componentBackground: some View {
		if useLiquidGlassComponentBackground {
			componentShape
				.fill(.ultraThinMaterial)
			componentShape
				.fill(
					LinearGradient(
						colors: [
							.white.opacity(0.32),
							.white.opacity(0.08),
							.black.opacity(0.08)
						],
						startPoint: .topLeading,
						endPoint: .bottomTrailing
					)
				)
			componentShape
				.stroke(.white.opacity(0.18), lineWidth: 1)
				.blur(radius: 0.4)
		} else {
			componentShape
				.fill(.regularMaterial)
		}
	}

	/// 可拖动的组件标题栏。
	private var header: some View {
		HStack(spacing: 8) {
			Image(systemName: component.kind.systemImage)
				.symbolRenderingMode(.hierarchical)
			Text(component.title)
				.font(.caption.weight(.semibold))
			Spacer()
			Text(component.size.title)
				.font(.caption2.monospacedDigit())
				.foregroundStyle(.secondary)
			Image(systemName: "move.3d")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 9)
		.contentShape(.rect)
		.overlay {
			if let onBeginDrag, let onDrag, let onEndDrag {
				DesktopComponentDragHandle(
					onBeginDrag: onBeginDrag,
					onDrag: onDrag,
					onEndDrag: onEndDrag
				)
			}
		}
		.help("拖动以移动组件")
	}

	/// 组件主体内容。
	@ViewBuilder
	private var componentContent: some View {
		switch component.kind {
		case .clock:
			ClockComponentView(size: component.size)
		case .calendar:
			CalendarComponentView(size: component.size)
		case .note:
			NoteComponentView(component: component, isEditable: isEditable)
		}
	}

	/// 右键菜单中的尺寸切换。
	private var sizeMenu: some View {
		Menu("尺寸") {
			ForEach(DesktopComponentSize.allCases) { size in
				Button(size.title) {
					DesktopComponentsController.shared.updateSize(of: component, to: size)
				}
			}
		}
	}
}

/// 覆盖在组件标题栏上的 AppKit 拖动层。
private struct DesktopComponentDragHandle: NSViewRepresentable {
	let onBeginDrag: () -> Void
	let onDrag: (NSPoint) -> Void
	let onEndDrag: () -> Void

	func makeNSView(context: Context) -> DragHandleView {
		let view = DragHandleView()
		view.onBeginDrag = onBeginDrag
		view.onDrag = onDrag
		view.onEndDrag = onEndDrag
		return view
	}

	func updateNSView(_ nsView: DragHandleView, context: Context) {
		nsView.onBeginDrag = onBeginDrag
		nsView.onDrag = onDrag
		nsView.onEndDrag = onEndDrag
	}

	final class DragHandleView: NSView {
		var onBeginDrag: (() -> Void)?
		var onDrag: ((NSPoint) -> Void)?
		var onEndDrag: (() -> Void)?

		override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

		override func mouseDown(with event: NSEvent) {
			onBeginDrag?()
		}

		override func mouseDragged(with event: NSEvent) {
			onDrag?(NSEvent.mouseLocation)
		}

		override func mouseUp(with event: NSEvent) {
			onEndDrag?()
		}
	}
}

/// 时钟组件。
private struct ClockComponentView: View {
	let size: DesktopComponentSize

	/// 当前时间。
	var body: some View {
		TimelineView(.periodic(from: .now, by: 1)) { context in
			let date = context.date
			let isCompactHeight = size.heightSlots == 1

			VStack(spacing: isCompactHeight ? 4 : 10) {
				Text(date, format: .dateTime.hour().minute())
					.font(.system(size: isCompactHeight ? 34 : 62, weight: .semibold, design: .rounded))
					.monospacedDigit()
					.minimumScaleFactor(0.7)
				Text(date, format: .dateTime.weekday(.wide).month().day())
					.font(isCompactHeight ? .caption : .title3.weight(.medium))
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.padding(14)
		}
	}
}

/// 日历组件。
private struct CalendarComponentView: View {
	let size: DesktopComponentSize

	private let calendar = Calendar.current

	/// 当前月份日历。
	var body: some View {
		let today = Date()
		let days = daysInVisibleMonth(for: today)
		let isCompactHeight = size.heightSlots == 1

		VStack(alignment: .leading, spacing: isCompactHeight ? 6 : 12) {
			Text(today, format: .dateTime.year().month(.wide))
				.font(isCompactHeight ? .caption.weight(.semibold) : .title2.weight(.semibold))
				.lineLimit(1)
			LazyVGrid(
				columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
				spacing: isCompactHeight ? 3 : 8
			) {
				ForEach(calendar.shortStandaloneWeekdaySymbols, id: \.self) { weekday in
					Text(String(weekday.prefix(1)))
						.font(.caption2.weight(.medium))
						.foregroundStyle(.secondary)
				}

				ForEach(Array(days.enumerated()), id: \.offset) { _, date in
					if let date {
						dayCell(date, isToday: calendar.isDateInToday(date))
					} else {
						Color.clear
							.frame(height: 18)
					}
				}
			}
		}
		.padding(isCompactHeight ? 10 : 18)
	}

	/// 单个日期单元格。
	private func dayCell(_ date: Date, isToday: Bool) -> some View {
		let isCompactHeight = size.heightSlots == 1

		return Text(date, format: .dateTime.day())
			.font(isCompactHeight ? .caption2.monospacedDigit() : .callout.monospacedDigit())
			.frame(maxWidth: .infinity, minHeight: isCompactHeight ? 14 : 24)
			.background {
				if isToday {
					Circle()
						.fill(.tint)
				}
			}
			.foregroundStyle(isToday ? .white : .primary)
	}

	/// 生成当前月需要显示的日期和占位。
	private func daysInVisibleMonth(for date: Date) -> [Date?] {
		guard
			let monthInterval = calendar.dateInterval(of: .month, for: date),
			let dayRange = calendar.range(of: .day, in: .month, for: date)
		else {
			return []
		}

		let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
		let leadingEmptyDays = (firstWeekday - calendar.firstWeekday + 7) % 7
		let dates = dayRange.compactMap { day -> Date? in
			calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start)
		}

		return Array(repeating: nil, count: leadingEmptyDays) + dates
	}
}

/// 便签组件。
private struct NoteComponentView: View {
	let component: DesktopComponent
	let isEditable: Bool

	/// 可编辑便签文本。
	var body: some View {
		if isEditable {
			TextEditor(
				text: Binding(
					get: {
						DesktopComponentsController.shared.component(withID: component.id)?.noteText ?? component.noteText
					},
					set: {
						DesktopComponentsController.shared.updateNoteText(of: component, to: $0)
					}
				)
			)
			.font(noteFont)
			.scrollContentBackground(.hidden)
			.padding(.horizontal, 8)
			.padding(.vertical, 6)
		} else {
			Text(component.noteText.isEmpty ? "新便签" : component.noteText)
				.font(noteFont)
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
				.padding(.horizontal, 14)
				.padding(.vertical, 12)
		}
	}

	private var noteFont: Font {
		.system(size: component.size.heightSlots == 1 ? 13 : 16, weight: .regular, design: .rounded)
	}
}
