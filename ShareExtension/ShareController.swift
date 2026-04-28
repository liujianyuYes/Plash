import Cocoa

/// 分享扩展入口，把系统分享来的网页 URL 转换为 `plash:add` 命令。
final class ShareController: ExtensionController {
	/// 读取分享上下文中的第一个 URL，并请求主 App 添加为网站。
	override func run(_ context: NSExtensionContext) async throws -> [NSExtensionItem] {
		guard
			let url = try await (context.attachments.first { $0.hasItemConforming(to: .url) })?.loadTransferable(type: URL.self)
		else {
			context.cancel()
			return []
		}

		var components = URLComponents()
		components.scheme = "plash"
		components.path = "add"

		components.queryItems = [
			.init(name: "url", value: url.absoluteString)
		]

		NSWorkspace.shared.open(components.url!)

		return []
	}
}

extension NSItemProvider: @retroactive @unchecked Sendable {}
