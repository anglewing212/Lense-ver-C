import AppKit

final class AnnotationBoard: NSView {
    let selection: CGRect
    var newSelection: ((CGRect)->Void)?
    private var dragStart: CGPoint?
    private var dragRect = CGRect.zero
    private var isDragging = false
    private var pendingSelection: CGRect?
    var marks = BoardMarks()
    private var currentSources: [URL] = []
    private var statusFailed = false
    private var layoutWarning: String?
    private var hasDraft: Bool { isDragging || pendingSelection != nil }
    let statusLabel = NSTextField(labelWithString:"正在识别题目并标注答案…")
    let retryButton = NSButton(title:"重试",target:nil,action:nil)
    let reselectButton = NSButton(title:"重新圈选",target:nil,action:nil)
    let closeButton = NSButton(title:"关闭画板 ⌃⌥",target:nil,action:nil)
    let sourcesView = NSTextView()
    var retry: (()->Void)?
    var reselect: (()->Void)?
    var close: (()->Void)?
    private var boxes: [NSScrollView] = []
    private var boxMarks: [ObjectIdentifier:TextMark] = [:]
    private var manualFrames: [TextMark:CGRect] = [:]
    private var movingMark: TextMark?
    private var movingOrigin = CGPoint.zero
    private var movedTextBox = false
    var pasteboard = NSPasteboard.general
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(frame:CGRect, selection:CGRect) {
        self.selection = selection
        super.init(frame:frame)
        for button in [retryButton,reselectButton,closeButton] {
            button.bezelStyle = .rounded; button.isBordered = true
            button.target = self; addSubview(button)
        }
        retryButton.action = #selector(retryClicked)
        reselectButton.action = #selector(reselectClicked)
        closeButton.action = #selector(closeClicked)
        retryButton.isHidden = true; reselectButton.isHidden = true; closeButton.isHidden = true
        statusLabel.isHidden = true
        statusLabel.font = .systemFont(ofSize:13,weight:.medium)
        statusLabel.textColor = .white; statusLabel.backgroundColor = .black.withAlphaComponent(0.8)
        statusLabel.drawsBackground = true; statusLabel.maximumNumberOfLines = 2
        addSubview(statusLabel)
        sourcesView.isEditable = false; sourcesView.isSelectable = true
        sourcesView.drawsBackground = false; sourcesView.backgroundColor = .clear
        sourcesView.textContainerInset = NSSize(width:8,height:4)
        sourcesView.isHidden = true; addSubview(sourcesView)
        setAccessibilityLabel("原位解答画板")
    }
    required init?(coder:NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        let available = max(100,bounds.width-360)
        statusLabel.frame = CGRect(x:20,y:bounds.height-72,width:min(640,available),height:44)
        closeButton.frame = CGRect(x:bounds.width-150,y:bounds.height-64,width:130,height:32)
        reselectButton.frame = CGRect(x:bounds.width-260,y:bounds.height-64,width:100,height:32)
        retryButton.frame = CGRect(x:bounds.width-340,y:bounds.height-64,width:70,height:32)
        sourcesView.frame = CGRect(x:20,y:bounds.height-76,width:min(700,bounds.width-40),height:56)
    }
    @objc private func retryClicked() { retry?() }
    @objc private func reselectClicked() { reselect?() }
    @objc private func closeClicked() { close?() }
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
    override func keyDown(with event:NSEvent) {
        if event.keyCode == 53 {
            if hasDraft {
                dragStart = nil; pendingSelection = nil; isDragging = false; dragRect = .zero
                updateVisibility(); needsDisplay = true
            } else { close?() }
        }
        else if event.keyCode == 36 || event.keyCode == 76 {
            guard let rect = pendingSelection else { return }
            pendingSelection = nil; dragRect = .zero; needsDisplay = true
            updateVisibility()
            newSelection?(rect)
        } else { super.keyDown(with:event) }
    }
    func show(_ marks:BoardMarks, sources:[URL]) {
        self.marks = marks; currentSources = sources; layoutWarning = nil
        boxes.forEach { $0.removeFromSuperview() }; boxes.removeAll(); boxMarks.removeAll()
        manualFrames = manualFrames.filter { marks.boxes.contains($0.key) }
        for mark in marks.boxes {
            let origin = markPoint(x:mark.x,y:mark.y,selection:selection)
            let font = NSFont(name:"TimesNewRomanPSMT",size:10) ?? NSFont(name:"Times New Roman",size:10) ?? NSFont(name:"Times-Roman",size:10)!
            let isFill = mark.kind == .fill
            let answerText = isFill ? mark.text.components(separatedBy:.newlines).joined(separator:" ") : mark.text
            let naturalWidth = ceil((answerText as NSString).size(withAttributes:[.font:font]).width) + 16
            var width = min(isFill ? naturalWidth : max(mark.width/1000*selection.width,200),bounds.width-16)
            var textHeight = isFill ? ceil(font.ascender-font.descender+font.leading)+16 : (answerText as NSString).boundingRect(with:NSSize(width:width-20,height:CGFloat.greatestFiniteMagnitude),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:font]).height + 20
            let height = isFill ? textHeight : min(max(mark.height/1000*selection.height,textHeight,32),min(480,bounds.height-32))
            var frame = CGRect(x:max(8,min(origin.x,bounds.width-width-8)),y:max(8,min(origin.y,bounds.height-height-8)),width:width,height:height)
            var occupied = boxes.map { $0.frame }
            if !sources.isEmpty {
                occupied.append(CGRect(x:20,y:bounds.height-76,width:min(700,bounds.width-40),height:56))
            }
            let blankArea = CGRect(origin:origin,size:CGSize(width:mark.width/1000*selection.width,height:mark.height/1000*selection.height))
            let fitsBlank = isFill && blankArea.contains(frame) && selection.contains(frame) &&
                naturalWidth <= frame.width && !occupied.contains { $0.intersects(frame) }
            var fitsBelow = false
            if isFill && !fitsBlank, let area = mark.belowArea {
                let available = CGRect(origin:markPoint(x:area.x,y:area.y,selection:selection),
                                       size:CGSize(width:area.width/1000*selection.width,height:area.height/1000*selection.height))
                let candidate = CGRect(x:origin.x,y:available.minY,width:naturalWidth,height:textHeight)
                if available.contains(candidate) && bounds.insetBy(dx:8,dy:8).contains(candidate) &&
                    !occupied.contains(where: { $0.insetBy(dx:-6,dy:-6).intersects(candidate) }) {
                    frame = candidate; width = frame.width; fitsBelow = true
                }
            }
            if manualFrames[mark] == nil && !fitsBlank && !fitsBelow {
                guard let free = freeAnswerRect(size:CGSize(width:isFill ? naturalWidth : width,height:textHeight),near:origin,
                                               bounds:bounds,protected:selection,occupied:occupied,
                                               minimum:CGSize(width:isFill ? min(naturalWidth,40) : min(width,60),
                                                              height:isFill ? textHeight : min(textHeight,ceil(font.ascender-font.descender+font.leading)+16))) else {
                    layoutWarning = "选区外没有足够的作答空间，请缩小选区或移动题目后重试。"
                    continue
                }
                frame = free; width = frame.width
                if !isFill {
                    textHeight = (answerText as NSString).boundingRect(with:NSSize(width:width-20,height:CGFloat.greatestFiniteMagnitude),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:font]).height+20
                }
            }
            if let saved = manualFrames[mark] {
                frame = saved
                frame.origin = clampedBoxOrigin(saved.origin,size:saved.size,bounds:bounds)
                width = frame.width
                if !isFill {
                    textHeight = (answerText as NSString).boundingRect(with:NSSize(width:width-20,height:CGFloat.greatestFiniteMagnitude),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:font]).height+20
                }
            }
            let visibleHeight = frame.height
            let scroll = NSScrollView(frame:frame)
            scroll.borderType = .noBorder
            scroll.hasVerticalScroller = !isFill && textHeight > visibleHeight
            scroll.hasHorizontalScroller = isFill && naturalWidth > width
            scroll.autohidesScrollers = true
            scroll.drawsBackground = false; scroll.backgroundColor = .clear
            scroll.contentView.drawsBackground = false
            let text = NSTextView(frame:CGRect(origin:.zero,size:NSSize(width:width,height:visibleHeight)))
            text.isEditable = false; text.isSelectable = true
            text.font = font; text.textColor = .darkGray; text.drawsBackground = false; text.backgroundColor = .clear
            text.textContainerInset = NSSize(width:8,height:8)
            text.textContainer?.lineFragmentPadding = 0
            text.textContainer?.widthTracksTextView = !isFill
            if isFill {
                text.textContainer?.size = NSSize(width:max(naturalWidth,width),height:visibleHeight)
                text.textContainer?.maximumNumberOfLines = 1
                text.textContainer?.lineBreakMode = .byClipping
            }
            text.isHorizontallyResizable = isFill; text.isVerticallyResizable = !isFill
            text.minSize = NSSize(width:0,height:visibleHeight); text.maxSize = NSSize(width:isFill ? max(naturalWidth,width) : width,height:isFill ? visibleHeight : CGFloat.greatestFiniteMagnitude)
            text.string = answerText; text.setAccessibilityLabel("\(mark.kind.rawValue) 答案")
            scroll.documentView = text; text.sizeToFit()
            addSubview(scroll,positioned:.below,relativeTo:statusLabel); boxes.append(scroll)
            boxMarks[ObjectIdentifier(scroll)] = mark
        }
        let links = NSMutableAttributedString(string:"")
        for (index,url) in sources.enumerated() {
            links.append(NSAttributedString(string:"[\(index+1)] \(url.host ?? "来源")  ",attributes:[.link:url,.font:NSFont.systemFont(ofSize:12)]))
        }
        sourcesView.textStorage?.setAttributedString(links)
        updateVisibility(); needsDisplay = true
    }
    func setStatus(_ text:String, failed:Bool = false) {
        statusLabel.stringValue = text.isEmpty ? (layoutWarning ?? "") : text; statusFailed = failed
        updateVisibility()
    }
    private func updateVisibility() {
        boxes.forEach { $0.isHidden = hasDraft }
        sourcesView.isHidden = hasDraft || currentSources.isEmpty
        if !statusFailed, let warning = layoutWarning { statusLabel.stringValue = warning }
        statusLabel.isHidden = hasDraft || (!statusFailed && layoutWarning == nil)
        retryButton.isHidden = hasDraft || !statusFailed
        reselectButton.isHidden = hasDraft || !statusFailed
    }
    override func hitTest(_ point:NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if hit is NSButton || hit.isDescendant(of:sourcesView) { return hit }
        return self
    }
    override func mouseDown(with event:NSEvent) {
        window?.makeKey(); window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow,from:nil)
        dragStart = point; isDragging = false; movingMark = nil; movedTextBox = false
        if let box = boxes.last(where:{ !$0.isHidden && $0.frame.contains(point) }), let mark = boxMarks[ObjectIdentifier(box)] {
            movingMark = mark; movingOrigin = box.frame.origin
        }
    }
    override func mouseDragged(with event:NSEvent) {
        guard let start = dragStart else { return }
        let point = convert(event.locationInWindow,from:nil)
        if let mark = movingMark {
            guard hypot(point.x-start.x,point.y-start.y)>3,
                  let box = boxes.first(where:{boxMarks[ObjectIdentifier($0)] == mark}) else { return }
            let origin = clampedBoxOrigin(CGPoint(x:movingOrigin.x+point.x-start.x,y:movingOrigin.y+point.y-start.y),size:box.frame.size,bounds:bounds)
            movedTextBox = true
            let candidate = CGRect(origin:origin,size:box.frame.size)
            guard mark.kind == .fill || !candidate.intersects(selection) else { return }
            box.setFrameOrigin(origin); manualFrames[mark] = box.frame
            return
        }
        guard isDragging || hypot(point.x-start.x,point.y-start.y) > 4 else { return }
        if !isDragging {
            isDragging = true; pendingSelection = nil
            updateVisibility()
        }
        dragRect = selectionRect(start,point,bounds:bounds); needsDisplay = true
    }
    override func mouseUp(with event:NSEvent) {
        mouseDragged(with:event)
        if let mark = movingMark {
            if !movedTextBox {
                pasteboard.clearContents()
                pasteboard.setString(mark.text,forType:.string)
            }
            movingMark = nil; dragStart = nil; return
        }
        if isDragging {
            pendingSelection = dragRect.width >= 8 && dragRect.height >= 8 ? dragRect : nil
            if pendingSelection == nil { dragRect = .zero }
        }
        dragStart = nil; isDragging = false; updateVisibility(); needsDisplay = true
    }
    override func scrollWheel(with event:NSEvent) {
        let point = convert(event.locationInWindow,from:nil)
        if let box = boxes.last(where:{$0.frame.contains(point)}) { box.scrollWheel(with:event) }
    }
    override func draw(_ dirtyRect:NSRect) {
        if hasDraft { drawSelectionCorners(dragRect); return }
        for arrow in marks.arrows {
            let tip = markPoint(x:arrow.x,y:arrow.y,selection:selection)
            let path = NSBezierPath()
            path.move(to:CGPoint(x:tip.x-30,y:tip.y)); path.line(to:tip)
            path.move(to:CGPoint(x:tip.x-8,y:tip.y-6)); path.line(to:tip); path.line(to:CGPoint(x:tip.x-8,y:tip.y+6))
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            NSColor.darkGray.setStroke()
            path.lineWidth = 1 / max(window?.backingScaleFactor ?? 1,1)
            path.stroke()
        }
    }
}
