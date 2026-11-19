import Foundation

/// One in-process engine with serialized, bounded searches. No URLSession or
/// executable launch is involved; the Objective-C++ bridge owns Stockfish.
@MainActor
final class LocalStockfish {
    static let shared = LocalStockfish()
    private let queue = DispatchQueue(label: "ChessLens.Stockfish", qos: .userInitiated)
    private let bridge = StockfishWorker()
    private var searching = false
    private var generation = 0

    func stop() {
        generation += 1
        bridge.stop()
    }

    func analyze(fen: String) async throws -> Analysis {
        guard !searching else { throw ServiceError(message: "Stockfish is finishing its previous search. Try again in a moment.") }
        let position = try ChessPosition(fen: fen)
        try position.validateForLocalAnalysis()
        try Task.checkCancellation()
        let engineName = "Stockfish 19 · On iPhone"
        let hasMoves = position.hasLegalMoves
        if !hasMoves || position.isAutomaticDraw {
            return Analysis(fen: fen, status: !hasMoves ? (position.isInCheck ? "checkmate" : "stalemate") : "draw",
                            engine: engineName, bestMove: nil, bestMoveSAN: nil,
                            fromSquare: nil, toSquare: nil, variations: [])
        }
        searching = true
        let current = generation
        defer { searching = false }
        let worker = bridge
        let transcript: String = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    do {
                        let result = try worker.analyze(fen: fen, milliseconds: 2000)
                        continuation.resume(returning: result)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { worker.stop() }
        try Task.checkCancellation()
        guard current == generation else { throw CancellationError() }
        return try StockfishTranscript.analysis(transcript, position: position, engine: engineName)
    }
}

// Analysis calls use LocalStockfish's serial queue; stop is the bridge's atomic,
// thread-safe interruption entry point. No Objective-C state crosses otherwise.
private final class StockfishWorker: @unchecked Sendable {
    private let bridge = StockfishBridge()
    func analyze(fen: String, milliseconds: Int) throws -> String {
        try bridge.analyze(fen: fen, milliseconds: milliseconds)
    }
    func stop() { bridge.stop() }
}

enum StockfishTranscript {
    private struct Line {
        let moves: [String]
        let cp: Int?
        let mate: Int?
        let depth: Int
    }

    static func analysis(_ transcript: String, position: ChessPosition, engine: String) throws -> Analysis {
        var lines: [Int: Line] = [:]
        var best: String?
        for row in transcript.split(separator: "\n") {
            let fields = row.split(separator: " ").map(String.init)
            func value(_ key: String) -> String? {
                guard let index = fields.firstIndex(of: key), index + 1 < fields.count else { return nil }
                return fields[index + 1]
            }
            if fields.first == "bestmove" { best = fields.dropFirst().first; continue }
            guard fields.first == "info", let pv = fields.firstIndex(of: "pv"),
                  let depthString = value("depth"), let depth = Int(depthString) else { continue }
            let moves = Array(fields.dropFirst(pv + 1))
            guard !moves.isEmpty else { continue }
            let side = position.turn == "w" ? 1 : -1
            lines[Int(value("multipv") ?? "1") ?? 1] = Line(
                moves: moves, cp: value("cp").flatMap(Int.init).map { $0 * side },
                mate: value("mate").flatMap(Int.init).map { $0 * side }, depth: depth)
        }
        guard let best, let san = position.san(forUCI: best) else {
            throw ServiceError(message: "Stockfish did not return a legal move. Review the position and try again.")
        }
        var ordered = lines.keys.sorted().compactMap { lines[$0] }
        if let index = ordered.firstIndex(where: { $0.moves.first == best }) {
            let first = ordered.remove(at: index); ordered.insert(first, at: 0)
        } else { ordered.insert(Line(moves: [best], cp: nil, mate: nil, depth: 0), at: 0) }
        var seen: Set<String> = []
        let variations: [Variation] = ordered.compactMap { line in
            guard let move = line.moves.first, seen.insert(move).inserted,
                  let san = position.san(forUCI: move) else { return nil }
            var board = position, continuation: [String] = []
            for uci in line.moves.prefix(16) {
                guard let notation = board.san(forUCI: uci), let next = board.applyingUCI(uci) else { break }
                continuation.append(notation); board = next
            }
            return Variation(move: move, san: san, line: continuation, scoreForWhiteCp: line.cp,
                             mateForWhite: line.mate, depth: line.depth)
        }
        return Analysis(fen: position.fen, status: "ok", engine: engine, bestMove: best, bestMoveSAN: san,
                        fromSquare: String(best.prefix(2)), toSquare: String(best.dropFirst(2).prefix(2)),
                        variations: Array(variations.prefix(3)))
    }
}
