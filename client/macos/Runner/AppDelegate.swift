import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // 菜单栏应用：关闭窗口只隐藏，不退出
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  // 点击 Dock 图标时重新显示窗口
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for w in sender.windows { w.makeKeyAndOrderFront(nil) }
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
