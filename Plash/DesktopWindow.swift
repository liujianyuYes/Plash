import Cocoa
import SwiftUI

/// 覆盖桌面的透明窗口，用于承载网页壁纸并在浏览模式下接收输入。
final class DesktopWindow: NSWindow {
	override var canBecomeMain: Bool { isInteractive }
	override var canBecomeKey: Bool { isInteractive }
	override var acceptsFirstResponder: Bool { isInteractive }

	private static let nonInteractiveLevel = NSWindow.Level.desktopIcon - 1

	private var cancellables = Set<AnyCancellable>()

	var targetDisplay: Display? {
		didSet {
			setFrame()
		}
	}

	/// 控制窗口是否可交互，并同步对应的窗口层级和鼠标事件策略。
	var isInteractive = false {
		didSet {
			if isInteractive {
				level = Defaults[.bringBrowsingModeToFront] ? .floating : (.desktopIcon + 1) // The `+ 1` fixes a weird issue where the window is sometimes not interactive. (macOS 11.2.1)
				makeKeyAndOrderFront(self)
				ignoresMouseEvents = false
			} else {
				level = Self.nonInteractiveLevel
				orderBack(self)

				// Even though the window ignores mouse events, this prevents accidental interaction if desktop icons are hidden.
				ignoresMouseEvents = true
			}
		}
	}

	/// 创建绑定到指定显示器的无边框桌面窗口。
	convenience init(display: Display?) {
		self.init(
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
		self.level = Self.nonInteractiveLevel
		self.isRestorable = false
		self.canHide = false
		self.displaysWhenScreenProfileChanges = true
		self.collectionBehavior = [
			.stationary,
			.ignoresCycle,
			.fullScreenNone // This ensures that if Plash is launched while an app is fullscreen (fullscreen is a separate space), it will not show behind that app and instead show in the primary space.
		]

		disableSnapshotRestoration()
		setFrame()

		NSScreen.publisher
			.sink { [weak self] in
				self?.setFrame()
			}
			.store(in: &cancellables)

		Defaults.publisher(.extendPlashBelowMenuBar)
			.sink { [weak self] _ in
				self?.setFrame()
			}
			.store(in: &cancellables)
	}

	/// 按目标显示器和菜单栏覆盖设置调整窗口尺寸。
	private func setFrame() {
		// Ensure the screen still exists.
		guard let screen = targetDisplay?.screen ?? .primary else {
			return
		}

		var frame = screen.frameWithoutStatusBar
		frame.size.height += 1 // Probably not needed, but just to ensure it covers all the way up to the menu bar on older Macs (I can only test on M1 Mac)

		if Defaults[.extendPlashBelowMenuBar] {
			frame = screen.frame
		}

		setFrame(frame, display: true)
	}
}

/// 组件从设置页拖到桌面时临时显示的透明投放窗口。
final class DesktopComponentDropWindow: NSWindow {
	private var cancellables = Set<AnyCancellable>()

	var targetDisplay: Display? {
		didSet {
			setFrame()
		}
	}

	/// 创建覆盖桌面的透明拖放目标。
	convenience init(display: Display?) {
		self.init(
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
		self.isRestorable = false
		self.canHide = false
		self.displaysWhenScreenProfileChanges = true
		self.level = .desktopIcon + 3
		self.collectionBehavior = [
			.stationary,
			.ignoresCycle,
			.fullScreenNone
		]

		let dropView = DesktopComponentDropView()
		dropView.wantsLayer = true
		dropView.layer?.backgroundColor = NSColor.clear.cgColor
		self.contentView = dropView

		disableSnapshotRestoration()
		setFrame()

		NSScreen.publisher
			.sink { [weak self] in
				self?.setFrame()
			}
			.store(in: &cancellables)

		Defaults.publisher(.extendPlashBelowMenuBar)
			.sink { [weak self] _ in
				self?.setFrame()
			}
			.store(in: &cancellables)
	}

	/// 显示或隐藏拖放目标。
	func setDropTargetVisible(_ isVisible: Bool) {
		if isVisible {
			orderFrontRegardless()
		} else {
			orderOut(nil)
		}
	}

	/// 接收拖放并把组件放到拖放事件所在槽位。
	fileprivate func performComponentDrop(from pasteboard: NSPasteboard, at screenPoint: NSPoint) -> Bool {
		guard
			let payload = pasteboard.string(forType: .desktopComponent),
			let dragItem = DesktopComponentDragPayload.decode(payload),
			currentScreenFrame != .zero
		else {
			return false
		}

		DesktopComponentsController.shared.drop(dragItem, at: screenPoint, in: currentScreenFrame)
		AppState.shared.setDesktopComponentDropMode(false)

		return true
	}

	/// 当前可用屏幕区域。
	private var currentScreenFrame: CGRect {
		guard let screen = targetDisplay?.screen ?? .primary else {
			return .zero
		}

		return Defaults[.extendPlashBelowMenuBar] ? screen.frame : screen.frameWithoutStatusBar
	}

	/// 跟随目标显示器尺寸。
	private func setFrame() {
		let screenFrame = currentScreenFrame
		guard screenFrame != .zero else {
			return
		}

		setFrame(screenFrame, display: true)
	}
}

/// 透明拖放目标内容视图。
private final class DesktopComponentDropView: NSView {
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		registerForDraggedTypes([.desktopComponent])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		canAccept(sender) ? .copy : []
	}

	override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
		canAccept(sender) ? .copy : []
	}

	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		guard
			canAccept(sender),
			let window = window as? DesktopComponentDropWindow
		else {
			return false
		}

		let screenPoint = window.convertPoint(toScreen: sender.draggingLocation)

		return window.performComponentDrop(from: sender.draggingPasteboard, at: screenPoint)
	}

	private func canAccept(_ sender: NSDraggingInfo) -> Bool {
		sender.draggingPasteboard.string(forType: .desktopComponent) != nil
	}
}

/// 贴在桌面壁纸窗口右下角的独立设置按钮窗口。
final class DesktopSettingsButtonWindow: NSWindow {
	override var canBecomeKey: Bool { true }
	override var canBecomeMain: Bool { false }

	private static let buttonSize = CGSize(width: 56, height: 56)
	private static let inset = 24.0

	private var cancellables = Set<AnyCancellable>()

	var targetDisplay: Display? {
		didSet {
			setFrame()
		}
	}

	/// 创建只覆盖按钮区域的透明窗口，避免拦截整张桌面的点击。
	convenience init(display: Display?) {
		self.init(
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
		self.isRestorable = false
		self.canHide = false
		self.displaysWhenScreenProfileChanges = true
		self.collectionBehavior = [
			.stationary,
			.ignoresCycle,
			.fullScreenNone
		]
		self.contentView = NSHostingView(
			rootView: FloatingSettingsButton {
				Constants.openSettingsInWebsitesWindow()
			}
		)

		refreshLevel(isBrowsingMode: Defaults[.isBrowsingMode])
		disableSnapshotRestoration()
		setFrame()

		NSScreen.publisher
			.sink { [weak self] in
				self?.setFrame()
			}
			.store(in: &cancellables)

		Defaults.publisher(.extendPlashBelowMenuBar)
			.sink { [weak self] _ in
				self?.setFrame()
			}
			.store(in: &cancellables)
	}

	/// 按当前浏览模式把按钮放到桌面窗口上方。
	func refreshLevel(isBrowsingMode: Bool) {
		if isBrowsingMode {
			level = Defaults[.bringBrowsingModeToFront] ? .floating + 1 : .desktopIcon + 2
		} else {
			level = .desktopIcon
		}
	}

	/// 按设置显示或隐藏按钮窗口。
	func setSettingsButtonVisible(_ isVisible: Bool) {
		if isVisible {
			orderFrontRegardless()
		} else {
			orderOut(nil)
		}
	}

	/// 将按钮固定在目标显示器的右下角。
	private func setFrame() {
		guard let screen = targetDisplay?.screen ?? .primary else {
			return
		}

		let screenFrame = Defaults[.extendPlashBelowMenuBar] ? screen.frame : screen.frameWithoutStatusBar
		let frame = NSRect(
			x: screenFrame.maxX - Self.buttonSize.width - Self.inset,
			y: screenFrame.minY + Self.inset,
			width: Self.buttonSize.width,
			height: Self.buttonSize.height
		)

		setFrame(frame, display: true)
	}
}
