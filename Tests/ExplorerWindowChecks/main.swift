import AppKit

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    let window = ExplorerWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                                styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let history = ["Home", "Documents", "Project"]
    var index = 2
    var backCalls = 0
    var forwardCalls = 0
    window.navigateBack = { backCalls += 1; index = max(0, index - 1) }
    window.navigateForward = { forwardCalls += 1; index = min(history.count - 1, index + 1) }

    // Dispatch native events directly to our window. No input is posted to macOS or another app.
    func send(_ type: CGEventType, button: UInt32) {
        let cg = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero,
                         mouseButton: CGMouseButton(rawValue: button)!)!
        let event = NSEvent(cgEvent: cg)!
        require(event.buttonNumber == Int(button), "Native event button number")
        window.sendEvent(event)
    }
    send(.otherMouseDown, button: 3)
    require(index == 2 && backCalls == 0, "Mouse press must not navigate")
    send(.otherMouseUp, button: 3)
    require(history[index] == "Documents" && backCalls == 1, "Back release must navigate exactly once")
    send(.otherMouseDown, button: 4)
    require(index == 1 && forwardCalls == 0, "Forward press must not navigate")
    send(.otherMouseUp, button: 4)
    require(history[index] == "Project" && forwardCalls == 1, "Forward release must navigate exactly once")
    send(.otherMouseDown, button: 2)
    send(.otherMouseUp, button: 2)
    require(backCalls == 1 && forwardCalls == 1, "Middle button must not change history")
    send(.otherMouseDown, button: 5)
    send(.otherMouseUp, button: 5)
    require(backCalls == 1 && forwardCalls == 1, "Other buttons must not change history")
    window.close()
    print("PASS: native mouse Back/Forward dispatch, one navigation per click, middle/extra buttons unchanged")
}
