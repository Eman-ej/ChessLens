import Foundation

@main
struct LocalStockfishChecks {
    static var count = 0
    static func check(_ condition: Bool, _ label: String) {
        guard condition else { fatalError("FAILED: " + label) }
        count += 1
    }

    @MainActor
    static func main() async throws {
        let white = try await LocalStockfish.shared.analyze(fen: ChessPosition.sample.fen)
        check(white.bestMove == "h5f7" && white.bestMoveSAN == "Qxf7#", "real local white mate")
        check(white.variations.first?.mateForWhite == 1, "white mate score perspective")
        check(white.variations.count == 3, "three principal variations")
        for variation in white.variations {
            check(ChessPosition.sample.san(forUCI: variation.move) == variation.san, "legal variation and SAN")
        }

        var mirror = ChessPosition.sample
        mirror.squares = (0..<8).flatMap { row in
            ChessPosition.sample.squares[((7-row)*8)..<((8-row)*8)].map {
                $0 == $0.uppercased() ? $0.lowercased() : $0.uppercased()
            }
        }
        mirror.turn = "b"
        let black = try await LocalStockfish.shared.analyze(fen: mirror.fen)
        check(black.bestMove == "h4f2" && black.bestMoveSAN == "Qxf2#", "real local black mate")
        check(black.variations.first?.mateForWhite == -1, "black mate score perspective")

        for (fen, status) in [
            ("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3", "checkmate"),
            ("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1", "stalemate"),
            ("7k/8/6K1/8/8/8/8/8 w - - 0 1", "draw")
        ] {
            let result = try await LocalStockfish.shared.analyze(fen: fen)
            check(result.status == status && result.bestMove == nil, "terminal " + status)
        }

        for fen in [
            "8/8/8/8/8/8/8/8 w - - 0 1",
            "8/8/8/8/8/8/4k3/4K3 w - - 0 1",
            "7k/8/8/8/8/8/8/P3K3 w - - 0 1",
            "4k3/8/8/8/8/8/4R3/4K3 w - - 0 1",
            "4k3/8/8/8/8/8/8/4K3 w K - 0 1",
            "4k3/8/8/8/8/8/8/4K3 w - e6 0 1"
        ] {
            do {
                _ = try await LocalStockfish.shared.analyze(fen: fen)
                fatalError("accepted illegal FEN: " + fen)
            } catch { count += 1 }
        }

        for (fen, move, expected) in [
            ("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "e1g1", "O-O"),
            ("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "e1c1", "O-O-O"),
            ("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", "e5d6", "exd6"),
            ("7k/P7/8/8/8/8/8/7K w - - 0 1", "a7a8q", "a8=Q+"),
            ("7k/P7/8/8/8/8/8/7K w - - 0 1", "a7a8n", "a8=N"),
            ("7k/8/8/8/8/8/8/1N2KN2 w - - 0 1", "b1d2", "Nbd2"),
            ("7k/8/8/8/8/R7/8/R3K3 w - - 0 1", "a1a2", "R1a2")
        ] {
            let board = try ChessPosition(fen: fen)
            check(board.san(forUCI: move) == expected, "SAN " + expected)
        }

        let parsed = try StockfishTranscript.analysis(
            "info depth 9 multipv 1 score cp 37 pv e7e5 g1f3\nbestmove e7e5\n",
            position: try ChessPosition(fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"), engine: "test")
        check(parsed.variations.first?.scoreForWhiteCp == -37, "centipawn perspective conversion")
        check(parsed.variations.first?.line == ["e5", "Nf3"], "principal variation SAN")

        let thinking = Task { try await LocalStockfish.shared.analyze(fen: ChessPosition.initial.fen) }
        try await Task.sleep(nanoseconds: 150_000_000)
        LocalStockfish.shared.stop()
        do { _ = try await thinking.value; fatalError("stopped search returned a result") }
        catch is CancellationError { count += 1 }
        let restarted = try await LocalStockfish.shared.analyze(fen: ChessPosition.sample.fen)
        check(restarted.bestMoveSAN == "Qxf7#", "engine reusable after stop")
        print("Passed \(count) Swift/local Stockfish integration checks; no network service used.")
    }
}
