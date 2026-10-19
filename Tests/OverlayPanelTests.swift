// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// AppKit describes a non-activating panel as a system dialog, which tiling
/// window managers track and list on whichever space is current. The shared
/// panel class is compiled here and created deferred, so no window is shown;
/// each floating surface's own file is read for the class it builds.
enum OverlayPanelTests {
    static func run(_ suite: TestSuite) {
        // The Clipboard History window keeps a title bar strip to drag it by.
        for style: NSWindow.StyleMask in [[.borderless, .nonactivatingPanel],
                                          [.titled, .closable, .fullSizeContentView, .nonactivatingPanel]] {
            let overlay = OverlayPanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 40),
                                       styleMask: style, backing: .buffered, defer: true)
            suite.expect(overlay.accessibilitySubrole() == .unknown,
                         "a floating overlay describes itself as an undescribed window, so window managers skip it")
            suite.expect(overlay.accessibilityRole() == .window && overlay.isAccessibilityElement(),
                         "a floating overlay stays an accessible window for assistive technology")
        }

        // HUDs, previews, pickers and the menu's positioning helper: none is a
        // document window, and each floats over other apps' windows.
        let surfaces = [
            "Sources/Juno Island/App/AppDelegate.swift",
            "Sources/Juno Island/UI/PermissionGuideOverlay.swift",
            "Sources/Juno Island/UI/QuitProtection/QuitProtectionHUD.swift",
            "Sources/Juno Island/Services/QuickTools/QuickToolHUD.swift",
            "Sources/Juno Island/Services/QuickTools/QuickLauncherService.swift",
            "Sources/Juno Island/Services/QuickTools/CameraPreviewService.swift",
            "Sources/Juno Island/Services/QuickTools/RecentCaptureService.swift",
            "Sources/Juno Island/Services/QuickTools/ScreenshotSelectionController.swift",
            "Sources/Juno Island/Services/QuickTools/ScreenshotQuickPreviewController.swift",
            "Sources/Juno Island/Services/QuickTools/ScreenshotPinController.swift",
            "Sources/Juno Island/Services/QuickTools/QRResultController.swift",
            "Sources/Juno Island/Services/QuickTools/ScratchpadService.swift",
            "Sources/Juno Island/Services/Snippets/SnippetLibraryService.swift",
            "Sources/Juno Island/Services/Clipboard/ClipboardHistoryService.swift",
            "Sources/Juno Island/Services/CommandBar/CommandBarService.swift",
            "Sources/Juno Island/Services/Switcher/AppSwitcher.swift",
            "Sources/Juno Island/Services/RadialMenu/RadialMenuService.swift",
            "Sources/Juno Island/Services/RadialMenu/RadialNowPlayingService.swift",
            "Sources/Juno Island/Services/DockPreview/DockPreviewService.swift",
            "Sources/Juno Island/Services/WindowLayout/WindowLayoutService.swift",
            "Sources/Juno Island/Services/DiskImageInstaller/DiskImageInstallerService.swift",
            "Sources/Juno Island/Services/Finder/FinderCutPaste.swift",
            "Sources/Juno Island/Services/Display/BrightnessOSD.swift",
            "Sources/Juno Island/Services/CleaningMode/CleaningModeManager.swift",
            "Sources/Juno Island/Services/Recorder/RecorderIndicator.swift",
        ]
        for path in surfaces {
            let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            suite.expect(source.range(of: #"\bOverlayPanel\(contentRect|:\s*OverlayPanel\b"#,
                                      options: .regularExpression) != nil
                         && !source.contains("NSPanel(contentRect")
                         && source.range(of: #"class \w+:\s*NSPanel\b"#, options: .regularExpression) == nil,
                         "\(path) builds its floating panels as overlays, which window managers do not list")
        }
    }
}
