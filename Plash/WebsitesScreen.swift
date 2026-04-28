import SwiftUI

/// 网站管理窗口，展示、添加、编辑、删除和切换用户保存的网站。
struct WebsitesScreen: View {
	/// 网站表单。
	var body: some View {
		Form {
			WebsiteSettingsSections()
		}
		.formStyle(.grouped)
		.frame(minWidth: 480, idealWidth: 520, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
		.windowMinimizeBehavior(.disabled)
		.windowLevel(.floating)
	}
}

/// 网站设置表单区域，用于独立网站页和壁纸页的网站来源。
struct WebsiteSettingsSections: View {
	@Default(.websites) private var websites
//	@State private var selection: Website.ID? // We need two states as selection must be independent from actually opening the editing because of keyboard navigation and accessibility.
	@State private var editedWebsite: Website.ID?
	@State private var isAddWebsiteDialogPresented = false

	/// 网站列表、添加入口和编辑弹窗。
	var body: some View {
		Section("网站") {
			Button("添加网站…", systemImage: "plus") {
				isAddWebsiteDialogPresented = true
			}

			if websites.isEmpty {
				Text("没有网站")
					.foregroundStyle(.secondary)
			} else {
				ForEach($websites) { website in
					RowView(
						website: website,
						selection: $editedWebsite
					)
				}
				.id(websites) // Workaround for the row not updating when changing the current active website. It's placed here and not on the row to prevent another issue where adding a new website makes it scroll outside the view. (macOS 15.3)
			}
		}
//			.onKeyboardShortcut(.defaultAction) {
//				editedWebsite = selection
//			}
		.accessibilityAction(named: "添加网站") {
			isAddWebsiteDialogPresented = true
		}
//		.onChange(of: editedWebsite) {
//			selection = $0
//		}
		.sheet(item: $editedWebsite) {
			AddWebsiteScreen(
				isEditing: true,
				website: $websites[id: $0]
			)
		}
		.sheet(isPresented: $isAddWebsiteDialogPresented) {
			AddWebsiteScreen(
				isEditing: false,
				website: nil
			)
		}
	}
}

/// 网站列表中的单行视图，负责当前状态展示和行级操作。
private struct RowView: View {
	@Binding var website: Website
	@Binding var selection: Website.ID?

	/// 网站标题、URL、图标和上下文菜单。
	var body: some View {
		HStack {
			Label {
				// TODO: This should use something like `.lineBreakMode = .byCharWrapping` if SwiftUI ever supports that.
				if let title = website.title.nilIfEmpty {
					Text(title)
				}
				Text(website.subtitle)
			} icon: {
				IconView(website: website)
			}
			.lineLimit(1)
			Spacer()
			if website.isCurrent {
				Image(systemName: "checkmark.circle.fill")
					.renderingMode(.original)
					.font(.title2)
			}
		}
		.frame(height: 64) // Note: Setting a fixed height prevents a lot of SwiftUI rendering bugs.
		.padding(.horizontal, 8)
		.help(website.tooltip)
		.swipeActions(edge: .leading, allowsFullSwipe: true) {
			Button("设为当前") {
				website.makeCurrent()
			}
			.disabled(website.isCurrent)
		}
		.contentShape(.rect)
		.onDoubleClick {
			selection = website.id
		}
		.contextMenu { // Must come after `.onDoubleClick`.
			Button("设为当前") {
				website.makeCurrent()
			}
			.disabled(website.isCurrent)
			Divider()
			Button("编辑…") {
				selection = website.id
			}
			Divider()
			Button("删除", role: .destructive) {
				website.remove()
			}
		}
		.accessibilityElement(children: .combine)
		.accessibilityAddTraits(.isButton)
		.if(website.isCurrent) {
			$0.accessibilityAddTraits(.isSelected)
		}
		.accessibilityAction(named: "编辑") { // Doesn't show up in accessibility actions. (macOS 14.0)
			selection = website.id
		}
		.accessibilityRepresentation {
			Button(website.menuTitle) {
				selection = website.id
			}
		}
	}
}

/// 网站图标视图，优先读取缓存，缺失时异步抓取。
private struct IconView: View {
	@State private var icon: Image?

	let website: Website

	/// 固定尺寸的网站图标或占位背景。
	var body: some View {
		VStack {
			if let icon {
				icon
					.resizable()
					.scaledToFit()
			} else {
				Color.primary.opacity(0.1)
			}
		}
		.frame(width: 32, height: 32)
		.clipShape(.rect(cornerRadius: 4))
		.task(id: website.url) {
			guard let image = await fetchIcons() else {
				return
			}

			icon = Image(nsImage: image)
		}
	}

	/// 从内存/磁盘缓存或网络获取网站图标。
	private func fetchIcons() async -> NSImage? {
		let cache = WebsitesController.shared.thumbnailCache

		if let image = cache[website.thumbnailCacheKey] {
			return image
		}

		guard let image = try? await WebsiteIconFetcher.fetch(for: website.url) else {
			return nil
		}

		cache[website.thumbnailCacheKey] = image

		return image
	}
}
