import Foundation

/// 桌面组件类型。
enum DesktopComponentKind: String, CaseIterable, Codable, Identifiable, Sendable {
	case clock
	case calendar
	case note

	/// 类型唯一标识。
	var id: Self { self }

	/// 面向用户的名称。
	var title: String {
		switch self {
		case .clock:
			"时钟"
		case .calendar:
			"日历"
		case .note:
			"便签"
		}
	}

	/// 系统图标。
	var systemImage: String {
		switch self {
		case .clock:
			"clock"
		case .calendar:
			"calendar"
		case .note:
			"note.text"
		}
	}
}

/// 组件占用的槽位尺寸。
enum DesktopComponentSize: String, CaseIterable, Codable, Identifiable, Sendable {
	case oneByOne
	case oneByTwo
	case twoByTwo

	static let allCases: [Self] = [
		.oneByOne,
		.oneByTwo,
		.twoByTwo
	]

	/// 尺寸唯一标识。
	var id: Self { self }

	/// 占用的列数。
	var widthSlots: Int {
		switch self {
		case .oneByOne:
			1
		case .oneByTwo:
			2
		case .twoByTwo:
			2
		}
	}

	/// 占用的行数。
	var heightSlots: Int {
		switch self {
		case .oneByOne:
			1
		case .oneByTwo:
			1
		case .twoByTwo:
			2
		}
	}

	/// 面向用户的名称。
	var title: String {
		switch self {
		case .oneByOne:
			"1x1"
		case .oneByTwo:
			"1x2"
		case .twoByTwo:
			"2x2"
		}
	}

	init(from decoder: Decoder) throws {
		let rawValue = try decoder.singleValueContainer().decode(String.self)

		switch rawValue {
		case Self.oneByOne.rawValue:
			self = .oneByOne
		case Self.oneByTwo.rawValue:
			self = .oneByTwo
		case Self.twoByTwo.rawValue, "fourByFour":
			self = .twoByTwo
		default:
			throw DecodingError.dataCorrupted(
				.init(
					codingPath: decoder.codingPath,
					debugDescription: "Unknown desktop component size: \(rawValue)"
				)
			)
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(rawValue)
	}
}

/// 组件在桌面网格中的左上角槽位。
struct DesktopComponentPosition: Hashable, Codable, Sendable {
	var column: Int
	var row: Int
}

/// 用户添加到 Plash 桌面的一个组件。
struct DesktopComponent: Hashable, Codable, Identifiable, Sendable, Defaults.Serializable {
	let id: UUID
	var kind: DesktopComponentKind
	var size: DesktopComponentSize
	var position: DesktopComponentPosition
	var noteText: String

	/// 组件默认标题。
	var title: String { kind.title }

	/// 创建一个新组件。
	init(
		id: UUID = UUID(),
		kind: DesktopComponentKind,
		size: DesktopComponentSize,
		position: DesktopComponentPosition,
		noteText: String = ""
	) {
		self.id = id
		self.kind = kind
		self.size = size
		self.position = position
		self.noteText = noteText
	}
}

extension DesktopComponent {
	/// 首次启用组件系统时展示的默认组件。
	static let defaults = [
		DesktopComponent(
			id: UUID(uuidString: "6EA7A928-9F6B-44C7-A7C9-4533D98AA001")!,
			kind: .clock,
			size: .oneByOne,
			position: .init(column: 0, row: 0)
		),
		DesktopComponent(
			id: UUID(uuidString: "6EA7A928-9F6B-44C7-A7C9-4533D98AA002")!,
			kind: .calendar,
			size: .twoByTwo,
			position: .init(column: 1, row: 0)
		),
		DesktopComponent(
			id: UUID(uuidString: "6EA7A928-9F6B-44C7-A7C9-4533D98AA003")!,
			kind: .note,
			size: .twoByTwo,
			position: .init(column: 0, row: 2),
			noteText: "拖动标题栏移动组件。\n在“组件”页面可以添加、删除和调整大小。"
		)
	]
}

/// 桌面组件网格度量。
enum DesktopComponentGrid {
	static let preferredSlotLength = 140.0
	static let spacing = 12.0
	static let inset = 28.0

	/// 按屏幕可放区域计算出的真实网格。
	struct Metrics {
		let slotLength: Double
		let spacing: Double
		let inset: Double
		let placementArea: CGRect
		let columns: Int
		let rows: Int
		let origin: CGPoint
		let gridSize: CGSize

		/// 相邻槽位左上角之间的距离。
		var pitch: Double { slotLength + spacing }
	}

	/// 获取屏幕内真正允许摆放组件的区域。
	static func placementArea(in screenFrame: CGRect) -> CGRect {
		screenFrame.insetBy(dx: inset, dy: inset)
	}

	/// 获取当前屏幕可放组件区域对应的动态网格。
	static func metrics(in screenFrame: CGRect) -> Metrics {
		let placementArea = placementArea(in: screenFrame)
		let availableWidth = max(1, placementArea.width)
		let availableHeight = max(1, placementArea.height)
		let columns = max(1, Int(((availableWidth + spacing) / (preferredSlotLength + spacing)).rounded(.down)))
		let slotLength = (availableWidth - (Double(columns - 1) * spacing)) / Double(columns)
		let pitch = slotLength + spacing
		let rows = max(1, Int(((availableHeight + spacing) / pitch).rounded(.down)))
		let gridHeight = (Double(rows) * slotLength) + (Double(max(0, rows - 1)) * spacing)

		return .init(
			slotLength: slotLength,
			spacing: spacing,
			inset: inset,
			placementArea: placementArea,
			columns: columns,
			rows: rows,
			origin: .init(x: placementArea.minX, y: placementArea.maxY),
			gridSize: .init(width: availableWidth, height: gridHeight)
		)
	}

	/// 指定槽位尺寸对应的窗口像素尺寸。
	static func pixelSize(for size: DesktopComponentSize, in screenFrame: CGRect) -> CGSize {
		pixelSize(for: size, metrics: metrics(in: screenFrame))
	}

	/// 指定槽位尺寸对应的窗口像素尺寸。
	static func pixelSize(for size: DesktopComponentSize, metrics: Metrics) -> CGSize {
		let widthSlots = Double(size.widthSlots)
		let heightSlots = Double(size.heightSlots)
		let width = (widthSlots * metrics.slotLength) + ((widthSlots - 1) * metrics.spacing)
		let height = (heightSlots * metrics.slotLength) + ((heightSlots - 1) * metrics.spacing)

		return .init(width: width, height: height)
	}

	/// 按屏幕尺寸限制组件位置，避免拖出可见区域。
	static func clamped(
		_ position: DesktopComponentPosition,
		size: DesktopComponentSize,
		in screenFrame: CGRect
	) -> DesktopComponentPosition {
		let metrics = metrics(in: screenFrame)
		let maxColumn = max(0, metrics.columns - size.widthSlots)
		let maxRow = max(0, metrics.rows - size.heightSlots)

		return .init(
			column: min(max(position.column, 0), maxColumn),
			row: min(max(position.row, 0), maxRow)
		)
	}

	/// 将拖放位置换算为最近槽位，默认让组件中心对齐鼠标落点。
	static func position(
		centeredAt point: CGPoint,
		size: DesktopComponentSize,
		in screenFrame: CGRect
	) -> DesktopComponentPosition {
		let metrics = metrics(in: screenFrame)
		let pixelSize = pixelSize(for: size, metrics: metrics)
		let column = Int(((point.x - (pixelSize.width / 2) - metrics.origin.x) / metrics.pitch).rounded())
		let row = Int(((metrics.origin.y - (pixelSize.height / 2) - point.y) / metrics.pitch).rounded())

		return clamped(
			.init(column: column, row: row),
			size: size,
			in: screenFrame
		)
	}
}

/// 组件从设置页拖到桌面时传递的内容。
enum DesktopComponentDragPayload {
	static let typeIdentifier = "com.sindresorhus.PlashDev.desktop-component"

	/// 把新组件类型编码为拖拽字符串。
	static func encodeNewComponent(_ kind: DesktopComponentKind) -> String {
		"new:\(kind.rawValue)"
	}

	/// 把现有组件 ID 编码为拖拽字符串。
	static func encodeExistingComponent(_ id: DesktopComponent.ID) -> String {
		"existing:\(id.uuidString)"
	}

	/// 解析拖拽字符串。
	static func decode(_ payload: String) -> DesktopComponentDragItem? {
		if payload.hasPrefix("new:") {
			let rawKind = payload.removingPrefix("new:")
			guard let kind = DesktopComponentKind(rawValue: rawKind) else {
				return nil
			}

			return .new(kind)
		}

		if payload.hasPrefix("existing:") {
			let rawID = payload.removingPrefix("existing:")
			guard let id = UUID(uuidString: rawID) else {
				return nil
			}

			return .existing(id)
		}

		return nil
	}
}

/// 拖拽载荷解析后的组件来源。
enum DesktopComponentDragItem {
	case new(DesktopComponentKind)
	case existing(DesktopComponent.ID)
}
