import SwiftUI
import UniformTypeIdentifiers

/// 壁纸管理页面，统一管理网站、视频和图片来源。
struct WallpaperScreen: View {
	@Default(.wallpaperSettings) private var wallpaperSettings
	@State private var selectedDisplayID: Display.ID?
	@State private var isVideoImporterPresented = false
	@State private var isImageImporterPresented = false
	@State private var importerError: String?

	private var displays: [Display] { Display.all }

	private var selectedDisplay: Display? {
		if let selectedDisplayID {
			return displays.first { $0.id == selectedDisplayID }
		}

		return displays.first
	}

	private var configuration: Binding<WallpaperConfiguration> {
		.init {
			guard let display = selectedDisplay ?? displays.first else {
				return wallpaperSettings.sharedConfiguration
			}

			return wallpaperSettings.configuration(for: display)
		} set: {
			wallpaperSettings.setConfiguration($0, for: selectedDisplay)
			AppState.shared.reloadWallpaper()
		}
	}

	/// 当前来源的完整设置内容。
	var body: some View {
		content
		.frame(maxWidth: .infinity, minHeight: 540, maxHeight: .infinity)
		.onAppear {
			if selectedDisplayID == nil {
				selectedDisplayID = displays.first?.id
			}
		}
		.fileImporter(
			isPresented: $isVideoImporterPresented,
			allowedContentTypes: [
				.movie,
				.video,
				.mpeg4Movie,
				.quickTimeMovie
			],
			allowsMultipleSelection: true
		) {
			handleVideoImport($0)
		}
		.fileImporter(
			isPresented: $isImageImporterPresented,
			allowedContentTypes: [
				.image
			],
			allowsMultipleSelection: true
		) {
			handleImageImport($0)
		}
	}

	@ViewBuilder
	private var content: some View {
		Form {
			displaySection
			sourceSection

			switch configuration.wrappedValue.sourceKind {
			case .website:
				WebsiteSettingsSections()
			case .video:
				videoSettingsSections
			case .image:
				imageSettingsSections
			}

			importerErrorSection
		}
		.formStyle(.grouped)
	}

	private var displaySection: some View {
		Section("显示器") {
			displayControls
		}
	}

	private var sourceSection: some View {
		Section("来源") {
			sourcePicker
		}
	}

	@ViewBuilder
	private var displayControls: some View {
		Picker("模式", selection: $wallpaperSettings.displayMode) {
			ForEach(WallpaperDisplayMode.allCases) { mode in
				Text(mode.title)
					.tag(mode)
			}
		}
		.pickerStyle(.segmented)
		.onChange(of: wallpaperSettings.displayMode) {
			AppState.shared.reloadWallpaper()
		}

		if wallpaperSettings.displayMode == .separatePerDisplay {
			Picker("当前显示器", selection: selectedDisplayIDBinding) {
				ForEach(displays) { display in
					Text(display.localizedName)
						.tag(display.id as Display.ID?)
				}
			}
		}
	}

	private var sourcePicker: some View {
		Picker("来源", selection: configuration.sourceKind) {
			ForEach(WallpaperSourceKind.allCases) { sourceKind in
				Label(sourceKind.title, systemImage: sourceKind.systemImage)
					.tag(sourceKind)
			}
		}
		.pickerStyle(.segmented)
	}

	@ViewBuilder
	private var videoSettingsSections: some View {
		Section("视频") {
			Button("选择视频…", systemImage: "plus") {
				isVideoImporterPresented = true
			}

			if configuration.wrappedValue.video.urls.isEmpty {
				Text("未选择视频")
					.foregroundStyle(.secondary)
			} else {
				ForEach(Array(configuration.wrappedValue.video.urls.enumerated()), id: \.offset) { index, url in
					HStack {
						Text(url.lastPathComponent)
							.lineLimit(1)
						Spacer()
						if index == configuration.wrappedValue.video.selectedIndex {
							Image(systemName: "checkmark.circle.fill")
								.foregroundStyle(.green)
						}
					}
					.contentShape(.rect)
					.onTapGesture {
						configuration.video.selectedIndex.wrappedValue = index
					}
				}
			}
		}

		Section("播放") {
			Toggle("自动播放", isOn: configuration.video.startsAutomatically)
			Toggle("循环播放", isOn: configuration.video.shouldLoop)
			Toggle("静音", isOn: configuration.video.isMuted)
			Toggle("显示播放控件", isOn: configuration.video.showsControls)
			Slider(
				value: configuration.video.playbackRate,
				in: 0.25...2,
				step: 0.25
			) {
				Text("播放速度")
			}
			Picker("填充方式", selection: configuration.video.fillMode) {
				ForEach(WallpaperFillMode.allCases) { fillMode in
					Text(fillMode.title)
						.tag(fillMode)
				}
			}
		}
	}

	@ViewBuilder
	private var imageSettingsSections: some View {
		Section("图片") {
			Button("选择图片…", systemImage: "plus") {
				isImageImporterPresented = true
			}

			if configuration.wrappedValue.image.urls.isEmpty {
				Text("未选择图片")
					.foregroundStyle(.secondary)
			} else {
				ForEach(Array(configuration.wrappedValue.image.urls.enumerated()), id: \.offset) { index, url in
					HStack {
						Text(url.lastPathComponent)
							.lineLimit(1)
						Spacer()
						if index == configuration.wrappedValue.image.selectedIndex {
							Image(systemName: "checkmark.circle.fill")
								.foregroundStyle(.green)
						}
					}
					.contentShape(.rect)
					.onTapGesture {
						configuration.image.selectedIndex.wrappedValue = index
					}
				}
			}
		}

		Section("轮播") {
			Toggle("启用轮播", isOn: configuration.image.isSlideshowEnabled)
			LabeledContent("切换间隔") {
				Stepper(
					value: configuration.image.slideshowInterval,
					in: 5...86_400,
					step: 5
				) {
					Text("\(Int(configuration.wrappedValue.image.slideshowInterval)) 秒")
						.monospacedDigit()
				}
			}
			Toggle("随机顺序", isOn: configuration.image.isRandomOrder)
			Toggle("模糊背景", isOn: configuration.image.usesBlurredBackground)
			Picker("填充方式", selection: configuration.image.fillMode) {
				ForEach(WallpaperFillMode.allCases) { fillMode in
					Text(fillMode.title)
						.tag(fillMode)
				}
			}
		}
	}

	@ViewBuilder
	private var importerErrorSection: some View {
		if let importerError {
			Section {
				Text(importerError)
					.foregroundStyle(.red)
			}
		}
	}

	private var selectedDisplayIDBinding: Binding<Display.ID?> {
		.init {
			selectedDisplayID ?? displays.first?.id
		} set: {
			selectedDisplayID = $0
		}
	}

	private func handleVideoImport(_ result: Result<[URL], Error>) {
		do {
			let urls = try result.get()
			configuration.video.urls.wrappedValue = urls
			configuration.video.selectedIndex.wrappedValue = 0
			importerError = nil
		} catch {
			importerError = error.localizedDescription
		}
	}

	private func handleImageImport(_ result: Result<[URL], Error>) {
		do {
			let urls = try result.get()
			configuration.image.urls.wrappedValue = urls
			configuration.image.selectedIndex.wrappedValue = 0
			importerError = nil
		} catch {
			importerError = error.localizedDescription
		}
	}
}

#Preview {
	WallpaperScreen()
}
