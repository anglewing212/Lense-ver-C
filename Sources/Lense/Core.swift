import Foundation
import CoreGraphics

struct PermissionRequestGate {
    private var requested = false
    mutating func shouldRequest() -> Bool {
        guard !requested else { return false }
        requested = true
        return true
    }
}

func selectionRect(_ a: CGPoint, _ b: CGPoint, bounds: CGRect) -> CGRect {
    CGRect(x: min(a.x,b.x), y: min(a.y,b.y), width: abs(a.x-b.x), height: abs(a.y-b.y)).intersection(bounds)
}
func snappedOrigin(frame: CGRect, bounds: CGRect) -> CGPoint {
    var origin = CGPoint(x: max(bounds.minX, min(frame.minX, bounds.maxX-frame.width)),
                         y: max(bounds.minY, min(frame.minY, bounds.maxY-frame.height)))
    let distances = [abs(frame.minX-bounds.minX), abs(bounds.maxX-frame.maxX),
                     abs(frame.minY-bounds.minY), abs(bounds.maxY-frame.maxY)]
    switch distances.indices.min(by: { distances[$0] < distances[$1] })! {
    case 0: origin.x = bounds.minX
    case 1: origin.x = bounds.maxX-frame.width
    case 2: origin.y = bounds.minY
    default: origin.y = bounds.maxY-frame.height
    }
    return origin
}

struct OverlayShortcut {
    private var held = false
    mutating func update(control: Bool, option: Bool, otherModifiers: Bool) -> Bool {
        let both = control && option
        defer { held = both }
        return both && !held && !otherModifiers
    }
}

struct CanvasSession {
    private(set) var generation = UUID()
    var isVisible = false
    private(set) var isThinking = false
    mutating func beginRound() { generation = UUID(); isThinking = true }
    mutating func finish(_ token: UUID) { if token == generation { isThinking = false } }
    mutating func cancel() { generation = UUID(); isThinking = false }
}

enum DockEdge: String {
    case left, right, bottom, top
    static func nearest(frame:CGRect,bounds:CGRect) -> DockEdge {
        let distances = [(DockEdge.left,abs(frame.minX-bounds.minX)),(.right,abs(frame.maxX-bounds.maxX)),
                         (.bottom,abs(frame.minY-bounds.minY)),(.top,abs(frame.maxY-bounds.maxY))]
        return distances.min(by:{$0.1 < $1.1})!.0
    }
    func body(in bounds:CGRect) -> CGRect {
        switch self {
        case .left: return CGRect(x:bounds.minX,y:bounds.midY-22,width:12,height:44)
        case .right: return CGRect(x:bounds.maxX-12,y:bounds.midY-22,width:12,height:44)
        case .bottom: return CGRect(x:bounds.midX-22,y:bounds.minY,width:44,height:12)
        case .top: return CGRect(x:bounds.midX-22,y:bounds.maxY-12,width:44,height:12)
        }
    }
}
