import AppKit

final class SampleQuestions: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        NSColor.black.setFill(); CGRect(x:470,y:0,width:bounds.width-470,height:bounds.height).fill()
        let rows: [(String,CGFloat,CGFloat)] = [
            ("画板预览 · 使用示例答案，不连接 AI",24,24),
            ("1. 单选：2 + 2 = ?",80,100),("A. 3",100,140),("B. 4",100,175),
            ("2. 多选：哪些是偶数？",80,240),("A. 2",100,280),("B. 3",100,315),("C. 4",100,350),
            ("3. 填空：法国首都是 ______",480,100),
            ("4. 短文：介绍光合作用",480,230),
            ("5. 长文：解释水循环",480,370),
            ("6. 数学：求解 2x + 3 = 11",80,440)
        ]
        for (text,x,y) in rows { text.draw(at:CGPoint(x:x,y:y),withAttributes:[.font:NSFont.systemFont(ofSize:16),.foregroundColor:x >= 470 ? NSColor.white : NSColor.black]) }
    }
}
@main struct BoardPreview {
    static func main() throws {
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect:CGRect(x:100,y:100,width:980,height:760),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title = "Lense 画板预览"
        let root = SampleQuestions(frame:CGRect(x:0,y:0,width:980,height:760))
        let crop = CGRect(x:60,y:90,width:850,height:600)
        let board = AnnotationBoard(frame:root.bounds,selection:crop)
        var marks = BoardMarks()
        let arrows = [ArrowMark(x:35,y:158),ArrowMark(x:35,y:333),ArrowMark(x:35,y:450)]
        let boxes = [
            TextMark(x:700,y:12,width:160,height:50,kind:.fill,lines:["巴黎"]),
            TextMark(x:500,y:290,width:460,height:150,kind:.short,lines:["植物利用光能，把水和二氧化碳转化成有机物。","这个过程会释放氧气。"]),
            TextMark(x:500,y:525,width:460,height:160,kind:.long,lines:["水受热蒸发后进入大气。","水汽凝结成云，随后以雨或雪落回地面。","地表水和地下水最终流回海洋，形成循环。"]),
            TextMark(x:25,y:650,width:400,height:200,kind:.math,lines:["2x + 3 = 11","两边减去 3：2x = 8","两边除以 2：x = 4","检验：2 × 4 + 3 = 11","答案：x = 4"])
        ]
        marks.arrows = arrows; marks.boxes = boxes
        board.show(marks,sources:[URL(string:"https://example.com")!])
        board.setStatus("预览：箭头与文本框 · 示例数据，未连接 AI")
        board.close = { app.terminate(nil) }
        root.addSubview(board); window.contentView = root
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(board); app.activate(ignoringOtherApps:true)
        app.run(); withExtendedLifetime(window) {}
    }
}
