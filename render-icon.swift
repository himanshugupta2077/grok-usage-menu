import AppKit

let paths = [
    "M395.479 633.828L735.91 381.105C752.599 368.715 776.454 373.548 784.406 392.792C826.26 494.285 807.561 616.253 724.288 699.996C641.016 783.739 525.151 802.104 419.247 760.277L303.556 814.143C469.49 928.202 670.987 899.995 796.901 773.282C896.776 672.843 927.708 535.937 898.785 412.476L899.047 412.739C857.105 231.37 909.358 158.874 1016.4 10.6326C1018.93 7.11771 1021.47 3.60279 1024 0L883.144 141.651V141.212L395.392 633.916",
    "M325.226 695.251C206.128 580.84 226.662 403.776 328.285 301.668C403.431 226.097 526.549 195.254 634.026 240.596L749.454 186.994C728.657 171.88 702.007 155.623 671.424 144.2C533.19 86.9942 367.693 115.465 255.323 228.382C147.234 337.081 113.244 504.215 171.613 646.833C215.216 753.423 143.739 828.818 71.7385 904.916C46.2237 931.893 20.6216 958.87 0 987.429L325.139 695.339",
]

func tokens(_ d: String) -> [String] {
    var out: [String] = []
    var current = ""
    func flush() {
        if !current.isEmpty { out.append(current); current = "" }
    }
    for ch in d {
        if ch.isLetter || ch == "-" || ch == "." || ch.isNumber {
            if ch.isLetter { flush() }
            current.append(ch)
            if ch.isLetter { flush() }
        } else {
            flush()
        }
    }
    flush()
    return out
}

func bezier(_ d: String) -> NSBezierPath {
    let path = NSBezierPath()
    let parts = tokens(d)
    var i = 0
    var command = ""
    var cursor = NSPoint.zero
    func num() -> CGFloat {
        defer { i += 1 }
        return CGFloat(Double(parts[i]) ?? 0)
    }
    while i < parts.count {
        if parts[i].first?.isLetter == true {
            command = parts[i]
            i += 1
        }
        switch command {
        case "M":
            cursor = NSPoint(x: num(), y: num())
            path.move(to: cursor)
            command = "L"
        case "L":
            cursor = NSPoint(x: num(), y: num())
            path.line(to: cursor)
        case "V":
            cursor.y = num()
            path.line(to: cursor)
        case "H":
            cursor.x = num()
            path.line(to: cursor)
        case "C":
            let c1 = NSPoint(x: num(), y: num())
            let c2 = NSPoint(x: num(), y: num())
            cursor = NSPoint(x: num(), y: num())
            path.curve(to: cursor, controlPoint1: c1, controlPoint2: c2)
        case "Z", "z":
            path.close()
        default:
            i += 1
        }
    }
    return path
}

let combined = NSBezierPath()
for d in paths { combined.append(bezier(d)) }
let bounds = combined.bounds
let side: CGFloat = 128
let pad: CGFloat = 8
let scale = min((side - pad * 2) / bounds.width, (side - pad * 2) / bounds.height)
func fitted(_ source: NSBezierPath) -> NSBezierPath {
    let out = NSBezierPath()
    func map(_ point: NSPoint) -> NSPoint {
        NSPoint(
            x: pad + (point.x - bounds.minX) * scale,
            y: pad + (point.y - bounds.minY) * scale
        )
    }
    for index in 0..<source.elementCount {
        var points = [NSPoint](repeating: .zero, count: 3)
        switch source.element(at: index, associatedPoints: &points) {
        case .moveTo:
            out.move(to: map(points[0]))
        case .lineTo:
            out.line(to: map(points[0]))
        case .curveTo:
            out.curve(to: map(points[2]), controlPoint1: map(points[0]), controlPoint2: map(points[1]))
        case .closePath:
            out.close()
        default:
            break
        }
    }
    return out
}

let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()
    NSColor.black.setFill()
    fitted(combined).fill()
    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("render failed\n", stderr)
    exit(1)
}
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "grok.png")
try png.write(to: out)
print("wrote \(out.path)")
