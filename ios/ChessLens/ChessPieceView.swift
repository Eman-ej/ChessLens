import SwiftUI

struct ChessPieceView: View {
    let piece: String

    var body: some View {
        if let kind = ChessPieceKind(rawValue: piece.lowercased()) {
            let isWhite = piece == piece.uppercased()
            Canvas { context, size in
                // Draw on a 50-point square so both views share the same proportions.
                let scale = min(size.width, size.height) / 50
                var drawing = context
                drawing.translateBy(x: (size.width - 50 * scale) / 2, y: (size.height - 50 * scale) / 2)
                drawing.scaleBy(x: scale, y: scale)

                let detail = isWhite ? Color.black : Color.white
                let silhouette = kind.silhouette
                drawing.fill(silhouette, with: .color(isWhite ? .white : .black))
                drawing.stroke(silhouette, with: .color(.black), style: Self.outline)
                drawing.stroke(kind.lines, with: .color(detail), style: Self.detail)
                drawing.fill(kind.ornaments, with: .color(detail))
                if kind == .king {
                    drawing.stroke(Self.kingCross, with: .color(.black), style: Self.outline)
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }

    private static let outline = StrokeStyle(lineWidth: 1.65, lineCap: .round, lineJoin: .round)
    private static let detail = StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)
    private static let kingCross = Path { path in
        path.move(to: point(25, 5))
        path.addLine(to: point(25, 12.7))
        path.move(to: point(22, 7.6))
        path.addLine(to: point(28, 7.6))
    }
}

private enum ChessPieceKind: String {
    case king = "k"
    case queen = "q"
    case rook = "r"
    case bishop = "b"
    case knight = "n"
    case pawn = "p"

    var silhouette: Path {
        Path { path in
            switch self {
            case .king:
                path.move(to: point(13, 37))
                path.addCurve(to: point(7, 19), control1: point(8, 31), control2: point(3, 25))
                path.addCurve(to: point(20, 18), control1: point(10, 14), control2: point(16, 14))
                path.addCurve(to: point(30, 18), control1: point(21, 10), control2: point(29, 10))
                path.addCurve(to: point(43, 19), control1: point(34, 14), control2: point(40, 14))
                path.addCurve(to: point(37, 37), control1: point(47, 25), control2: point(42, 31))
                path.addLine(to: point(38.5, 44))
                path.addLine(to: point(11.5, 44))
                path.closeSubpath()
            case .queen:
                path.addLines([point(13, 36), point(5.5, 18), point(15, 25), point(17.5, 9), point(22, 23),
                               point(25, 8), point(28, 23), point(32.5, 9), point(35, 25),
                               point(44.5, 18), point(37, 36), point(38, 44), point(12, 44)])
                path.closeSubpath()
                path.addEllipse(in: circle(5.5, 17.5, radius: 1.8))
                path.addEllipse(in: circle(17.5, 9, radius: 1.8))
                path.addEllipse(in: circle(25, 8, radius: 1.8))
                path.addEllipse(in: circle(32.5, 9, radius: 1.8))
                path.addEllipse(in: circle(44.5, 17.5, radius: 1.8))
            case .rook:
                path.addLines([point(10, 44), point(10, 39), point(14, 36), point(16, 21),
                               point(12, 17), point(12, 9), point(18, 9), point(18, 12.5),
                               point(22, 12.5), point(22, 9), point(28, 9), point(28, 12.5),
                               point(32, 12.5), point(32, 9), point(38, 9), point(38, 17),
                               point(34, 21), point(36, 36), point(40, 39), point(40, 44)])
                path.closeSubpath()
            case .bishop:
                path.move(to: point(20, 11))
                path.addQuadCurve(to: point(30, 11), control: point(25, 8))
                path.addCurve(to: point(31, 33), control1: point(42, 19), control2: point(37, 28))
                path.addQuadCurve(to: point(37, 40.5), control: point(31, 39.5))
                path.addQuadCurve(to: point(44, 44), control: point(42, 40))
                path.addCurve(to: point(25, 40.5), control1: point(30, 45.5), control2: point(28, 43.5))
                path.addCurve(to: point(6, 44), control1: point(22, 43.5), control2: point(20, 45.5))
                path.addQuadCurve(to: point(13, 40.5), control: point(8, 40))
                path.addQuadCurve(to: point(19, 33), control: point(19, 39.5))
                path.addCurve(to: point(20, 11), control1: point(13, 28), control2: point(8, 19))
                path.closeSubpath()
                path.addEllipse(in: circle(25, 7, radius: 2.6))
            case .knight:
                path.move(to: point(29.5, 6))
                path.addCurve(to: point(41, 27), control1: point(36.5, 10), control2: point(41, 17))
                path.addQuadCurve(to: point(42.5, 44), control: point(40.5, 38))
                path.addLine(to: point(13, 44))
                path.addCurve(to: point(24, 27), control1: point(13.5, 34), control2: point(24, 33))
                path.addQuadCurve(to: point(17, 29.5), control: point(20.5, 26.5))
                path.addLine(to: point(12.5, 31))
                path.addLine(to: point(11, 27.5))
                path.addLine(to: point(8.5, 28.5))
                path.addLine(to: point(7, 23))
                path.addQuadCurve(to: point(20, 13), control: point(11.5, 18.5))
                path.addQuadCurve(to: point(29.5, 6), control: point(25.5, 10))
                path.closeSubpath()
            case .pawn:
                path.move(to: point(22, 22))
                path.addCurve(to: point(18.5, 14), control1: point(19, 19.5), control2: point(18, 17))
                path.addCurve(to: point(31.5, 14), control1: point(20, 8.5), control2: point(30, 8.5))
                path.addCurve(to: point(28, 22), control1: point(32, 17), control2: point(31, 19.5))
                path.addQuadCurve(to: point(33.5, 25.5), control: point(30, 24))
                path.addLine(to: point(28.7, 25.5))
                path.addCurve(to: point(37.5, 42), control1: point(30, 33), control2: point(33, 38.5))
                path.addQuadCurve(to: point(37.5, 44), control: point(38.5, 43))
                path.addLine(to: point(12.5, 44))
                path.addQuadCurve(to: point(12.5, 42), control: point(11.5, 43))
                path.addCurve(to: point(21.3, 25.5), control1: point(17, 38.5), control2: point(20, 33))
                path.addLine(to: point(16.5, 25.5))
                path.addQuadCurve(to: point(22, 22), control: point(20, 24))
                path.closeSubpath()
            }
        }
    }

    var lines: Path {
        Path { path in
            switch self {
            case .king:
                path.move(to: point(13, 37))
                path.addQuadCurve(to: point(37, 37), control: point(25, 31))
                path.move(to: point(14, 34))
                path.addCurve(to: point(21, 19), control1: point(1, 18.5), control2: point(14, 13.5))
                path.addQuadCurve(to: point(25, 33.5), control: point(25.5, 24))
                path.addQuadCurve(to: point(29, 19), control: point(24.5, 24))
                path.addCurve(to: point(36, 34), control1: point(36, 13.5), control2: point(49, 18.5))
            case .queen:
                path.move(to: point(13, 36))
                path.addQuadCurve(to: point(37, 36), control: point(25, 29.5))
            case .rook:
                path.addLines([point(14.5, 19.5), point(35.5, 19.5)])
                path.addLines([point(14, 36.5), point(36, 36.5)])
            case .bishop:
                path.addLines([point(25, 16), point(25, 23)])
                path.addLines([point(22, 19), point(28, 19)])
                path.addLines([point(19, 29), point(31, 29)])
                path.addLines([point(19, 33), point(31, 33)])
            case .knight:
                path.move(to: point(31.5, 11.5))
                path.addCurve(to: point(38.5, 40), control1: point(41, 19.5), control2: point(35, 32))
                path.move(to: point(13.2, 26))
                path.addQuadCurve(to: point(19, 24), control: point(16, 25.8))
            case .pawn:
                break
            }
        }
    }

    var ornaments: Path {
        Path { path in
            switch self {
            case .king, .queen:
                path.addLines([point(22, 39.5), point(25, 37.7), point(28, 39.5), point(25, 41.3)])
                path.closeSubpath()
                path.addEllipse(in: circle(17.7, 39.5, radius: 0.85))
                path.addEllipse(in: circle(32.3, 39.5, radius: 0.85))
            case .knight:
                path.addEllipse(in: circle(20.5, 19.4, radius: 0.95))
                path.addEllipse(in: circle(10.2, 24, radius: 0.75))
            case .rook, .bishop, .pawn:
                break
            }
        }
    }
}

private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x, y: y)
}

private func circle(_ x: CGFloat, _ y: CGFloat, radius: CGFloat) -> CGRect {
    CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
}
