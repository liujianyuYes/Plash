import Foundation

/// 用户保存的一个网站配置，包含展示 URL、标题和网页渲染定制项。
struct Website: Hashable, Codable, Identifiable, Sendable, Defaults.Serializable {
	let id: UUID
	var isCurrent: Bool
	var url: URL
	@DecodableDefault.EmptyString var title: String
	@DecodableDefault.Custom<InvertColors> var invertColors2
	var usePrintStyles: Bool
	var css = ""
	var javaScript = ""
	@DecodableDefault.False var allowSelfSignedCertificate

	var subtitle: String { url.humanString }

	var menuTitle: String { title.isEmpty ? subtitle : title }

	// The space is there to force `NSMenu` to display an empty line.
	var tooltip: String { "\(title)\n \n\(subtitle)".trimmed }

	/// 缩略图缓存键，本地目录按路径区分，远程网站按主机区分。
	var thumbnailCacheKey: String { url.isFileURL ? url.tildePath : (url.host ?? "") }

	/// 将当前网站设为正在显示的网站。
	@MainActor
	func makeCurrent() {
		WebsitesController.shared.current = self
	}

	/// 从网站列表中删除当前网站。
	@MainActor
	func remove() {
		WebsitesController.shared.remove(self)
	}
}

extension Website {
	/// 网站颜色反转策略，用于模拟深色模式或强制反色。
	enum InvertColors: String, CaseIterable, Codable {
		case never
		case always
		case darkMode

		/// 设置界面中显示的本地化标题。
		var title: String {
			switch self {
			case .never:
				"从不"
			case .always:
				"始终"
			case .darkMode:
				"深色模式时"
			}
		}
	}
}

extension Website.InvertColors: DecodableDefault.Source {
	/// 解码旧数据时使用的默认反色策略。
	static let defaultValue = never
}
