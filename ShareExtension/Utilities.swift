import Cocoa
import UniformTypeIdentifiers
import CoreTransferable


extension Sequence where Element: Sequence {
	/// 将嵌套序列展开为一维数组。
	func flatten() -> [Element.Element] {
		flatMap(\.self)
	}
}


extension NSExtensionContext {
	/// 将扩展输入项安全转换为 `NSExtensionItem` 数组。
	var inputItemsTyped: [NSExtensionItem] { inputItems as! [NSExtensionItem] }

	/// 从扩展输入项中收集所有附件。
	var attachments: [NSItemProvider] {
		inputItemsTyped.compactMap(\.attachments).flatten()
	}
}


extension NSItemProvider {
	/// 用 async/await 形式加载 Transferable 内容。
	func loadTransferable<T: Transferable>(type transferableType: T.Type) async throws -> T {
		try await withCheckedThrowingContinuation { continuation in
			_ = loadTransferable(type: transferableType) {
				continuation.resume(with: $0)
			}
		}
	}
}


// Strongly-typed versions of some of the methods.
extension NSItemProvider {
	/// 判断附件是否包含指定 UTType。
	func hasItemConforming(to contentType: UTType) -> Bool {
		hasItemConformingToTypeIdentifier(contentType.identifier)
	}
}


extension NSError {
	/// 扩展主动取消时使用的标准 Cocoa 错误。
	static let userCancelled = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
}


extension NSExtensionContext {
	/// 使用标准用户取消错误结束扩展请求。
	func cancel() {
		cancelRequest(withError: NSError.userCancelled)
	}
}


/// 轻量扩展控制器基类，在加载视图时执行异步扩展逻辑。
class ExtensionController: NSViewController { // swiftlint:disable:this final_class
	/// 创建无 nib 的扩展控制器。
	init() {
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError() // swiftlint:disable:this fatal_error_message
	}

	/// 启动扩展任务，并把结果或错误回传给系统。
	override func loadView() {
		Task { @MainActor in // Not sure if this is needed, but added just in case.
			do {
				extensionContext!.completeRequest(
					returningItems: try await run(extensionContext!),
					completionHandler: nil
				)
			} catch {
				extensionContext!.cancelRequest(withError: error)
			}
		}
	}

	/// 子类覆盖此方法执行实际的扩展业务。
	func run(_ context: NSExtensionContext) async throws -> [NSExtensionItem] { [] }
}
