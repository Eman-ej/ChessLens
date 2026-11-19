import SwiftUI

enum Theme {
    static let background = Color(red: 0.055, green: 0.095, blue: 0.085)
    static let card = Color(red: 0.09, green: 0.14, blue: 0.125)
    static let accent = Color(red: 0.78, green: 0.93, blue: 0.57)
    static let lightSquare = Color(red: 0.86, green: 0.89, blue: 0.80)
    static let darkSquare = Color(red: 0.36, green: 0.49, blue: 0.41)
}

struct BoardView: View {
    @ObservedObject var model: AppModel
    @State private var pendingPromotion: PromotionRequest?

    var body: some View {
        GeometryReader { geometry in
            let side = geometry.size.width / 8
            let legalDestinations = model.selectedSquare.map { model.position.legalDestinations(from: $0) } ?? []
            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { col in
                                let index = model.whiteAtBottom ? row * 8 + col : 63 - (row * 8 + col)
                                let name = ChessPosition.name(at: index)
                                let piece = model.position.squares[index]
                                let isLegalDestination = legalDestinations.contains(index)
                                Button { tapSquare(index, isLegalDestination: isLegalDestination) } label: {
                                    ZStack {
                                        ((row + col) % 2 == 0 ? Theme.lightSquare : Theme.darkSquare)
                                        if model.selectedSquare == index {
                                            Color.yellow.opacity(0.55)
                                        } else if name == model.analysis?.fromSquare || name == model.analysis?.toSquare {
                                            Theme.accent.opacity(0.5)
                                        }
                                        if isLegalDestination {
                                            MoveMarker(isCapture: piece != ".", squareSize: side)
                                                .accessibilityHidden(true)
                                                .allowsHitTesting(false)
                                        }
                                        ChessPieceView(piece: piece)
                                            .frame(width: side * 0.92, height: side * 0.92)
                                            .offset(y: -side * 0.05)
                                        VStack {
                                            HStack {
                                                if col == 0 { Text(String(name.suffix(1))).font(.system(size: 9, weight: .bold)) }
                                                Spacer(minLength: 0)
                                                if model.uncertainSquares.contains(name) {
                                                    Circle().fill(.orange).frame(width: 7, height: 7)
                                                }
                                            }
                                            Spacer(minLength: 0)
                                            if row == 7 {
                                                HStack {
                                                    Spacer(minLength: 0)
                                                    Text(String(name.prefix(1))).font(.system(size: 8, weight: .bold))
                                                }
                                                .offset(y: 2)
                                            }
                                        }
                                        .padding(3)
                                        .foregroundStyle(Color.black.opacity(0.7))
                                    }
                                    .frame(width: side, height: side)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(name), \(pieceName(piece))")
                                .accessibilityValue(isLegalDestination ? "Legal destination" : "")
                                .accessibilityHint(isLegalDestination ? "Moves the selected piece here" : "Select to show moves or edit this square")
                            }
                        }
                    }
                }
                if let from = model.analysis?.fromSquare, let to = model.analysis?.toSquare {
                    MoveArrow(from: from, to: to, whiteAtBottom: model.whiteAtBottom)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .aspectRatio(1, contentMode: .fit)
        .confirmationDialog(
            "Promote pawn",
            isPresented: Binding(get: { pendingPromotion != nil }, set: { if !$0 { pendingPromotion = nil } }),
            titleVisibility: .visible,
            presenting: pendingPromotion
        ) { request in
            ForEach(ChessPromotion.allCases, id: \.self) { promotion in
                Button(String(describing: promotion).capitalized) {
                    model.playMove(from: request.from, to: request.to, promotion: promotion)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private func tapSquare(_ index: Int, isLegalDestination: Bool) {
        guard let source = model.selectedSquare, isLegalDestination else {
            model.selectedSquare = model.selectedSquare == index ? nil : index
            return
        }
        if model.position.isPromotion(from: source, to: index) {
            pendingPromotion = PromotionRequest(from: source, to: index)
        } else {
            model.playMove(from: source, to: index)
        }
    }

    private struct PromotionRequest {
        let from: Int
        let to: Int
    }
}

private struct MoveMarker: View {
    let isCapture: Bool
    let squareSize: CGFloat

    var body: some View {
        if isCapture {
            Circle()
                .strokeBorder(.black.opacity(0.34), lineWidth: squareSize * 0.085)
                .frame(width: squareSize * 0.96, height: squareSize * 0.96)
        } else {
            Circle()
                .fill(.black.opacity(0.28))
                .frame(width: squareSize * 0.29, height: squareSize * 0.29)
        }
    }
}

private struct MoveArrow: View {
    let from: String
    let to: String
    let whiteAtBottom: Bool

    var body: some View {
        Canvas { context, size in
            guard let start = ChessPosition.index(of: from), let end = ChessPosition.index(of: to) else { return }
            let square = size.width / 8
            func center(_ index: Int) -> CGPoint {
                let shown = whiteAtBottom ? index : 63 - index
                return CGPoint(x: (Double(shown % 8) + 0.5) * square, y: (Double(shown / 8) + 0.5) * square)
            }
            let a = center(start), b = center(end)
            let angle = atan2(b.y - a.y, b.x - a.x)
            let tip = CGPoint(x: b.x - cos(angle) * square * 0.10, y: b.y - sin(angle) * square * 0.10)
            let base = CGPoint(x: tip.x - cos(angle) * square * 0.34, y: tip.y - sin(angle) * square * 0.34)
            var line = Path()
            line.move(to: a); line.addLine(to: base)
            context.stroke(line, with: .color(.orange.opacity(0.88)), style: StrokeStyle(lineWidth: square * 0.16, lineCap: .round))
            var head = Path()
            head.move(to: tip)
            head.addLine(to: CGPoint(x: base.x - sin(angle) * square * 0.22, y: base.y + cos(angle) * square * 0.22))
            head.addLine(to: CGPoint(x: base.x + sin(angle) * square * 0.22, y: base.y - cos(angle) * square * 0.22))
            head.closeSubpath()
            context.fill(head, with: .color(.orange.opacity(0.9)))
        }
    }
}

extension View {
    func lensCard() -> some View {
        padding(18).background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
    }
}
