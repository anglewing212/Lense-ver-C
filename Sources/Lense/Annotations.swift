import Foundation
import CoreGraphics
import NaturalLanguage

struct ArrowMark: Codable, Equatable { let x: Double; let y: Double }
struct TextMark: Codable, Equatable, Hashable {
    enum Kind: String, Codable { case fill, short, long, math, notice }
    let x: Double; let y: Double; let width: Double; let height: Double
    let kind: Kind
    let lines: [String]
    struct Supplement: Codable, Equatable, Hashable {
        enum Kind: String, Codable { case explanation, example, caseStudy = "case_study" }
        let point: Int
        let kind: Kind
        let sentence: String
    }
    let supplements: [Supplement]?
    let questionPrefix: String?
    let blankIndex: Int?
    struct AnswerArea: Codable, Equatable, Hashable {
        let x: Double; let y: Double; let width: Double; let height: Double
    }
    let belowArea: AnswerArea?
    enum CodingKeys: String, CodingKey { case x, y, width, height, kind, lines, supplements; case questionPrefix = "question_prefix"; case blankIndex = "blank_index"; case belowArea = "below_area" }
    init(x:Double,y:Double,width:Double,height:Double,kind:Kind,lines:[String],questionPrefix:String? = nil,supplements:[Supplement]? = nil,blankIndex:Int? = nil,belowArea:AnswerArea? = nil) {
        self.x=x; self.y=y; self.width=width; self.height=height; self.kind=kind; self.lines=lines; self.questionPrefix=questionPrefix; self.supplements=supplements; self.blankIndex=blankIndex; self.belowArea=belowArea
    }
    var text: String {
        let answer = lines.enumerated().map { index, line in
            guard let extra = supplements?.first(where: { $0.point == index+1 }) else { return line }
            return line + " " + extra.sentence
        }.joined(separator: kind == .math ? "\n" : " ")
        guard let prefix = questionPrefix?.trimmingCharacters(in:.whitespacesAndNewlines), !prefix.isEmpty else { return answer }
        if kind == .fill {
            let digits = "0-9０-９零〇一二三四五六七八九十百千万"
            if let range = prefix.range(of:"["+digits+"]+(?:[.．]["+digits+"]+)*",options:.regularExpression) {
                return String(prefix[range]) + (blankIndex.map { "." + String($0) } ?? "") + " " + answer
            }
        }
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
                let citationPattern = #"(?i)https?://|www\.|doi\s*:|\[\s*\d+(?:\s*[,，–—-]\s*\d+)*\s*\]|\[[^\]\n]+\]\([^\n]+\)|[]|【[^】]*(?:†|来源|引用)[^】]*】|(?:references|bibliography|参考文献|引用来源)\s*[:：]"#
                guard box.text.range(of:citationPattern,options:.regularExpression) == nil else {
                    throw fail("答案禁止引用标记、引用编号、参考文献及来源链接；请仅保留解答内容后重试。")
                }
                if let prefix = box.questionPrefix {
                    let digits = CharacterSet.decimalDigits.union(CharacterSet(charactersIn:"零〇一二三四五六七八九十百千万"))
                    let allowed = digits.union(CharacterSet(charactersIn:" .、．()（）:：-—第题"))
                    guard prefix.count <= 24, prefix.unicodeScalars.contains(where:digits.contains),
                          prefix.unicodeScalars.allSatisfy(allowed.contains) else { throw fail("题号只可填写原题的数字前缀；没有数字题号时请传 null。") }
                }
                if let index = box.blankIndex {
                    guard box.kind == .fill && index > 0 else { throw fail("blank_index 仅用于填空，按该题空格阅读顺序从 1 编号；其他题型传 null。") }
                }
                if let area = box.belowArea {
                    guard box.kind == .fill, coordinate(area.x), coordinate(area.y), coordinate(area.width), coordinate(area.height),
                          area.width > 0, area.height > 0, area.x+area.width <= 1000.001, area.y+area.height <= 1000.001,
                          area.y >= box.y+box.height-0.001,
                          area.x <= box.x+0.001, area.x+area.width >= box.x else {
                        throw fail("below_area 只用于填空，须是作答区正下方不遮挡题干的真实空白矩形，坐标在截图内；没有可用留白则传 null。")
                    }
                }
                let limit: Int
                switch box.kind { case .fill: limit = 1; case .short: limit = 5; case .long: limit = 10; case .math: limit = 80; case .notice: limit = 3 }
                guard box.lines.count <= limit else { throw fail("答案超过该题型的句数或步骤上限。") }
                func sentenceCount(_ text:String) -> Int {
                    let tokenizer = NLTokenizer(unit:.sentence)
                    tokenizer.string = text
                    var count = 0
                    tokenizer.enumerateTokens(in:text.startIndex..<text.endIndex) { _,_ in count += 1; return true }
                    return max(1,count)
                }
                if box.kind == .short || box.kind == .long {
                    guard box.lines.allSatisfy({ sentenceCount($0) == 1 }) else {
                        throw fail("每个要点须单独放在 lines 的一项内，且只有一句正文；短文最多五个、长文最多十个要点。")
                    }
                }
                let extras = box.supplements ?? []
                guard extras.count <= box.lines.count, Set(extras.map { $0.point }).count == extras.count,
                      extras.allSatisfy({ (1...box.lines.count).contains($0.point) &&
                          !$0.sentence.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && sentenceCount($0.sentence) == 1 }) else {
                    throw fail("每个要点最多一句补充，point 从 1 开始且不可重复；补充只选 explanation、example 或 case_study 一种用途，也可不加。")
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
