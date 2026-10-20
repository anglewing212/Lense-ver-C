import AppKit

@main struct AppLifecycleCheck {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let owner = AppDelegate()
            owner.bubble = owner.panel(frame:CGRect(x:0,y:0,width:60,height:60))
            owner.bubbleView = BubbleView(owner:owner)
            owner.bubble.contentView = owner.bubbleView
            owner.session.isVisible = true; owner.session.beginRound()
            let board = AnnotationBoard(frame:CGRect(x:0,y:0,width:600,height:400),selection:CGRect(x:20,y:30,width:500,height:300))
            let panel = owner.panel(frame:board.bounds)
            panel.contentView = board; owner.overlays = [panel]
            var requestCount = 0
            owner.runAgent(png:Data([1]),board:board,send:{ request in
                requestCount += 1
                try await Task.sleep(nanoseconds:150_000_000)
                let output: [[String:Any]] = requestCount == 1 ? [["type":"function_call","call_id":"a","name":"place_arrows","arguments":"{\"arrows\":[{\"x\":100,\"y\":200}]}" ]] : []
                return (try JSONSerialization.data(withJSONObject:["status":"completed","output":output]),HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
            })
            let token = owner.session.generation
            owner.dismiss()
            assert(!owner.session.isVisible && owner.session.isThinking && owner.task?.isCancelled == false)
            assert(owner.session.generation == token && owner.bubbleView.isThinking)
            await owner.task?.value
            assert(requestCount == 2 && board.marks.arrows.count == 1)
            assert(!owner.session.isThinking && !owner.bubbleView.isThinking && !panel.isVisible && !owner.session.isVisible)
            assert(owner.overlays.first?.contentView === board)
            owner.toggleOverlay()
            assert(owner.session.isVisible && panel.isVisible)
            assert(panel.level == .floating)
            let savedMarks = board.marks.arrows
            let foreignOverlay: [String:Any] = [kCGWindowOwnerPID as String:999999,
                kCGWindowLayer as String:1000, kCGWindowBounds as String:NSScreen.main!.frame.dictionaryRepresentation]
            owner.checkExternalOverlays(windows:[foreignOverlay])
            assert(owner.yieldsToExternalOverlay && panel.ignoresMouseEvents && owner.bubble.ignoresMouseEvents)
            assert(owner.session.isVisible && panel.isVisible && board.marks.arrows == savedMarks)
            owner.checkExternalOverlays(windows:[])
            assert(!owner.yieldsToExternalOverlay && !panel.ignoresMouseEvents && !owner.bubble.ignoresMouseEvents)
            assert(owner.session.isVisible && board.marks.arrows == savedMarks)
            owner.checkExternalOverlays(windows:[foreignOverlay]); owner.dismiss()
            owner.checkExternalOverlays(windows:[])
            assert(!owner.session.isVisible && !owner.yieldsToExternalOverlay)
            owner.toggleOverlay()
            print("Passed: external overlays get input priority without closing canvas or clearing answers; ending them restores interaction and never reopens a dismissed canvas")
            @MainActor func mouse(_ type:NSEvent.EventType,_ x:CGFloat,_ y:CGFloat) -> NSEvent {
                NSEvent.mouseEvent(with:type,location:CGPoint(x:x,y:y),modifierFlags:[],timestamp:0,
                                   windowNumber:panel.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
            }
            let enter = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,
                                         windowNumber:panel.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!
            owner.bubbleView.isOverlayActive = false
            owner.bubbleView.dock(to:.right)
            assert(owner.bubbleView.isCompressed)
            owner.bubbleView.mouseEntered(with:mouse(.mouseMoved,0,0))
            assert(!owner.bubbleView.isCompressed)
            owner.bubbleView.mouseExited(with:mouse(.mouseMoved,0,0))
            assert(owner.bubbleView.isCompressed)
            owner.bubbleView.isOverlayActive = true
            assert(!owner.bubbleView.isCompressed)
            owner.bubbleView.isThinking = true
            assert(owner.bubbleView.isCompressed)
            owner.bubbleView.mouseEntered(with:mouse(.mouseMoved,0,0))
            assert(!owner.bubbleView.isCompressed)
            let thinkingDot = owner.bubbleView.layer!.sublayers!.last!
            assert(thinkingDot.isHidden && thinkingDot.backgroundColor == NSColor.systemBlue.cgColor)
            let symbol = owner.bubbleView.layer!.sublayers![1]
            let ring = symbol.sublayers!.first { $0.name == "loadingRing" }!
            assert(!ring.isHidden && ring.animation(forKey:"loading") != nil)
            owner.bubbleView.mouseExited(with:mouse(.mouseMoved,0,0))
            assert(owner.bubbleView.isCompressed && owner.bubbleView.isThinking && !thinkingDot.isHidden)
            assert(ring.isHidden && ring.animation(forKey:"loading") == nil)
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { assert(thinkingDot.animation(forKey:"thinking") != nil) }
            owner.bubbleView.isThinking = false
            assert(thinkingDot.isHidden && ring.isHidden && !owner.bubbleView.isCompressed)
            owner.bubbleView.mouseExited(with:mouse(.mouseMoved,0,0))
            print("Passed: thinking uses rotating ring when expanded and blinking blue dot when compact, neither remains after completion")
            owner.bubbleView.isOverlayActive = false
            owner.bubbleView.isKeyEntryExpanded = true
            assert(!owner.bubbleView.isCompressed)
            owner.bubbleView.isKeyEntryExpanded = false
            assert(owner.bubbleView.isCompressed)
            print("Passed: edge morph restores circle for hover, canvas and key entry, then compresses again")
            owner.bubbleView.isOverlayActive = true
            var sends = 0
            board.newSelection = { _ in sends += 1 }
            board.mouseDown(with:mouse(.leftMouseDown,30,40))
            board.mouseDragged(with:mouse(.leftMouseDragged,200,160))
            board.mouseUp(with:mouse(.leftMouseUp,200,160))
            assert(sends == 0 && board.marks.arrows.count == 1)
            let escape = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,
                                          windowNumber:panel.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53)!
            var closed = false
            board.close = { closed = true }
            board.keyDown(with:escape)
            assert(!closed && board.marks.arrows.count == 1)
            board.keyDown(with:enter); assert(sends == 0)
            board.mouseDown(with:mouse(.leftMouseDown,30,40))
            board.mouseUp(with:mouse(.leftMouseUp,200,160))
            board.keyDown(with:enter); assert(sends == 1)
            board.keyDown(with:enter); assert(sends == 1)
            owner.dismiss(); owner.toggleOverlay()
            board.mouseDown(with:mouse(.leftMouseDown,40,50))
            board.mouseUp(with:mouse(.leftMouseUp,220,180))
            assert(sends == 1)
            board.keyDown(with:escape)
            var fillMarks = BoardMarks()
            fillMarks.boxes = [TextMark(x:100,y:100,width:10,height:50,kind:.fill,lines:["A complete single line answer"],supplements:[.init(point:1,kind:.explanation,sentence:"A useful clarification.")])]
            board.show(fillMarks,sources:[])
            let fillScroll = board.subviews.compactMap { $0 as? NSScrollView }.first!
            let fillText = fillScroll.documentView as! NSTextView
            assert(fillText.textColor == NSColor.darkGray)
            assert(fillText.font?.fontName == "TimesNewRomanPSMT" && fillText.font?.pointSize == 10)
            let requiredWidth = ceil((fillText.string as NSString).size(withAttributes:[.font:fillText.font!]).width)+6
            assert(fillScroll.frame.width >= requiredWidth && fillText.textContainer?.maximumNumberOfLines == 1)
            assert(board.selection.contains(fillScroll.frame))
            owner.checkExternalOverlays(windows:[])
            owner.handleShortcut(.command)
            assert(board.showsBoxOutlines && fillScroll.layer?.borderWidth == 1)
            owner.handleShortcut([])
            assert(!board.showsBoxOutlines && fillScroll.layer?.borderWidth == 0)
            owner.handleShortcut(.command)
            let outlined = fillScroll
            assert(outlined.layer?.borderWidth == 1)
            owner.dismiss()
            assert(!board.showsBoxOutlines && outlined.layer?.borderWidth == 0)
            owner.handleShortcut(.command)
            assert(!board.showsBoxOutlines)
            owner.toggleOverlay(); owner.handleShortcut([])
            print("Passed: holding Command reveals textbox outlines, release and hiding remove them, new answer updates retain held-key outlines")
            let currentFillScroll = board.subviews.compactMap { $0 as? NSScrollView }.first!
            let currentFillText = currentFillScroll.documentView as! NSTextView
            let originalContent = currentFillText.string
            let initialFrame = fillScroll.frame
            board.pasteboard = NSPasteboard.withUniqueName()
            let textPoint = CGPoint(x:initialFrame.midX,y:initialFrame.midY)
            let startY = board.bounds.height-textPoint.y
            board.mouseDown(with:mouse(.leftMouseDown,textPoint.x,startY))
            board.mouseUp(with:mouse(.leftMouseUp,textPoint.x,startY))
            assert(board.pasteboard.string(forType:.string) == fillMarks.boxes[0].text)
            board.pasteboard.setString("unchanged",forType:.string)
            board.mouseDown(with:mouse(.leftMouseDown,textPoint.x,startY))
            board.mouseUp(with:mouse(.leftMouseUp,textPoint.x+70,startY))
            assert(board.pasteboard.string(forType:.string) == "unchanged")
            assert(board.selection.contains(fillScroll.frame))
            assert(fillScroll.frame.origin != initialFrame.origin && fillText.string == originalContent)
            assert(board.bounds.contains(fillScroll.frame) && sends == 1)
            let safeFrame = fillScroll.frame
            board.mouseDown(with:mouse(.leftMouseDown,safeFrame.midX,board.bounds.height-safeFrame.midY))
            board.mouseUp(with:mouse(.leftMouseUp,safeFrame.midX,board.bounds.height-board.selection.midY))
            assert(board.selection.intersects(fillScroll.frame))
            let movedFrame = fillScroll.frame
            board.show(fillMarks,sources:[])
            let restoredScroll = board.subviews.compactMap { $0 as? NSScrollView }.first!
            assert(restoredScroll.frame == movedFrame)
            assert((restoredScroll.documentView as! NSTextView).string == originalContent)
            print("Passed: textbox dragging keeps answer content, stays on canvas, preserves its position across updates and never submits a new question")
            let inlineBoard = AnnotationBoard(frame:CGRect(x:0,y:0,width:1000,height:800),selection:CGRect(x:200,y:180,width:600,height:400))
            var blanks = BoardMarks()
            blanks.boxes = [TextMark(x:100,y:100,width:500,height:100,kind:.fill,lines:["Paris"],questionPrefix:"1.",blankIndex:1),
                            TextMark(x:100,y:300,width:500,height:100,kind:.fill,lines:["London"],questionPrefix:"1.",blankIndex:2)]
            inlineBoard.showsBoxOutlines = true
            inlineBoard.show(blanks,sources:[])
            let inlineBoxes = inlineBoard.subviews.compactMap { $0 as? NSScrollView }
            assert(inlineBoxes.count == 2 && inlineBoxes.allSatisfy { inlineBoard.selection.contains($0.frame) && $0.layer?.borderWidth == 1 })
            assert((inlineBoxes[0].documentView as! NSTextView).string == "1.1 Paris")
            assert((inlineBoxes[1].documentView as! NSTextView).string == "1.2 London")
            print("Passed: numbered fill answers occupy actual blank areas, ordered independently per question")
            var belowMarks = BoardMarks()
            let belowArea = TextMark.AnswerArea(x:100,y:200,width:600,height:120)
            belowMarks.boxes = [TextMark(x:100,y:100,width:10,height:50,kind:.fill,lines:["Paris"],questionPrefix:"1.",blankIndex:1,belowArea:belowArea)]
            inlineBoard.show(belowMarks,sources:[])
            let belowBox = inlineBoard.subviews.compactMap { $0 as? NSScrollView }.first!
            assert(belowBox.frame.minX == 260 && belowBox.frame.minY == 260)
            assert(inlineBoard.selection.contains(belowBox.frame))
            belowMarks.boxes.append(TextMark(x:100,y:100,width:10,height:50,kind:.fill,lines:["London"],questionPrefix:"1.",blankIndex:2,belowArea:belowArea))
            inlineBoard.show(belowMarks,sources:[])
            let orderedBoxes = inlineBoard.subviews.compactMap { $0 as? NSScrollView }
            assert(orderedBoxes.count == 1 && !inlineBoard.statusLabel.isHidden)
            belowMarks.boxes = [TextMark(x:100,y:100,width:10,height:50,kind:.fill,lines:["Paris"],belowArea:.init(x:100,y:200,width:10,height:10))]
            inlineBoard.show(belowMarks,sources:[])
            assert(!inlineBoard.subviews.contains { $0 is NSScrollView } && !inlineBoard.statusLabel.isHidden)
            print("Passed: fill placement tries blank, then full answer directly below, never outside selection; unavailable nearby space shows a warning")
            belowMarks.boxes = [TextMark(x:100,y:900,width:10,height:100,kind:.fill,lines:["Paris"])]
            inlineBoard.show(belowMarks,sources:[])
            assert(!inlineBoard.subviews.contains { $0 is NSScrollView })
            var multiple = BoardMarks()
            multiple.boxes = [TextMark(x:100,y:100,width:500,height:500,kind:.short,lines:["An answer that needs more room."]),
                              TextMark(x:200,y:200,width:10,height:10,kind:.math,lines:["2x + 3 = 11","x = 4"])]
            let layoutBoard = AnnotationBoard(frame:CGRect(x:0,y:0,width:1000,height:800),selection:CGRect(x:200,y:180,width:600,height:400))
            layoutBoard.show(multiple,sources:[])
            let relocated = layoutBoard.subviews.compactMap { $0 as? NSScrollView }
            assert(relocated.count == 2)
            assert(relocated.allSatisfy { !layoutBoard.selection.intersects($0.frame) })
            assert(!relocated[0].frame.intersects(relocated[1].frame))
            let fullBoard = AnnotationBoard(frame:CGRect(x:0,y:0,width:600,height:400),selection:CGRect(x:0,y:0,width:600,height:400))
            fullBoard.show(multiple,sources:[]); fullBoard.setStatus("")
            assert(!fullBoard.statusLabel.isHidden)
            assert(!fullBoard.subviews.contains { $0 is NSScrollView })
            print("Passed: actual fill/short/math layouts move outside questions, avoid each other, and preserve no-space feedback")
            board.mouseDown(with:mouse(.leftMouseDown,30,40))
            board.mouseUp(with:mouse(.leftMouseUp,200,160))
            assert(restoredScroll.isHidden)
            board.keyDown(with:escape)
            assert(!closed && !restoredScroll.isHidden && board.marks.boxes.count == 1)
            print("Passed: Esc restores existing answers; fill answers use Times New Roman 10 and full single-line width")
            board.mouseDown(with:mouse(.leftMouseDown,40,50))
            board.mouseUp(with:mouse(.leftMouseUp,220,180))
            board.keyDown(with:enter); assert(sends == 2)
            let selection = SelectionView(frame:board.bounds)
            selection.selected = { _ in sends += 1 }
            panel.contentView = selection
            selection.mouseDown(with:mouse(.leftMouseDown,30,40))
            selection.mouseUp(with:mouse(.leftMouseUp,200,160))
            assert(sends == 2 && !selection.rect.isEmpty)
            selection.keyDown(with:enter); assert(sends == 3)
            selection.keyDown(with:enter); assert(sends == 3)
            let pixels = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:600,pixelsHigh:400,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            pixels.bitmapData!.initialize(repeating:0,count:pixels.bytesPerRow*pixels.pixelsHigh)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:pixels)
            selection.draw(selection.bounds)
            NSGraphicsContext.restoreGraphicsState()
            assert(pixels.colorAt(x:300,y:200)!.alphaComponent == 0)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:pixels)
            drawSelectionCorners(CGRect(x:100,y:100,width:200,height:100))
            NSGraphicsContext.restoreGraphicsState()
            let cornerRow = pixels.pixelsHigh-1-100
            assert(pixels.colorAt(x:200,y:cornerRow)!.alphaComponent == 0)
            let dot = pixels.colorAt(x:100,y:cornerRow)!.usingColorSpace(.deviceRGB)!
            assert(abs(dot.alphaComponent-0.5) < 0.02)
            assert(abs(dot.redComponent-dot.greenComponent) < 0.02 && abs(dot.greenComponent-dot.blueComponent) < 0.02)
            print("Passed: gray corner dots have 50% transparency with no connecting lines")
            print("Passed: reopen and drag again; mouse release never sends; Enter sends exactly once; blank canvas remains transparent")
            owner.session.beginRound()
            owner.bubbleView.isThinking = true
            owner.clearForNewSelection()
            assert(owner.task == nil && !owner.session.isThinking && !owner.bubbleView.isThinking)
            print("Passed: actual app hides without cancellation, stores background answer, stops spinner, and cancels only for a new selection")
            owner.dismiss(); owner.toggleOverlay()
            try? await Task.sleep(nanoseconds:250_000_000)
            assert(owner.session.isVisible && panel.isVisible && panel.alphaValue > 0.99)
            owner.dismiss()
            try? await Task.sleep(nanoseconds:250_000_000)
            assert(!owner.session.isVisible && !panel.isVisible)
            print("Passed: rapid fade reversal keeps reopened canvas visible, fade-out completes without stale callbacks")
            owner.bubble.close(); panel.close()
            app.terminate(nil)
        }
        app.run()
    }
}
