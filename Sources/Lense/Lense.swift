import AppKit
import SwiftUI
import ScreenCaptureKit

final class KeyPanel: NSPanel { override var canBecomeKey: Bool { true } }
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var bubble: NSPanel!
    var bubbleView: BubbleView!
    var collapsedFrame: CGRect?
    var keyField: NSSecureTextField?
    var overlays: [NSPanel] = []
    var settingsPanel: NSPanel?
    var status: NSStatusItem!
    var shortcut = OverlayShortcut()
    var globalKeyMonitor: Any?
    var keyMonitor: Any?
    var task: Task<Void,Never>?
    var session = CanvasSession()
    var permissionRequest = PermissionRequestGate()
    private var visibilityRevision = UUID()
    private var overlayWatch: Timer?
    private(set) var yieldsToExternalOverlay = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Lense")
        let quitItem = NSMenuItem(title: "退出 Lense", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self; appMenu.addItem(quitItem)
        appItem.submenu = appMenu; mainMenu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        for (title, action, key) in [("剪切", #selector(NSText.cut(_:)), "x"),
                                     ("复制", #selector(NSText.copy(_:)), "c"),
                                     ("粘贴", #selector(NSText.paste(_:)), "v"),
                                     ("全选", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        editItem.submenu = editMenu; mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
        status = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        status.button?.title = "◉"
        let menu = NSMenu()
        for (title, action) in [("开关透明画板  ⌃⌥",#selector(toggleOverlay)),("设置…",#selector(settings)),("退出 Lense",#selector(quit))] {
            let item = NSMenuItem(title:title,action:action,keyEquivalent:""); item.target = self; menu.addItem(item)
        }
        status.menu = menu
        bubble = panel(frame:CGRect(x:0,y:0,width:60,height:60))
        bubbleView = BubbleView(owner:self)
        bubble.contentView = bubbleView
        if let screen = NSScreen.main { bubble.setFrameOrigin(CGPoint(x:screen.visibleFrame.maxX-60,y:screen.visibleFrame.midY)); bubbleView.dock(to:.right) }
        bubble.orderFrontRegardless()
        overlayWatch = Timer.scheduledTimer(withTimeInterval:0.15,repeats:true) { [weak self] _ in
            Task { @MainActor in self?.checkExternalOverlays() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleShortcut(event.modifierFlags)
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let flags = event.modifierFlags
            Task { @MainActor in self?.handleShortcut(flags) }
        }
    }
    func handleShortcut(_ flags: NSEvent.ModifierFlags) {
        for panel in overlays {
            (panel.contentView as? AnnotationBoard)?.showsBoxOutlines = session.isVisible && !yieldsToExternalOverlay && flags.contains(.command)
        }
        if shortcut.update(control: flags.contains(.control), option: flags.contains(.option),
                           otherModifiers: !flags.intersection([.command, .shift]).isEmpty) {
            toggleOverlay()
        }
    }

    func checkExternalOverlays(windows:[[String:Any]]? = nil) {
        guard session.isVisible else { return }
        let list = windows ?? (CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? [])
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let blocked = list.contains { item in
            let owner = item[kCGWindowOwnerName as String] as? String ?? ""
            guard !["Dock", "Window Server", "SystemUIServer"].contains(owner),
                  (item[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let pid = item[kCGWindowOwnerPID as String] as? Int, pid != ownPID,
                  let layer = item[kCGWindowLayer as String] as? Int, layer >= Int(NSWindow.Level.popUpMenu.rawValue),
                  let dictionary = item[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation:dictionary) else { return false }
            return overlays.contains { panel in
                let screenRect = CGRect(x:panel.frame.minX,y:(NSScreen.screens.first?.frame.maxY ?? 0)-panel.frame.maxY,width:panel.frame.width,height:panel.frame.height)
                let area = rect.intersection(screenRect)
                return !area.isNull && area.width >= panel.frame.width*0.85 && area.height >= panel.frame.height*0.85
            }
        }
        guard blocked != yieldsToExternalOverlay else { return }
        yieldsToExternalOverlay = blocked
        for panel in overlays {
            panel.ignoresMouseEvents = blocked
            (panel.contentView as? AnnotationBoard)?.showsBoxOutlines = !blocked && NSEvent.modifierFlags.contains(.command)
            if blocked { panel.resignKey() }
            else { panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(panel.contentView) }
        }
        bubble.ignoresMouseEvents = blocked
    }

    func panel(frame:CGRect) -> NSPanel {
        let p = KeyPanel(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = false; p.hasShadow = false
        p.becomesKeyOnlyIfNeeded = false
        p.isOpaque = false; p.backgroundColor = .clear; p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; p.isReleasedWhenClosed = false
        return p
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool) -> Bool {
        bubble.orderFrontRegardless()
        return false
    }
    func alert(_ text:String) { let a = NSAlert(); a.messageText = "Lense"; a.informativeText = text; a.runModal() }
    func dismiss() {
        visibilityRevision = UUID(); let revision = visibilityRevision
        session.isVisible = false
        yieldsToExternalOverlay = false; bubble.ignoresMouseEvents = false
        for panel in overlays {
            (panel.contentView as? AnnotationBoard)?.showsBoxOutlines = false
            panel.ignoresMouseEvents = true
            guard panel.isVisible else { continue }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name:.easeOut)
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self, weak panel] in
                Task { @MainActor in
                    guard let self, let panel, self.visibilityRevision == revision, !self.session.isVisible else { return }
                    panel.orderOut(nil); panel.alphaValue = 1
                }
            }
        }
        bubbleView.isOverlayActive = false
        bubble.orderFrontRegardless()
    }
    @objc func toggle() {
        if session.isVisible || !overlays.isEmpty { toggleOverlay(); return }
        guard !Secret.read().isEmpty else { expandKeyEntry(); return }
        toggleOverlay()
    }
    @objc func toggleOverlay() {
        if session.isVisible { dismiss(); return }
        collapseKeyEntry(); settingsPanel?.orderOut(nil)
        if overlays.isEmpty { makeSelectionBoards() }
        visibilityRevision = UUID()
        session.isVisible = true
        NSApp.activate(ignoringOtherApps:true)
        for panel in overlays {
            if !panel.isVisible { panel.alphaValue = 0 }
            (panel.contentView as? AnnotationBoard)?.showsBoxOutlines = NSEvent.modifierFlags.contains(.command)
            panel.ignoresMouseEvents = false
            panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(panel.contentView)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name:.easeOut)
                panel.animator().alphaValue = 1
            }
        }
        checkExternalOverlays()
        bubbleView.isOverlayActive = true
        bubble.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        bubble.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps:true)
    }
    func makeSelectionBoards() {
        overlays.forEach { $0.close() }; overlays.removeAll()
        for screen in NSScreen.screens {
            let p = panel(frame:screen.frame)
            let view = SelectionView(frame:CGRect(origin:.zero,size:screen.frame.size))
            view.cancel = { [weak self] in self?.dismiss() }
            view.selected = { [weak self] rect in self?.selected(rect,screen:screen) }
            p.contentView = view; overlays.append(p)
        }
    }
    func clearForNewSelection() {
        task?.cancel(); task = nil; session.cancel()
        bubbleView.isThinking = false
    }
    func selected(_ rect:CGRect, screen:NSScreen) {
        guard rect.width >= 8,rect.height >= 8 else { return }
        clearForNewSelection()
        for panel in overlays {
            if let board = panel.contentView as? AnnotationBoard { board.show(BoardMarks(),sources:[]); board.setStatus("") }
        }
        guard !Secret.read().isEmpty else { dismiss(); expandKeyEntry(); return }
        guard CGPreflightScreenCaptureAccess() else {
            if permissionRequest.shouldRequest() && CGRequestScreenCaptureAccess() {
                selected(rect,screen:screen)
                return
            }
            let board = answerBoard(rect:rect,screen:screen)
            board.setStatus("屏幕录制尚未授权。打开权限设置允许 Lense，再点重试；若系统要求，请退出重开。",failed:true)
            board.reselectButton.title = "权限设置"
            board.reselect = {
                if let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            board.retry = { [weak self] in self?.selected(rect,screen:screen) }
            return
        }
        session.beginRound(); bubbleView.isThinking = true
        let token = session.generation
        task = Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
                      let display = content.displays.first(where:{$0.displayID == number}) else { throw NSError(domain:"Lense",code:5,userInfo:[NSLocalizedDescriptionKey:"未找到选中的屏幕。"] ) }
                let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = SCContentFilter(display:display,excludingApplications:ownApps,exceptingWindows:[])
                let config = SCStreamConfiguration()
                config.sourceRect = rect
                config.width = Int(rect.width * screen.backingScaleFactor); config.height = Int(rect.height * screen.backingScaleFactor)
                config.showsCursor = false; config.captureResolution = .best
                let image = try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
                try Task.checkCancellation()
                guard token == session.generation else { return }
                guard let png = NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) else { throw NSError(domain:"Lense",code:6,userInfo:[NSLocalizedDescriptionKey:"截图失败，请重新圈选。"] ) }
                showAnswer(png:png,rect:rect,screen:screen)
            } catch {
                if token == session.generation { session.finish(token); bubbleView.isThinking = false; showBoardError(error.localizedDescription,rect:rect,screen:screen) }
            }
        }
    }
    func answerBoard(rect:CGRect,screen:NSScreen) -> AnnotationBoard {
        overlays.forEach { $0.close() }; overlays.removeAll()
        let p = panel(frame:screen.frame)
        let board = AnnotationBoard(frame:CGRect(origin:.zero,size:screen.frame.size),selection:rect)
        board.showsBoxOutlines = session.isVisible && NSEvent.modifierFlags.contains(.command)
        board.close = { [weak self] in self?.dismiss() }
        board.reselect = { [weak self] in
            guard let self else { return }
            self.clearForNewSelection(); self.makeSelectionBoards()
            if self.session.isVisible { self.overlays.forEach { $0.makeKeyAndOrderFront(nil); $0.makeFirstResponder($0.contentView) }; self.bubble.orderFrontRegardless() }
        }
        board.newSelection = { [weak self] rect in self?.selected(rect,screen:screen) }
        p.contentView = board; overlays = [p]
        if session.isVisible { p.makeKeyAndOrderFront(nil); p.makeFirstResponder(board) }
        bubbleView.isOverlayActive = session.isVisible; bubble.orderFrontRegardless()
        checkExternalOverlays()
        return board
    }
    func showBoardError(_ message:String,rect:CGRect,screen:NSScreen) {
        let board = answerBoard(rect:rect,screen:screen)
        board.setStatus(message,failed:true)
        board.retry = { [weak self] in self?.selected(rect,screen:screen) }
    }
    func showAnswer(png:Data,rect:CGRect,screen:NSScreen) {
        let board = answerBoard(rect:rect,screen:screen)
        board.retry = { [weak self, weak board] in
            guard let self, let board else { return }
            self.clearForNewSelection(); self.session.beginRound()
            self.runAgent(png:png,board:board)
        }
        runAgent(png:png,board:board)
    }
    func runAgent(png:Data,board:AnnotationBoard,
                  send: @escaping (URLRequest) async throws -> (Data,URLResponse) = { try await URLSession.shared.data(for:$0) }) {
        let token = session.generation
        bubbleView.isThinking = true
        board.show(BoardMarks(),sources:[])
        board.setStatus("正在识别题目并原位标注… · ⌃⌥ 或 Esc 关闭")
        task = Task { @MainActor [weak self, weak board] in
            do {
                try await annotate(image:png,key:Secret.read(),send:send) { [weak self, weak board] marks,sources in
                    guard self?.session.generation == token else { return }
                    board?.show(marks,sources:sources)
                }
                guard self?.session.generation == token else { return }
                self?.session.finish(token); self?.bubbleView.isThinking = false
                board?.setStatus("")
            } catch {
                if self?.session.generation == token, !Task.isCancelled {
                    self?.session.finish(token); self?.bubbleView.isThinking = false
                    board?.setStatus(error.localizedDescription,failed:true)
                }
            }
        }
    }
    func expandKeyEntry() {
        if let keyField { bubble.makeKeyAndOrderFront(nil); bubble.makeFirstResponder(keyField); return }
        let original = bubble.frame
        let screen = bubble.screen ?? NSScreen.main!
        let width = min(360, screen.visibleFrame.width)
        let expandLeft = original.midX > screen.visibleFrame.midX
        let x = max(screen.visibleFrame.minX, min(expandLeft ? original.maxX-width : original.minX, screen.visibleFrame.maxX-width))
        collapsedFrame = original
        bubbleView.isKeyEntryExpanded = true
        let root = NSView(frame: CGRect(x:0,y:0,width:width,height:60))
        root.wantsLayer = true; root.layer?.backgroundColor = NSColor.black.cgColor; root.layer?.cornerRadius = 30
        bubbleView.removeFromSuperview()
        bubbleView.frame = CGRect(x:expandLeft ? width-60 : 0,y:0,width:60,height:60)
        root.addSubview(bubbleView)
        let input = NSView(frame: CGRect(x:expandLeft ? 12 : 60,y:12,width:width-72,height:36))
        input.wantsLayer = true
        input.layer?.cornerRadius = 18
        input.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        input.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        input.layer?.borderWidth = 0.5
        let icon = NSImageView(frame: CGRect(x:12,y:10,width:16,height:16))
        icon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        input.addSubview(icon)
        let field = NSSecureTextField(frame: CGRect(x:36,y:8,width:input.frame.width-48,height:20))
        field.isBezeled = false; field.drawsBackground = false
        field.font = .systemFont(ofSize: 13)
        field.setFrameSize(NSSize(width: input.frame.width-48, height: field.intrinsicContentSize.height))
        field.setFrameOrigin(CGPoint(x: 36, y: (input.bounds.height-field.frame.height)/2))
        field.textColor = .white
        field.placeholderAttributedString = NSAttributedString(string: "粘贴 OpenAI 密钥，回车保存", attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.5)])
        field.setAccessibilityLabel("OpenAI 密钥")
        field.target = self; field.action = #selector(saveInlineKey(_:))
        field.focusRingType = .none
        input.addSubview(field); root.addSubview(input); keyField = field
        bubble.contentView = root
        bubble.setFrame(CGRect(x:x,y:original.minY,width:width,height:60),display:true)
        bubble.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); bubble.makeFirstResponder(field)
    }
    func collapseKeyEntry() {
        guard let frame = collapsedFrame else { return }
        keyField = nil; collapsedFrame = nil
        bubbleView.removeFromSuperview(); bubbleView.frame = CGRect(x:0,y:0,width:60,height:60)
        bubble.contentView = bubbleView; bubble.setFrame(frame,display:true)
        bubbleView.isKeyEntryExpanded = false
    }
    @objc func saveInlineKey(_ sender: NSSecureTextField) {
        do { try Secret.save(sender.stringValue); collapseKeyEntry() }
        catch { alert(error.localizedDescription); bubble.makeKeyAndOrderFront(nil); bubble.makeFirstResponder(sender) }
    }
    @objc func settings() {
        if let p = settingsPanel { p.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); return }
        let p = NSPanel(contentRect:CGRect(x:0,y:0,width:420,height:310),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        p.title = "Lense · 设置"; p.isReleasedWhenClosed = false
        p.contentView = NSHostingView(rootView:SettingsView()); p.center(); settingsPanel = p
        p.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
}
final class BubbleView: NSView {
    weak var owner: AppDelegate?
    var origin = CGPoint.zero
    var moved = false
    var grabOffset = CGPoint.zero
    private let bodyLayer = CALayer()
    private let symbolLayer = CALayer()
    private let ringLayer = CAShapeLayer()
    private let spinnerLayer = CAShapeLayer()
    private let thinkingDot = CALayer()
    private let crossLayer = CAShapeLayer()
    private var hover = false
    private var dragging = false
    private(set) var dockEdge: DockEdge?
    var isCompressed: Bool { dockEdge != nil && !hover && !dragging && !isKeyEntryExpanded && (isThinking || !isOverlayActive) }
    var isKeyEntryExpanded = false { didSet { updateShape() } }
    var isThinking = false {
        didSet {
            setAccessibilityValue(isThinking ? "正在思考" : "就绪")
            updateShape()
        }
    }
    var isOverlayActive = false {
        didSet {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            crossLayer.isHidden = !isOverlayActive; CATransaction.commit()
            setAccessibilityLabel(isOverlayActive ? "Lense 关闭透明画板" : "Lense 圈选屏幕")
            updateShape()
        }
    }
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
    init(owner:AppDelegate) {
        self.owner = owner; super.init(frame:CGRect(x:0,y:0,width:60,height:60))
        wantsLayer = true
        bodyLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(bodyLayer); layer?.addSublayer(symbolLayer)
        thinkingDot.backgroundColor = NSColor.systemBlue.cgColor
        thinkingDot.bounds = CGRect(x:0,y:0,width:4,height:4)
        thinkingDot.cornerRadius = 2; thinkingDot.isHidden = true
        layer?.addSublayer(thinkingDot)
        symbolLayer.bounds = CGRect(x:0,y:0,width:60,height:60)
        for shape in [ringLayer,spinnerLayer,crossLayer] {
            shape.frame = CGRect(x:0,y:0,width:60,height:60)
            shape.fillColor = nil; shape.strokeColor = NSColor.white.cgColor
            shape.lineCap = .round; symbolLayer.addSublayer(shape)
        }
        ringLayer.path = CGPath(ellipseIn:CGRect(x:18,y:18,width:24,height:24),transform:nil)
        ringLayer.lineWidth = 2
        spinnerLayer.name = "loadingRing"
        spinnerLayer.path = ringLayer.path; spinnerLayer.lineWidth = 2.5
        spinnerLayer.strokeEnd = 0.28; spinnerLayer.isHidden = true
        let cross = CGMutablePath()
        cross.move(to:CGPoint(x:26,y:26)); cross.addLine(to:CGPoint(x:34,y:34))
        cross.move(to:CGPoint(x:26,y:34)); cross.addLine(to:CGPoint(x:34,y:26))
        crossLayer.path = cross; crossLayer.lineWidth = 1.5; crossLayer.isHidden = true
        toolTip = "移近展开 · 点击圈选 · 拖动贴边 · ⌃⌥"
        setAccessibilityElement(true); setAccessibilityLabel("Lense 圈选屏幕"); setAccessibilityRole(.button)
        updateShape(animated:false)
    }
    required init?(coder:NSCoder) { fatalError() }
    override func accessibilityPerformPress() -> Bool { owner?.toggle(); return true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil))
    }
    override func mouseEntered(with event:NSEvent) { hover = true; updateShape() }
    override func mouseExited(with event:NSEvent) { hover = false; updateShape() }
    override func layout() { super.layout(); updateShape(animated:false) }
    func dock(to edge:DockEdge) { dockEdge = edge; updateShape() }
    private func updateShape(animated:Bool = true) {
        let target = isCompressed ? dockEdge!.body(in:bounds) : CGRect(x:bounds.midX-25,y:bounds.midY-25,width:50,height:50)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let showDot = isThinking && isCompressed
        let showRing = isThinking && !isCompressed
        CATransaction.begin(); CATransaction.setDisableActions(true)
        thinkingDot.isHidden = !showDot; spinnerLayer.isHidden = !showRing
        ringLayer.opacity = showRing ? 0.2 : 0.9
        CATransaction.commit()
        if showDot && !reduced {
            if thinkingDot.animation(forKey:"thinking") == nil {
                let pulse = CABasicAnimation(keyPath:"opacity")
                pulse.fromValue = 0.3; pulse.toValue = 1
                pulse.duration = 0.55; pulse.autoreverses = true; pulse.repeatCount = .infinity
                pulse.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
                thinkingDot.add(pulse,forKey:"thinking")
            }
        } else { thinkingDot.removeAnimation(forKey:"thinking") }
        if showRing {
            if spinnerLayer.animation(forKey:"loading") == nil {
                let spin = CABasicAnimation(keyPath:"transform.rotation.z")
                spin.fromValue = 0; spin.toValue = 2 * Double.pi
                spin.duration = reduced ? 2 : 0.9; spin.repeatCount = .infinity
                spinnerLayer.add(spin,forKey:"loading")
            }
        } else { spinnerLayer.removeAnimation(forKey:"loading") }
        func change(_ layer:CALayer,_ key:String,_ value:Any) {
            let previous = layer.presentation()?.value(forKeyPath:key) ?? layer.value(forKeyPath:key)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer.setValue(value,forKeyPath:key); CATransaction.commit()
            guard animated, !reduced else { layer.removeAnimation(forKey:key); return }
            let spring = CASpringAnimation(keyPath:key)
            spring.mass = 1; spring.stiffness = 260; spring.damping = 22
            spring.fromValue = previous; spring.toValue = value
            spring.duration = spring.settlingDuration
            layer.add(spring,forKey:key)
        }
        change(bodyLayer,"bounds",NSValue(rect:CGRect(origin:.zero,size:target.size)))
        change(bodyLayer,"position",NSValue(point:CGPoint(x:target.midX,y:target.midY)))
        change(bodyLayer,"cornerRadius",min(target.width,target.height)/2)
        change(symbolLayer,"position",NSValue(point:CGPoint(x:target.midX,y:target.midY)))
        change(symbolLayer,"transform.scale",isCompressed ? 0.32 : 1.0)
        change(symbolLayer,"opacity",isCompressed ? Float(0) : Float(1))
        change(thinkingDot,"position",NSValue(point:CGPoint(x:target.midX,y:target.midY)))
    }
    override func mouseDown(with event:NSEvent) {
        owner?.collapseKeyEntry(); dragging = true; updateShape()
        origin = NSEvent.mouseLocation; moved = false
        if let window { grabOffset = CGPoint(x:origin.x-window.frame.minX,y:origin.y-window.frame.minY) }
    }
    override func mouseDragged(with event:NSEvent) {
        let point = NSEvent.mouseLocation
        if hypot(point.x-origin.x,point.y-origin.y)>3 { moved = true }
        if moved { window?.setFrameOrigin(CGPoint(x:point.x-grabOffset.x,y:point.y-grabOffset.y)) }
    }
    override func mouseUp(with event:NSEvent) {
        dragging = false
        if !moved { updateShape(); owner?.toggle(); return }
        guard let window, let screen = NSScreen.screens.first(where:{$0.frame.contains(NSEvent.mouseLocation)}) else { updateShape(); return }
        let origin = snappedOrigin(frame:window.frame,bounds:screen.visibleFrame)
        window.setFrameOrigin(origin)
        dock(to:DockEdge.nearest(frame:window.frame,bounds:screen.visibleFrame))
        hover = bounds.contains(convert(window.mouseLocationOutsideOfEventStream,from:nil))
        updateShape()
    }
}
final class SelectionView: NSView {
    var start:CGPoint?
    var rect = CGRect.zero {
        didSet { setAccessibilityValue(rect.isEmpty ? "未选择" : "已圈选，回车发送") }
    }
    var selected:((CGRect)->Void)?
    var cancel:(()->Void)?
    override init(frame: NSRect) {
        super.init(frame:frame)
        setAccessibilityElement(true); setAccessibilityRole(.group)
        setAccessibilityLabel("透明画板，拖框后回车发送")
    }
    required init?(coder:NSCoder) { fatalError() }
    override var isFlipped:Bool { true }
    override var acceptsFirstResponder:Bool { true }
    override func resetCursorRects() { addCursorRect(bounds,cursor:.crosshair) }
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
    override func keyDown(with event:NSEvent) {
        if event.keyCode == 53 {
            if !rect.isEmpty || start != nil { rect = .zero; start = nil; needsDisplay = true }
            else { cancel?() }
        }
        else if event.keyCode == 36 || event.keyCode == 76 {
            guard rect.width >= 8, rect.height >= 8 else { return }
            let confirmed = rect; rect = .zero; start = nil; needsDisplay = true
            selected?(confirmed)
        } else { super.keyDown(with:event) }
    }
    override func mouseDown(with event:NSEvent) {
        window?.makeKey(); window?.makeFirstResponder(self)
        start = convert(event.locationInWindow,from:nil); rect = .zero; needsDisplay = true
    }
    override func mouseDragged(with event:NSEvent) { if let start { rect = selectionRect(start,convert(event.locationInWindow,from:nil),bounds:bounds); needsDisplay = true } }
    override func mouseUp(with event:NSEvent) { mouseDragged(with:event); start = nil }
    override func draw(_ dirtyRect:NSRect) {
        drawSelectionCorners(rect)

    }
}
