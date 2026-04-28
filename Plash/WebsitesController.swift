import SwiftUI
import LinkPresentation

/// 管理用户网站列表、当前网站选择、随机切换和网站标题/图标缓存。
@MainActor
final class WebsitesController {
	static let shared = WebsitesController()

	private var cancellables = Set<AnyCancellable>()
	private var _current: Website? { all.first(where: \.isCurrent) }
	private var nextCurrent: Website? { all.elementAfterOrFirst(_current) }
	private var previousCurrent: Website? { all.elementBeforeOrLast(_current) }

	var randomWebsiteIterator = Defaults[.websites].infiniteUniformRandomSequence().makeIterator()

	@MainActor let thumbnailCache = SimpleImageCache<String>(diskCacheName: "websiteThumbnailCache")

	/// 当前正在显示的网站；没有显式当前项时回退到列表第一项。
	var current: Website? {
		get { _current ?? all.first }
		set {
			guard let newValue else {
				all = all.modifying {
					$0.isCurrent = false
				}

				return
			}

			makeCurrent(newValue)
		}
	}

	/// 用户保存的全部网站，持久化在 Defaults 中。
	var all: [Website] {
		get { Defaults[.websites] }
		set {
			Defaults[.websites] = newValue
		}
	}

	let allBinding = Defaults.bindingCollection(for: .websites)

	/// 初始化网站变更监听，并预热缩略图缓存。
	private init() {
		setUpEvents()
		thumbnailCache.prewarmCacheFromDisk(for: all.map(\.thumbnailCacheKey))
	}

	/// 监听网站列表变更，保证存在当前网站并刷新随机迭代器。
	private func setUpEvents() {
		Defaults.publisher(.websites)
			.sink { [weak self] change in
				guard let self else {
					return
				}

				// Ensures there's always a current website.
				if
					change.newValue.allSatisfy(!\.isCurrent),
					let website = change.newValue.first
				{
					website.makeCurrent()
				}

				// We only reset the iterator if a website was added/removed.
				if change.newValue.map(\.id) != change.oldValue.map(\.id) {
					randomWebsiteIterator = all.infiniteUniformRandomSequence().makeIterator()
				}
			}
			.store(in: &cancellables)
	}

	/// 将指定网站标记为唯一当前项。
	private func makeCurrent(_ website: Website) {
		all = all.modifying {
			$0.isCurrent = $0.id == website.id
		}
	}

	/// 添加完整的网站配置，并把它设为当前网站。
	@discardableResult
	func add(_ website: Website) -> Binding<Website> {
		// The order here is important.
		all.append(website)
		current = website

		return allBinding[id: website.id]!
	}

	/// 通过 URL 创建网站配置；未提供标题时异步抓取网页标题。
	@discardableResult
	func add(_ websiteURL: URL, title: String? = nil) -> Binding<Website> {
		let websiteBinding = add(
			Website(
				id: UUID(),
				isCurrent: true,
				url: websiteURL,
				usePrintStyles: false
			)
		)

		if let title = title?.nilIfEmptyOrWhitespace {
			websiteBinding.wrappedValue.title = title
		} else {
			fetchTitleIfNeeded(for: websiteBinding)
		}

		return websiteBinding
	}

	/// 从列表中移除指定网站。
	func remove(_ website: Website) {
		all = all.removingAll(website)
	}

	/// 切换到列表中的下一个网站。
	func makeNextCurrent() {
		guard let nextCurrent else {
			return
		}

		makeCurrent(nextCurrent)
	}

	/// 切换到列表中的上一个网站。
	func makePreviousCurrent() {
		guard let previousCurrent else {
			return
		}

		makeCurrent(previousCurrent)
	}

	/// 随机切换网站，并尽量避免连续选中同一个网站。
	func makeRandomCurrent() {
		guard let website = randomWebsiteIterator.next() else {
			return
		}

		makeCurrent(website)
	}

	/// 在标题为空时使用 LinkPresentation 异步抓取网页标题。
	func fetchTitleIfNeeded(for website: Binding<Website>) {
		guard website.wrappedValue.title.isEmpty else {
			return
		}

		Task {
			let metadataProvider = LPMetadataProvider()
			metadataProvider.shouldFetchSubresources = false

			guard
				let metadata = try? await metadataProvider.startFetchingMetadata(for: website.wrappedValue.url),
				let title = metadata.title
			else {
				return
			}

			website.wrappedValue.title = title
		}
	}
}
