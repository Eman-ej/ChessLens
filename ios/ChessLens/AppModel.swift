import SwiftUI
import UIKit
import Combine

@MainActor
final class AppModel: ObservableObject {
    private static let sampleHint = "Example: White has a mate in one. Tap Find best move to ask Stockfish."
    @Published var position = ChessPosition.initial
    @Published var whiteAtBottom = true
    @Published var selectedSquare: Int?
    @Published var uncertainSquares: [String] = []
    @Published var warnings: [String] = []
    @Published var analysis: Analysis?
    @Published var busy: String?
    @Published var error: String?
    private var analysisGeneration = 0


    func invalidateAnalysis() {
        analysis = nil
    }


    func setPiece(_ piece: String) {
        guard let index = selectedSquare else { return }
        position.squares[index] = piece
        position.halfmove = 0
        uncertainSquares.removeAll { $0 == ChessPosition.name(at: index) }
        invalidateAnalysis()
    }

    func playMove(from source: Int, to destination: Int, promotion: ChessPromotion? = nil) {
        guard selectedSquare == source, busy == nil,
              let moved = position.applyingMove(from: source, to: destination, promotion: promotion) else { return }

        // Move scan markers with the pieces; clear markers on captured pieces or superseded squares.
        let previousUncertainties = Set(uncertainSquares)
        var remaining = previousUncertainties
        for index in position.squares.indices where position.squares[index] != moved.position.squares[index] {
            remaining.remove(ChessPosition.name(at: index))
        }
        var relocations = [(from: source, to: destination)]
        if let rookMove = moved.rookMove { relocations.append(rookMove) }
        for relocation in relocations where previousUncertainties.contains(ChessPosition.name(at: relocation.from)) {
            remaining.insert(ChessPosition.name(at: relocation.to))
        }

        position = moved.position
        uncertainSquares = remaining.sorted()
        warnings.removeAll { $0 == Self.sampleHint }
        selectedSquare = nil
        invalidateAnalysis()
    }

    func loadExample() {
        position = .sample
        warnings = [Self.sampleHint]
        uncertainSquares = []
        selectedSquare = nil
        invalidateAnalysis()
    }


    func loadFEN(_ text: String) {
        do {
            position = try ChessPosition(fen: text)
            warnings = []
            uncertainSquares = []
            selectedSquare = nil
            invalidateAnalysis()
        } catch { self.error = error.localizedDescription }
    }


    func analyze() async {
        guard busy == nil else { return }
        busy = "Stockfish is thinking on this iPhone…"
        let fen = position.fen
        analysisGeneration += 1
        let generation = analysisGeneration
        defer { busy = nil }
        do {
            let result = try await LocalStockfish.shared.analyze(fen: fen)
            if generation == analysisGeneration, position.fen == fen {
                analysis = result; selectedSquare = nil
            }
        } catch is CancellationError {
            // Backgrounding is a normal cancellation, not an analysis failure.
        } catch {
            if generation == analysisGeneration { self.error = error.localizedDescription }
        }
    }

    func stopAnalysis() {
        analysisGeneration += 1
        LocalStockfish.shared.stop()
    }
}
