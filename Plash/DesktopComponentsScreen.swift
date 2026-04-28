import Cocoa
import SwiftUI

/// 组件管理页面，负责展示组件库并把组件拖放到桌面。
struct DesktopComponentsScreen: View {
	@Default(.plashApplicationStates) private var applicationStates
	@Default(.useLiquidGlassComponentBackground) private var useLiquidGlassComponentBackground

	/// 组件库和外观设置。
	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 24) {
				appearanceControls
				componentLibrary
			}
			.padding(20)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.frame(maxWidth: .infinity, minHeight: 540, maxHeight: .infinity)
	}

	/// 桌面组件外观设置。
	private var appearanceControls: some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionHeader(title: "外观", systemImage: "paintbrush")

			Toggle("液态玻璃背景", isOn: $useLiquidGlassComponentBackground)
				.toggleStyle(.switch)
				.padding(12)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
				.overlay {
					RoundedRectangle(cornerRadius: 16, style: .continuous)
						.stroke(.quaternary, lineWidth: 1)
				}
		}
	}

	/// 可添加到桌面的组件库。
	private var componentLibrary: some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionHeader(title: "组件库", systemImage: "square.grid.2x2")

			if componentDefinitions.isEmpty {
				ContentUnavailableView("没有可用组件", systemImage: "square.grid.2x2")
					.frame(maxWidth: .infinity, minHeight: 220)
			} else {
				PackedDesktopComponentLibraryLayout(metrics: componentMetrics) {
					ForEach(componentDefinitions) { componentDefinition in
						DesktopComponentLibraryItem(componentDefinition: componentDefinition, metrics: componentMetrics)
							.layoutValue(
								key: DesktopComponentLibraryItemSizeKey.self,
								value: componentDefinition.defaultSize
							)
					}
				}
			}
		}
	}

	private var componentDefinitions: [PlashApplicationComponentDefinition] {
		PlashApplicationRegistry.shared.componentDefinitions.filter { componentDefinition in
			guard let application = PlashApplicationRegistry.shared.application(withID: componentDefinition.applicationID) else {
				return true
			}

			return PlashApplicationController.shared.state(for: application, in: applicationStates).isEnabled
		}
	}

	private var componentMetrics: DesktopComponentGrid.Metrics {
		DesktopComponentGrid.metrics(in: screenFrame)
	}

	private var screenFrame: CGRect {
		guard let screen = NSScreen.primary ?? NSScreen.screens.first else {
			return .init(x: 0, y: 0, width: 1440, height: 900)
		}

		return Defaults[.extendPlashBelowMenuBar] ? screen.frame : screen.frameWithoutStatusBar
	}
}

/// 页面分区标题。
private struct SectionHeader: View {
	let title: String
	let systemImage: String

	var body: some View {
		Label(title, systemImage: systemImage)
			.font(.headline)
			.foregroundStyle(.primary)
	}
}

/// 组件库中的单个可拖拽组件，尺寸和桌面窗口保持一致。
private struct DesktopComponentLibraryItem: View {
	let componentDefinition: PlashApplicationComponentDefinition
	let metrics: DesktopComponentGrid.Metrics

	private var component: DesktopComponent {
		DesktopComponent(
			kind: componentDefinition.kind,
			size: componentDefinition.defaultSize,
			position: .init(column: 0, row: 0),
			noteText: componentDefinition.kind == .note ? "新便签" : ""
		)
	}

	private var componentSize: CGSize {
		DesktopComponentGrid.pixelSize(for: component.size, metrics: metrics)
	}

	var body: some View {
		DesktopComponentView(
			component: component,
			isEditable: false
		)
			.frame(width: componentSize.width, height: componentSize.height)
			.overlay {
				DesktopComponentDragSource(
					payload: DesktopComponentDragPayload.encodeNewComponent(componentDefinition.kind),
					component: component
				)
			}
	}
}

/// 组件库使用的占格尺寸。
private struct DesktopComponentLibraryItemSizeKey: LayoutValueKey {
	static let defaultValue = DesktopComponentSize.oneByOne
}

/// 按桌面同一套槽位尺寸把组件紧凑装入设置页。
private struct PackedDesktopComponentLibraryLayout: Layout {
	let metrics: DesktopComponentGrid.Metrics

	func sizeThatFits(
		proposal: ProposedViewSize,
		subviews: Subviews,
		cache: inout ()
	) -> CGSize {
		let packing = pack(subviews: subviews, availableWidth: proposal.width)

		return .init(
			width: max(packing.gridWidth, proposal.width ?? 0),
			height: packing.gridHeight
		)
	}

	func placeSubviews(
		in bounds: CGRect,
		proposal: ProposedViewSize,
		subviews: Subviews,
		cache: inout ()
	) {
		let packing = pack(subviews: subviews, availableWidth: bounds.width)

		for placement in packing.placements {
			let size = DesktopComponentGrid.pixelSize(for: placement.size, metrics: metrics)
			let origin = CGPoint(
				x: bounds.minX + (Double(placement.column) * metrics.pitch),
				y: bounds.minY + (Double(placement.row) * metrics.pitch)
			)

			subviews[placement.index].place(
				at: origin,
				anchor: .topLeading,
				proposal: .init(width: size.width, height: size.height)
			)
		}
	}

	private func pack(subviews: Subviews, availableWidth: CGFloat?) -> PackingResult {
		let sizes = subviews.map { $0[DesktopComponentLibraryItemSizeKey.self] }
		let maxWidthSlots = sizes.map(\.widthSlots).max() ?? 1
		let proposedWidth = max(availableWidth ?? 0, metrics.slotLength)
		let proposedColumns = Int(((proposedWidth + metrics.spacing) / metrics.pitch).rounded(.down))
		let columns = max(maxWidthSlots, proposedColumns, 1)
		var occupied = Set<GridCell>()
		var placements = [PackedPlacement]()
		let sortedIndices = sizes.indices.sorted {
			let lhs = sizes[$0]
			let rhs = sizes[$1]
			let lhsArea = lhs.widthSlots * lhs.heightSlots
			let rhsArea = rhs.widthSlots * rhs.heightSlots

			if lhsArea != rhsArea {
				return lhsArea > rhsArea
			}

			if lhs.heightSlots != rhs.heightSlots {
				return lhs.heightSlots > rhs.heightSlots
			}

			if lhs.widthSlots != rhs.widthSlots {
				return lhs.widthSlots > rhs.widthSlots
			}

			return $0 < $1
		}

		for index in sortedIndices {
			let size = sizes[index]
			var row = 0

			while true {
				if let column = firstAvailableColumn(for: size, row: row, columns: columns, occupied: occupied) {
					occupy(size: size, column: column, row: row, in: &occupied)
					placements.append(
						.init(
							index: index,
							size: size,
							column: column,
							row: row
						)
					)
					break
				}

				row += 1
			}
		}

		let usedRows = max(1, placements.map { $0.row + $0.size.heightSlots }.max() ?? 1)
		let gridWidth = (Double(columns) * metrics.slotLength) + (Double(max(0, columns - 1)) * metrics.spacing)
		let gridHeight = (Double(usedRows) * metrics.slotLength) + (Double(max(0, usedRows - 1)) * metrics.spacing)

		return .init(
			placements: placements,
			gridWidth: gridWidth,
			gridHeight: gridHeight
		)
	}

	private func firstAvailableColumn(
		for size: DesktopComponentSize,
		row: Int,
		columns: Int,
		occupied: Set<GridCell>
	) -> Int? {
		let maxColumn = columns - size.widthSlots

		guard maxColumn >= 0 else {
			return nil
		}

		for column in 0...maxColumn where canPlace(size: size, column: column, row: row, occupied: occupied) {
			return column
		}

		return nil
	}

	private func canPlace(
		size: DesktopComponentSize,
		column: Int,
		row: Int,
		occupied: Set<GridCell>
	) -> Bool {
		for xOffset in 0..<size.widthSlots {
			for yOffset in 0..<size.heightSlots where occupied.contains(.init(column: column + xOffset, row: row + yOffset)) {
				return false
			}
		}

		return true
	}

	private func occupy(
		size: DesktopComponentSize,
		column: Int,
		row: Int,
		in occupied: inout Set<GridCell>
	) {
		for xOffset in 0..<size.widthSlots {
			for yOffset in 0..<size.heightSlots {
				occupied.insert(.init(column: column + xOffset, row: row + yOffset))
			}
		}
	}

	private struct GridCell: Hashable {
		let column: Int
		let row: Int
	}

	private struct PackedPlacement {
		let index: Int
		let size: DesktopComponentSize
		let column: Int
		let row: Int
	}

	private struct PackingResult {
		let placements: [PackedPlacement]
		let gridWidth: CGFloat
		let gridHeight: CGFloat
	}
}

/// 设置页组件卡片上的拖拽源。
private struct DesktopComponentDragSource: NSViewRepresentable {
	let payload: String
	let component: DesktopComponent

	func makeNSView(context: Context) -> DragSourceView {
		let view = DragSourceView()
		view.payload = payload
		view.component = component
		return view
	}

	func updateNSView(_ nsView: DragSourceView, context: Context) {
		nsView.payload = payload
		nsView.component = component
	}

	final class DragSourceView: NSView, NSDraggingSource {
		var payload = ""
		var component: DesktopComponent?
		private var mouseDownEvent: NSEvent?
		private var isDragging = false

		override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

		override func mouseDown(with event: NSEvent) {
			mouseDownEvent = event
			isDragging = false
		}

		override func mouseDragged(with event: NSEvent) {
			guard !isDragging else {
				return
			}

			isDragging = true
			AppState.shared.setDesktopComponentDropMode(true)

			let pasteboardItem = NSPasteboardItem()
			pasteboardItem.setString(payload, forType: .desktopComponent)

			let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
			draggingItem.setDraggingFrame(bounds, contents: dragImage())

			let session = beginDraggingSession(
				with: [
					draggingItem
				],
				event: mouseDownEvent ?? event,
				source: self
			)
			session.animatesToStartingPositionsOnCancelOrFail = false
		}

		override func mouseUp(with event: NSEvent) {
			mouseDownEvent = nil
		}

		func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
			.copy
		}

		func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
			if
				!operation.contains(.copy),
				!isOverVisibleAppWindow(screenPoint),
				let dragItem = DesktopComponentDragPayload.decode(payload)
			{
				DesktopComponentsController.shared.drop(dragItem, at: screenPoint)
			}

			mouseDownEvent = nil
			isDragging = false
			AppState.shared.setDesktopComponentDropMode(false)
		}

		private func isOverVisibleAppWindow(_ screenPoint: NSPoint) -> Bool {
			NSApp.windows.contains {
				$0.isVisible
					&& $0.level.rawValue >= NSWindow.Level.normal.rawValue
					&& $0.frame.contains(screenPoint)
			}
		}

		private func dragImage() -> NSImage {
			let imageSize = bounds.size.width > 12 && bounds.size.height > 12 ? bounds.size : .init(width: 160, height: 100)
			guard let component else {
				return fallbackDragImage(size: imageSize)
			}

			let hostingView = NSHostingView(
				rootView: DesktopComponentView(
					component: component,
					isEditable: false
				)
				.frame(width: imageSize.width, height: imageSize.height)
			)
			hostingView.frame = .init(origin: .zero, size: imageSize)
			hostingView.wantsLayer = true
			hostingView.layer?.isOpaque = false
			hostingView.layer?.backgroundColor = NSColor.clear.cgColor
			hostingView.layoutSubtreeIfNeeded()

			guard let representation = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
				return fallbackDragImage(size: imageSize)
			}

			hostingView.cacheDisplay(in: hostingView.bounds, to: representation)

			let image = NSImage(size: imageSize)
			image.addRepresentation(representation)

			return image
		}

		private func fallbackDragImage(size imageSize: CGSize) -> NSImage {
			let image = NSImage(size: imageSize)

			image.lockFocus()
			NSColor.windowBackgroundColor.withAlphaComponent(0.88).setFill()
			let path = NSBezierPath(roundedRect: .init(origin: .zero, size: imageSize), xRadius: 22, yRadius: 22)
			path.fill()
			NSColor.separatorColor.withAlphaComponent(0.32).setStroke()
			path.lineWidth = 1
			path.stroke()
			image.unlockFocus()

			return image
		}
	}
}

#Preview {
	DesktopComponentsScreen()
}
