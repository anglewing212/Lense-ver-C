import Foundation
import CoreGraphics
import NaturalLanguage

struct ArrowMark: Codable, Equatable { let x: Double; let y: Double }
struct TextMark: Codable, Equatable, Hashable {
    enum Kind: String, Codable { case fill, short, long, math, notice }
    let x: Double; let y: Double; let width: Double; let height: Double
    let kind: Kind
    let lines: [String]
    let questionPrefix: String?
    enum CodingKeys: String, CodingKey { case x, y, width, height, kind, lines; case questionPrefix = "question_prefix" }
    init(x:Double,y:Double,width:Double,height:Double,kind:Kind,lines:[String],questionPrefix:String? = nil) {
        self.x=x; self.y=y; self.width=width; self.height=height; self.kind=kind; self.lines=lines; self.questionPrefix=questionPrefix
    }
    var text: String {
        let answer = lines.joined(separator: kind == .math ? "\n" : " ")
        guard let prefix = questionPrefix?.trimmingCharacters(in:.whitespacesAndNewlines), !prefix.isEmpty else { return answer }
        return prefix + " " + answer
    }
}
struct BoardMarks {
    var arrows: [ArrowMark] = []
    var boxes: [TextMark] = []
    var isEmpty: Bool { arrows.isEmpty && boxes.isEmpty }
    mutating func apply(name: String, arguments: String) throws {
        func fail(_ message: String) -> NSError { NSError(domain:"Lense.Tools",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
        func coordinate(_ n: Double) -> Bool { n.isFinite && (0...1000).contains(n) }
        let data = Data(arguments.utf8)
        switch name {
        case "place_arrows":
            struct Input: Decodable { let arrows: [ArrowMark] }
            let input = try JSONDecoder().decode(Input.self,from:data)
            guard !input.arrows.isEmpty, arrows.count + input.arrows.count <= 80,
                  input.arrows.allSatisfy({coordinate($0.x) && coordinate($0.y)}) else { throw fail("箭头位置须在截图的 0–1000 坐标内，最多 80 个。") }
            for mark in input.arrows where !arrows.contains(mark) { arrows.append(mark) }
        case "place_textboxes":
            struct Input: Decodable { let boxes: [TextMark] }
            let input = try JSONDecoder().decode(Input.self,from:data)
            guard !input.boxes.isEmpty, boxes.count + input.boxes.count <= 40 else { throw fail("每张截图最多 40 个文本框。") }
            for box in input.boxes {
                guard coordinate(box.x), coordinate(box.y), coordinate(box.width), coordinate(box.height),
                      box.width > 0, box.height > 0, box.x + box.width <= 1000.001, box.y + box.height <= 1000.001,
                      !box.lines.isEmpty, box.lines.allSatisfy({ !$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }),
                      box.text.count <= 20000 else { throw fail("文本框须在截图范围内，并包含有效答案。") }
                if let prefix = box.questionPrefix {
                    let digits = CharacterSet.decimalDigits.union(CharacterSet(charactersIn:"零〇一二三四五六七八九十百千万"))
                    let allowed = digits.union(CharacterSet(charactersIn:" .、．()（）:：-—第题"))
                    guard prefix.count <= 24, prefix.unicodeScalars.contains(where:digits.contains),
                          prefix.unicodeScalars.allSatisfy(allowed.contains) else { throw fail("题号只可填写原题的数字前缀；没有数字题号时请传 null。") }
                }
                let limit: Int
                switch box.kind { case .fill: limit = 1; case .short: limit = 5; case .long: limit = 10; case .math: limit = 80; case .notice: limit = 3 }
                guard box.lines.count <= limit else { throw fail("答案超过该题型的句数或步骤上限。") }
                if box.kind == .short || box.kind == .long {
                    let sentences = box.lines.reduce(0) { total, line in
                        let tokenizer = NLTokenizer(unit: .sentence)
                        tokenizer.string = line
                        var count = 0
                        tokenizer.enumerateTokens(in: line.startIndex..<line.endIndex) { _,_ in count += 1; return true }
                        return total + max(1,count)
                    }
                    guard sentences <= limit else { throw fail("短文最多五句，长文最多十句，请缩短答案。") }
                }
            }
            for box in input.boxes where !boxes.contains(box) { boxes.append(box) }
        default: throw fail("未知画板工具。只能使用 place_arrows 和 place_textboxes。")
        }
    }
}
func markPoint(x: Double, y: Double, selection: CGRect) -> CGPoint {
    CGPoint(x:selection.minX + x / 1000 * selection.width,y:selection.minY + y / 1000 * selection.height)
}
