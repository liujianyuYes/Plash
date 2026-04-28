import Cocoa

extension AppState {
	/// 注册 `plash:` URL Scheme 命令监听。
	func setUpURLCommands() {
		SSEvents.appOpenURL
			.sink { [self] in
				handleURLCommands($0)
			}
			.store(in: &cancellables)
	}

	/// 解析并执行外部传入的 `plash:` 命令。
	private func handleURLCommands(_ urlComponents: URLComponents) {
		guard urlComponents.scheme == "plash" else {
			return
		}

		let command = urlComponents.path
		let parameters = urlComponents.queryDictionary

		/// 激活 App 并展示命令错误信息。
		func showMessage(_ message: String) {
			SSApp.forceActivate()
			NSAlert.showModal(title: message)
		}

		switch command {
		case "add":
			guard
				let urlString = parameters["url"]?.trimmed,
				let url = URL(string: urlString, encodingInvalidCharacters: false),
				url.isValid
			else {
				showMessage("“add” 命令的 URL 无效。")
				return
			}

			WebsitesController.shared.add(url, title: parameters["title"]?.trimmed.nilIfEmpty)
		case "reload":
			reloadWebsite()
		case "next":
			WebsitesController.shared.makeNextCurrent()
		case "previous":
			WebsitesController.shared.makePreviousCurrent()
		case "random":
			WebsitesController.shared.makeRandomCurrent()
		case "toggle-browsing-mode":
			toggleBrowsingMode()
		default:
			showMessage("不支持命令“\(command)”。")
		}
	}
}
