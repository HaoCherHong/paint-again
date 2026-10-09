import AppKit

enum ToolKind: Hashable {
    case selectRectangle
    case selectFreeform
    case pencil
    case fill
    case text
    case eraser
    case colorPicker
    case magnifier
    case brush(BrushKind)
    case shape(ShapeKind)

    var isSelection: Bool {
        switch self {
        case .selectRectangle, .selectFreeform: return true
        default: return false
        }
    }
    var isBrush: Bool { if case .brush = self { return true } else { return false } }
    var isShape: Bool { if case .shape = self { return true } else { return false } }
}

enum BrushKind: Int, CaseIterable {
    case brush, calligraphy1, calligraphy2, airbrush, oil, crayon, marker, naturalPencil, watercolor

    var title: String {
        switch self {
        case .brush: return L("Brush")
        case .calligraphy1: return L("Calligraphy brush 1")
        case .calligraphy2: return L("Calligraphy brush 2")
        case .airbrush: return L("Airbrush")
        case .oil: return L("Oil brush")
        case .crayon: return L("Crayon")
        case .marker: return L("Marker")
        case .naturalPencil: return L("Natural pencil")
        case .watercolor: return L("Watercolor")
        }
    }

    var symbol: String {
        switch self {
        case .brush: return "paintbrush.pointed"
        case .calligraphy1: return "pencil.tip"
        case .calligraphy2: return "pencil.tip.crop.left"
        case .airbrush: return "sparkles"
        case .oil: return "paintbrush"
        case .crayon: return "pencil.line"
        case .marker: return "highlighter"
        case .naturalPencil: return "pencil"
        case .watercolor: return "drop"
        }
    }
}

enum ShapeKind: Int, CaseIterable {
    case line, curve, oval, rectangle, roundedRectangle, polygon, triangle, rightTriangle, diamond
    case pentagon, hexagon, rightArrow, leftArrow, upArrow, downArrow, fourPointStar, fivePointStar
    case sixPointStar, roundedCallout, ovalCallout, cloudCallout, lightning

    var title: String {
        switch self {
        case .line: return L("Line")
        case .curve: return L("Curve")
        case .oval: return L("Oval")
        case .rectangle: return L("Rectangle")
        case .roundedRectangle: return L("Rounded rectangle")
        case .polygon: return L("Polygon")
        case .triangle: return L("Triangle")
        case .rightTriangle: return L("Right-angled triangle")
        case .diamond: return L("Diamond")
        case .pentagon: return L("Pentagon")
        case .hexagon: return L("Hexagon")
        case .rightArrow: return L("Right arrow")
        case .leftArrow: return L("Left arrow")
        case .upArrow: return L("Up arrow")
        case .downArrow: return L("Down arrow")
        case .fourPointStar: return L("Four-point star")
        case .fivePointStar: return L("Five-point star")
        case .sixPointStar: return L("Six-point star")
        case .roundedCallout: return L("Rounded rectangular callout")
        case .ovalCallout: return L("Oval callout")
        case .cloudCallout: return L("Cloud callout")
        case .lightning: return L("Lightning")
        }
    }

    var isOpenPath: Bool { self == .line || self == .curve }
}

enum ShapeStrokeStyle: Int, CaseIterable {
    case none, solid
    var title: String { self == .none ? L("No outline") : L("Solid color") }
}

enum ShapeFillStyle: Int, CaseIterable {
    case none, solid
    var title: String { self == .none ? L("No fill") : L("Solid color") }
}

enum MouseButton { case primary, secondary }
