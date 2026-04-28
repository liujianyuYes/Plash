import Foundation

/// 壁纸来源类型。
enum WallpaperSourceKind: String, CaseIterable, Codable, Identifiable, Sendable {
	case website
	case video
	case image

	/// 来源唯一标识。
	var id: Self { self }

	/// 面向用户的名称。
	var title: String {
		switch self {
		case .website:
			"网站"
		case .video:
			"视频"
		case .image:
			"图片"
		}
	}

	/// 来源图标。
	var systemImage: String {
		switch self {
		case .website:
			"globe"
		case .video:
			"play.rectangle"
		case .image:
			"photo"
		}
	}
}

/// 多显示器壁纸配置模式。
enum WallpaperDisplayMode: String, CaseIterable, Codable, Identifiable, Sendable {
	case sameOnAllDisplays
	case separatePerDisplay

	/// 模式唯一标识。
	var id: Self { self }

	/// 面向用户的名称。
	var title: String {
		switch self {
		case .sameOnAllDisplays:
			"所有显示器相同"
		case .separatePerDisplay:
			"每个显示器单独设置"
		}
	}
}

/// 媒体填充方式。
enum WallpaperFillMode: String, CaseIterable, Codable, Identifiable, Sendable {
	case fill
	case fit
	case stretch
	case center

	/// 模式唯一标识。
	var id: Self { self }

	/// 面向用户的名称。
	var title: String {
		switch self {
		case .fill:
			"填充"
		case .fit:
			"适应"
		case .stretch:
			"拉伸"
		case .center:
			"居中"
		}
	}
}

/// 视频壁纸设置。
struct WallpaperVideoSettings: Hashable, Codable, Sendable {
	var urls = [URL]()
	var selectedIndex = 0
	var shouldLoop = true
	var startsAutomatically = true
	var isMuted = true
	var showsControls = false
	var playbackRate = 1.0
	var fillMode = WallpaperFillMode.fill

	/// 当前选中的视频文件。
	var selectedURL: URL? {
		guard urls.indices.contains(selectedIndex) else {
			return urls.first
		}

		return urls[selectedIndex]
	}
}

/// 图片壁纸设置。
struct WallpaperImageSettings: Hashable, Codable, Sendable {
	var urls = [URL]()
	var selectedIndex = 0
	var isSlideshowEnabled = true
	var slideshowInterval = 300.0
	var isRandomOrder = false
	var usesBlurredBackground = false
	var fillMode = WallpaperFillMode.fill

	/// 当前选中的图片文件。
	var selectedURL: URL? {
		guard urls.indices.contains(selectedIndex) else {
			return urls.first
		}

		return urls[selectedIndex]
	}
}

/// 单个显示器或全局共享的壁纸配置。
struct WallpaperConfiguration: Hashable, Codable, Sendable {
	var sourceKind = WallpaperSourceKind.website
	var video = WallpaperVideoSettings()
	var image = WallpaperImageSettings()
}

/// 壁纸总配置，支持所有显示器相同或逐显示器覆盖。
struct WallpaperSettings: Hashable, Codable, Sendable, Defaults.Serializable {
	var displayMode = WallpaperDisplayMode.sameOnAllDisplays
	var sharedConfiguration = WallpaperConfiguration()
	var displayConfigurations = [Display.ID: WallpaperConfiguration]()

	/// 读取指定显示器当前应该使用的配置。
	func configuration(for display: Display) -> WallpaperConfiguration {
		guard displayMode == .separatePerDisplay else {
			return sharedConfiguration
		}

		return displayConfigurations[display.id] ?? sharedConfiguration
	}

	/// 写入指定显示器当前应该使用的配置。
	mutating func setConfiguration(_ configuration: WallpaperConfiguration, for display: Display?) {
		guard
			displayMode == .separatePerDisplay,
			let display
		else {
			sharedConfiguration = configuration
			return
		}

		displayConfigurations[display.id] = configuration
	}

	/// 当前目标显示器中是否存在网站来源。
	func usesWebsiteSource(for displays: [Display]) -> Bool {
		displays.contains {
			configuration(for: $0).sourceKind == .website
		}
	}
}
