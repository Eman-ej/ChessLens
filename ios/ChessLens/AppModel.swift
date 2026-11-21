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


    @Published private(set) var photo: UIImage?
    private(set) var sampleCorners: [CGPoint]?

    func selectPhoto(_ image: UIImage) {
        photo = image
        sampleCorners = nil
    }

    func selectSamplePhoto() {
        guard let url = Bundle.main.url(forResource: "SampleRealBoard", withExtension: "jpg"),
              let image = UIImage(contentsOfFile: url.path) else {
            error = "The sample photo could not be opened."
            return
        }
        selectPhoto(image)
        // ChessReD annotations in a8, h8, h1, a1 order, normalized to the sample.
        sampleCorners = [(902.5667, 920.55), (156.2167, 790.0125), (410.9417, 349.2583), (1004.55, 423.3)].map {
            CGPoint(x: $0.0 / 1280, y: $0.1 / 1280)
        }
    }

    func scan(corners: [CGPoint]? = nil) async {
        guard busy == nil, let photo else { return }
        busy = "Reading the board on this iPhone…"
        defer { busy = nil }
        do {
            // Draw upright so the recognizer and the corner picker see the same orientation.
            let scale = min(photo.scale, 4096 / max(photo.size.width, photo.size.height))
            let size = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                photo.draw(in: CGRect(origin: .zero, size: size))
            }
            guard let image = upright.cgImage else { throw ServiceError(message: "This photo could not be opened.") }

            let result: Recognition
            if let corners {
                result = try await Task.detached(priority: .userInitiated) {
                    guard let url = Bundle.main.url(forResource: "ChessLensColabT4", withExtension: "mlmodelc") else {
                        throw ServiceError(message: "The guided scanner is missing from this build.")
                    }
                    let model = try RealBoardScanner.loadModel(at: url)
                    return try await RealBoardScanner.recognizeWithFallback(image: image, corners: corners, model: model) {
                        try await FullBoardScanner.shared.recognize(image: $0)
                    }
                }.value
            } else {
                result = try await FullBoardScanner.shared.recognize(image: image)
            }
            position = try ChessPosition(fen: result.placement + " w - - 0 1")
            warnings = result.warnings
            uncertainSquares = result.uncertainSquares
            selectedSquare = nil
            whiteAtBottom = true
            invalidateAnalysis()
        } catch {
            self.error = error.localizedDescription
        }
    }

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
