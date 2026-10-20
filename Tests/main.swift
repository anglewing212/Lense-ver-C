import Foundation
var permissionRequest = PermissionRequestGate()
assert(permissionRequest.shouldRequest())
assert(!permissionRequest.shouldRequest())
assert(!permissionRequest.shouldRequest())
print("Passed: screen permission is requested at most once per app session")
let bounds = CGRect(x:0,y:0,width:100,height:100)
assert(selectionRect(CGPoint(x:90,y:80),CGPoint(x:-10,y:20),bounds:bounds) == CGRect(x:0,y:20,width:90,height:60))
assert(selectionRect(CGPoint(x:50,y:50),CGPoint(x:50,y:50),bounds:bounds).isEmpty)
let area = CGRect(x:-500,y:100,width:1000,height:800)
assert(snappedOrigin(frame:CGRect(x:-480,y:400,width:60,height:60),bounds:area).x == -500)
assert(snappedOrigin(frame:CGRect(x:410,y:400,width:60,height:60),bounds:area).x == 440)
assert(snappedOrigin(frame:CGRect(x:0,y:110,width:60,height:60),bounds:area).y == 100)
assert(snappedOrigin(frame:CGRect(x:0,y:830,width:60,height:60),bounds:area).y == 840)
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent(".env")
defer { try? FileManager.default.removeItem(at:temporary.deletingLastPathComponent()) }
assert(Secret.read(from:temporary).isEmpty)
try Secret.save("test-placeholder",to:temporary)
assert(Secret.read(from:temporary) == "test-placeholder")
let permissions = try FileManager.default.attributesOfItem(atPath:temporary.path)[.posixPermissions] as? NSNumber
assert(permissions?.intValue == 0o600)
try Secret.save("updated-placeholder",to:temporary)
assert(Secret.read(from:temporary) == "updated-placeholder")
do { try Secret.save("invalid\nkey",to:temporary); fatalError("Expected invalid key rejection") } catch {}
assert(answerModel == "gpt-6-astra")
print("Passed: four-edge snapping, .env save/read/update/permissions, multiline rejection, Astra selection")
var shortcut = OverlayShortcut()
assert(!shortcut.update(control:true,option:false,otherModifiers:false))
assert(shortcut.update(control:true,option:true,otherModifiers:false))
assert(!shortcut.update(control:true,option:true,otherModifiers:false))
assert(!shortcut.update(control:false,option:true,otherModifiers:false))
assert(shortcut.update(control:true,option:true,otherModifiers:false))
assert(!shortcut.update(control:false,option:false,otherModifiers:false))
assert(!shortcut.update(control:true,option:true,otherModifiers:true))
assert(!shortcut.update(control:true,option:true,otherModifiers:false))
print("Passed: Control + Option triggers once per press, either order, extra modifiers ignored")

func arguments(_ root:[String:Any]) throws -> String {
    String(data:try JSONSerialization.data(withJSONObject:root),encoding:.utf8)!
}
func box(_ kind:String, _ lines:[String], x:Double = 100) -> [String:Any] {
    ["x":x,"y":100,"width":300,"height":200,"kind":kind,"lines":lines]
}
var marks = BoardMarks()
try marks.apply(name:"place_arrows",arguments:arguments(["arrows":[["x":120,"y":200],["x":120,"y":500]]]))
assert(marks.arrows.count == 2)
try marks.apply(name:"place_arrows",arguments:arguments(["arrows":[["x":120,"y":200]]]))
assert(marks.arrows.count == 2)
let crop = CGRect(x:50,y:100,width:800,height:400)
assert(markPoint(x:500,y:250,selection:crop) == CGPoint(x:450,y:200))
for kind in ["fill","short","long","math","notice"] {
    try marks.apply(name:"place_textboxes",arguments:arguments(["boxes":[box(kind,["答案。"]) ]]))
}
assert(marks.boxes.count == 5)
let before = marks.boxes.count
for invalid in [box("short",Array(repeating:"一句。",count:6)), box("long",Array(repeating:"一句。",count:11)),
                box("short",["One. Two. Three. Four. Five. Six."]), box("short",["一。二。三。四。五。六。"]),
                box("fill",["a","b"]),box("math",["" ]),box("fill",["答案"],x:900)] {
    do { try marks.apply(name:"place_textboxes",arguments:arguments(["boxes":[invalid]])); fatalError("Expected invalid textbox rejection") } catch {}
}
assert(marks.boxes.count == before)
do { try marks.apply(name:"place_arrows",arguments:"{\"arrows\":[{\"x\":-1,\"y\":0}]}"); fatalError("Expected out-of-range rejection") } catch {}
do { try marks.apply(name:"unknown",arguments:"{}"); fatalError("Expected unknown tool rejection") } catch {}
for (kind, limit) in [("short",5),("long",10)] {
    var answer = box(kind,Array(repeating:"A main point.",count:limit))
    answer["supplements"] = (1...limit).map { ["point":$0,"kind":"example","sentence":"For example, consider a tree."] as [String:Any] }
    var supplemented = BoardMarks()
    try supplemented.apply(name:"place_textboxes",arguments:arguments(["boxes":[answer]]))
    assert(supplemented.boxes[0].text.components(separatedBy:"For example").count == limit+1)
    assert(supplemented.boxes[0].lines.count == limit)
    for invalidExtras: [[String:Any]] in [
        [["point":1,"kind":"example","sentence":"First example. Second example."]],
        [["point":1,"kind":"example","sentence":"一。二。"]],
        [["point":1,"kind":"example","sentence":""]],
        [["point":0,"kind":"example","sentence":"Example."]],
        [["point":limit+1,"kind":"example","sentence":"Example."]],
        [["point":1,"kind":"explanation","sentence":"Explanation."],["point":1,"kind":"example","sentence":"Example."]],
        [["point":1,"kind":"mixed","sentence":"Mixed."]]
    ] {
        answer["supplements"] = invalidExtras
        do { try supplemented.apply(name:"place_textboxes",arguments:arguments(["boxes":[answer]])); fatalError("Expected supplement rejection") } catch {}
        assert(supplemented.boxes.count == 1)
    }
    answer["lines"] = Array(repeating:"A main point.",count:limit+1)
    answer["supplements"] = [] as [[String:Any]]
    do { try supplemented.apply(name:"place_textboxes",arguments:arguments(["boxes":[answer]])); fatalError("Main point limit must remain") } catch {}
}
for kind in ["explanation","example","case_study"] {
    var answer = box("short",["第一点。","第二点。"])
    answer["supplements"] = [["point":2,"kind":kind,"sentence":"这是补充。"]]
    var result = BoardMarks()
    try result.apply(name:"place_textboxes",arguments:arguments(["boxes":[answer]]))
    assert(result.boxes[0].text == "第一点。 第二点。 这是补充。")
}
print("Passed: optional single-purpose supplements render after their point, bypass only main sentence quota, reject duplicates and multiple sentences")

let toolData = try JSONSerialization.data(withJSONObject:drawingTools())
assert(String(data:toolData,encoding:.utf8)!.contains("place_textboxes"))
for citation in ["Answer [1]", "Answer [1, 2]", "See https://example.com", "Answer citeturn0search0", "[Source](https://example.com)", "References: book"] {
    do { try marks.apply(name:"place_textboxes",arguments:arguments(["boxes":[box("short",[citation])]])); fatalError("Expected citation rejection") } catch {}
    var answer = box("short",["Main point."])
    answer["supplements"] = [["point":1,"kind":"example","sentence":citation]]
    do { try marks.apply(name:"place_textboxes",arguments:arguments(["boxes":[answer]])); fatalError("Expected supplementary citation rejection") } catch {}
}
do { _ = try responseOutput(Data("{\"status\":\"incomplete\"}".utf8)); fatalError("Expected incomplete rejection") } catch {}
print("Passed: coordinate conversion, both drawing tools, all six answer modes, sentence limits, validation and sources")

var round = 0
var finalMarks = BoardMarks()
try await annotate(image:Data([1,2,3]),key:"test-only",send:{ request in
    round += 1
    let body = try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
    assert(body["model"] as? String == "gpt-6-astra")
    assert(body["store"] as? Bool == false)
    assert((body["instructions"] as? String)?.contains("禁止 citation") == true)
    assert((body["instructions"] as? String)?.contains("不能混合解释与举例或案例") == true)
    let input = body["input"] as! [[String:Any]]
    var output: [[String:Any]] = []
    if round == 1 {
        output = [["type":"function_call","call_id":"bad","name":"place_arrows","arguments":"{\"arrows\":[{\"x\":-1,\"y\":0}]}" ]]
    } else if round == 2 {
        assert(input.contains { ($0["output"] as? String)?.contains("未放置") == true })
        output = [["type":"function_call","call_id":"a","name":"place_arrows","arguments":"{\"arrows\":[{\"x\":100,\"y\":200}]}" ],
                  ["type":"function_call","call_id":"b","name":"place_textboxes","arguments":try arguments(["boxes":[box("math",["2 + 3 = 5","答案：5"])]])]]
    } else {
        assert(round == 3)
        assert(input.filter { $0["type"] as? String == "function_call_output" }.count == 3)
    }
    let data = try JSONSerialization.data(withJSONObject:["status":"completed","output":output])
    return (data,HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
},update:{ marks,sources in assert(sources.isEmpty); finalMarks = marks })
assert(round == 3 && finalMarks.arrows.count == 1 && finalMarks.boxes.count == 1)
print("Passed: agent tool loop corrects invalid positions, executes both tools, returns outputs and finishes without network")

var session = CanvasSession()
session.isVisible = true; session.beginRound()
let firstRound = session.generation
session.isVisible = false
assert(session.isThinking && session.generation == firstRound)
session.finish(firstRound)
assert(!session.isThinking && !session.isVisible)
session.isVisible = true; session.beginRound()
let secondRound = session.generation
session.finish(firstRound)
assert(session.isThinking && session.generation == secondRound)
session.cancel()
assert(!session.isThinking && session.generation != secondRound)
print("Passed: hidden canvas keeps work, background completion, new round rejects stale work")

let bubbleBounds = CGRect(x:0,y:0,width:60,height:60)
assert(DockEdge.left.body(in:bubbleBounds).minX == 0)
assert(DockEdge.right.body(in:bubbleBounds).maxX == 60)
assert(DockEdge.top.body(in:bubbleBounds).maxY == 60)
assert(DockEdge.bottom.body(in:bubbleBounds).minY == 0)
assert(DockEdge.nearest(frame:CGRect(x:440,y:400,width:60,height:60),bounds:area) == .right)
print("Passed: all four compact shapes stay attached to the matching screen edge")

let layoutBounds = CGRect(x:0,y:0,width:1000,height:800)
let question = CGRect(x:200,y:180,width:600,height:400)
let result1 = freeAnswerRect(size:CGSize(width:180,height:100),near:question.origin,bounds:layoutBounds,protected:question,occupied:[],minimum:CGSize(width:100,height:30))!
assert(layoutBounds.contains(result1) && !result1.intersects(question))
let result2 = freeAnswerRect(size:CGSize(width:180,height:100),near:result1.origin,bounds:layoutBounds,protected:question,occupied:[result1],minimum:CGSize(width:100,height:30))!
assert(!result2.intersects(question) && !result2.intersects(result1))
let compact = freeAnswerRect(size:CGSize(width:600,height:500),near:question.origin,bounds:layoutBounds,protected:question,occupied:[],minimum:CGSize(width:120,height:36))!
assert(!compact.intersects(question) && layoutBounds.contains(compact))
assert(freeAnswerRect(size:CGSize(width:200,height:100),near:.zero,bounds:layoutBounds,protected:layoutBounds,occupied:[],minimum:CGSize(width:100,height:30)) == nil)
assert(freeAnswerRect(size:CGSize(width:200,height:100),near:.zero,bounds:layoutBounds,protected:question,occupied:[layoutBounds],minimum:CGSize(width:100,height:30)) == nil)
for protected in [CGRect(x:0,y:0,width:700,height:800),CGRect(x:300,y:0,width:700,height:800),CGRect(x:0,y:0,width:1000,height:500),CGRect(x:0,y:300,width:1000,height:500)] {
    let placed = freeAnswerRect(size:CGSize(width:160,height:80),near:protected.origin,bounds:layoutBounds,protected:protected,occupied:[],minimum:CGSize(width:100,height:30))!
    assert(layoutBounds.contains(placed) && !placed.intersects(protected))
}
print("Passed: answers relocate outside protected question, avoid other answers, use all four sides, and reject no-space layouts")

let numbered = TextMark(x:0,y:0,width:500,height:200,kind:.short,lines:["The answer."],questionPrefix:"12.")
assert(numbered.text == "12. The answer.")
let unnumbered = TextMark(x:0,y:0,width:500,height:200,kind:.fill,lines:["Paris"])
assert(unnumbered.text == "Paris")
let mathNumbered = TextMark(x:0,y:0,width:500,height:200,kind:.math,lines:["2x = 8","x = 4"],questionPrefix:"（3）")
assert(mathNumbered.text == "（3） 2x = 8\nx = 4")
var prefixMarks = BoardMarks()
let encodedPrefix = String(data:try JSONEncoder().encode(numbered),encoding:.utf8)!
try prefixMarks.apply(name:"place_textboxes",arguments:"{\"boxes\":["+encodedPrefix+"]}")
assert(prefixMarks.boxes.first?.questionPrefix == "12.")
let invalidPrefix = TextMark(x:0,y:0,width:500,height:200,kind:.fill,lines:["Paris"],questionPrefix:"invented")
do {
    let encoded = String(data:try JSONEncoder().encode(invalidPrefix),encoding:.utf8)!
    try prefixMarks.apply(name:"place_textboxes",arguments:"{\"boxes\":["+encoded+"]}")
    fatalError("Expected invalid prefix rejection")
} catch {}
assert(clampedBoxOrigin(CGPoint(x:-20,y:900),size:CGSize(width:100,height:50),bounds:layoutBounds) == CGPoint(x:0,y:750))
print("Passed: supplied prefixes render exactly, absent prefixes stay absent, invalid prefixes reject, box dragging stays inside canvas")

for (prefix, expected) in [("1.","1.2 Paris"),("（3）","3.2 Paris"),("第4题","4.2 Paris"),("12.3.","12.3.2 Paris")] {
    let blank = TextMark(x:0,y:0,width:500,height:200,kind:.fill,lines:["Paris"],questionPrefix:prefix,blankIndex:2)
    assert(blank.text == expected)
    var validated = BoardMarks()
    try validated.apply(name:"place_textboxes",arguments:arguments(["boxes":[try JSONSerialization.jsonObject(with:JSONEncoder().encode(blank))]]))
    assert(validated.boxes[0].text == expected)
}
for (kind,index) in [("fill",0),("fill",-1),("short",1)] {
    var invalid = box(kind,["Answer."]); invalid["blank_index"] = index
    do { try marks.apply(name:"place_textboxes",arguments:arguments(["boxes":[invalid]])); fatalError("Expected invalid blank index rejection") } catch {}
}

for area in [["x":100,"y":110,"width":300,"height":100], ["x":100,"y":900,"width":300,"height":200], ["x":500,"y":400,"width":200,"height":100]] {
    var invalid = box("fill",["Answer"]); invalid["below_area"] = area
    do { try marks.apply(name:"place_textboxes",arguments:arguments(["boxes":[invalid]])); fatalError("Expected invalid below area rejection") } catch {}
}
var withBelow = box("fill",["Answer"])
withBelow["below_area"] = ["x":100,"y":400,"width":300,"height":100]
var belowValidated = BoardMarks()
try belowValidated.apply(name:"place_textboxes",arguments:arguments(["boxes":[withBelow]]))
assert(belowValidated.boxes[0].belowArea?.y == 400)

let singleFill = TextMark(x:0,y:0,width:300,height:100,kind:.fill,lines:["Paris"],questionPrefix:"6.")
assert(singleFill.text == "6 Paris")
assert(TextMark(x:0,y:0,width:300,height:100,kind:.fill,lines:["Paris"],questionPrefix:"6.",blankIndex:1).text == "6.1 Paris")

let fillCrop = CGRect(x:100,y:100,width:500,height:300)
let blankSlot = CGRect(x:200,y:200,width:30,height:20)
assert(fillAnswerRect(size:CGSize(width:25,height:16),blank:blankSlot,below:nil,selection:fillCrop,occupied:[]) == CGRect(x:200,y:200,width:25,height:16))
assert(fillAnswerRect(size:CGSize(width:100,height:16),blank:blankSlot,below:nil,selection:fillCrop,occupied:[]) == CGRect(x:200,y:222,width:100,height:16))
assert(fillAnswerRect(size:CGSize(width:600,height:16),blank:blankSlot,below:nil,selection:fillCrop,occupied:[]) == nil)
assert(fillAnswerRect(size:CGSize(width:100,height:16),blank:CGRect(x:200,y:385,width:30,height:15),below:nil,selection:fillCrop,occupied:[]) == nil)
