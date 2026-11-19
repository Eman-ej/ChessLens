import Foundation

@main
struct PositionChecks {
    static func main() throws {
        let initial = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        let parsed = try ChessPosition(fen: initial)
        precondition(parsed.fen == initial)
        for index in 0..<64 {
            precondition(ChessPosition.index(of: ChessPosition.name(at: index)) == index)
        }
        precondition(ChessPosition.index(of: "a8") == 0)
        precondition(ChessPosition.index(of: "h1") == 63)
        precondition(ChessPosition.index(of: "a0") == nil)
        for invalid in ["8/8/8/8/8/8/8/8", "9/8/8/8/8/8/8/8 w - - 0 1", "8/8/8/8/8/8/8/8 w KK - 0 1", "8/8/8/8/8/8/8/8 w - e4 0 1"] {
            do { _ = try ChessPosition(fen: invalid); preconditionFailure("Accepted invalid FEN") }
            catch PositionError.invalidFEN { }
        }
        var position = try ChessPosition(fen: initial)
        position.setRight("K", enabled: false)
        position.setRight("q", enabled: false)
        precondition(position.fen.contains(" w Qk - "))
        position.squares[ChessPosition.index(of: "e2")!] = "."
        position.squares[ChessPosition.index(of: "e4")!] = "P"
        position.turn = "b"
        position.enPassant = "e3"
        precondition(position.fen == "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b Qk e3 0 1")
        print("Swift position checks passed: FEN round trips, all 64 coordinates, editing, castling, en passant, invalid input.")
        try checkLegalDestinations(initial: initial)
        try checkPlayingMoves()
    }

    private static func checkLegalDestinations(initial: String) throws {
        func expect(_ fen: String, from source: String, _ destinations: Set<String>) throws {
            let position = try ChessPosition(fen: fen)
            let actual = Set(position.legalDestinations(from: ChessPosition.index(of: source)!).map(ChessPosition.name(at:)))
            precondition(actual == destinations, "\(source) in \(fen): expected \(destinations), got \(actual)")
        }

        try expect(initial, from: "e2", ["e3", "e4"])
        try expect(initial, from: "g1", ["f3", "h3"])
        try expect(initial, from: "a1", [])
        try expect(initial, from: "e7", [])
        try expect("4k3/4p3/8/8/8/8/8/4K3 b - - 0 1", from: "e7", ["e6", "e5"])
        try expect("4k3/8/8/8/8/4n3/4P3/4K3 w - - 0 1", from: "e2", [])
        try expect("k3r3/8/8/8/8/8/4R3/4K3 w - - 0 1", from: "e2", ["e3", "e4", "e5", "e6", "e7", "e8"])
        try expect("k3r3/8/8/8/8/8/8/1N2K3 w - - 0 1", from: "b1", [])
        try expect("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", from: "e1", ["c1", "d1", "f1", "g1", "d2", "e2", "f2"])
        try expect("r3kr2/8/8/8/8/8/8/R3K2R w KQ - 0 1", from: "e1", ["c1", "d1", "d2", "e2"])
        try expect("k7/8/8/3pP3/8/8/8/4K3 w - d6 0 1", from: "e5", ["d6", "e6"])
        try expect("k7/8/8/8/3Pp3/8/8/4K3 b - d3 0 1", from: "e4", ["d3", "e3"])
        try expect("k3r3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", from: "e5", ["e6"])
        try expect("k7/8/8/r4pPK/8/8/8/8 w - f6 0 1", from: "g5", ["g6"])
        try expect("k6r/6P1/8/8/8/8/8/4K3 w - - 0 1", from: "g7", ["g8", "h8"])
        try expect("8/8/8/8/8/8/4P3/4K3 w - - 0 1", from: "e2", [])
        print("Swift legal destination checks passed.")
    }

    private static func checkPlayingMoves() throws {
        func expect(
            _ fen: String, _ from: String, _ to: String, _ expected: String, promotion: ChessPromotion? = nil
        ) throws {
            let position = try ChessPosition(fen: fen)
            let result = position.applyingMove(
                from: ChessPosition.index(of: from)!, to: ChessPosition.index(of: to)!, promotion: promotion
            )
            precondition(result?.position.fen == expected,
                         "\(from)–\(to) in \(fen): expected \(expected), got \(result?.position.fen ?? "no move")")
        }

        try expect(ChessPosition.initial.fen, "e2", "e4",
                   "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")
        try expect("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", "g8", "f6",
                   "rnbqkb1r/pppppppp/5n2/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 1 2")
        try expect("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 4 12", "e1", "g1",
                   "r3k2r/8/8/8/8/8/8/R4RK1 b kq - 5 12")
        try expect("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 4 12", "e8", "c8",
                   "2kr3r/8/8/8/8/8/8/R3K2R w KQ - 5 13")
        try expect("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 4 12", "a1", "a8",
                   "R3k2r/8/8/8/8/8/8/4K2R b Kk - 0 12")
        try expect("k7/8/8/3pP3/8/8/8/4K3 w - d6 0 1", "e5", "d6",
                   "k7/8/3P4/8/8/8/8/4K3 b - - 0 1")
        try expect("k7/8/8/8/3Pp3/8/8/4K3 b - d3 0 1", "e4", "d3",
                   "k7/8/8/8/8/3p4/8/4K3 w - - 0 2")
        try expect("k6r/6P1/8/8/8/8/8/4K3 w - - 0 1", "g7", "h8",
                   "k6N/8/8/8/8/8/8/4K3 b - - 0 1", promotion: .knight)
        try expect("4k3/8/8/8/8/8/1p6/4K3 b - - 0 1", "b2", "b1",
                   "4k3/8/8/8/8/8/8/1r2K3 w - - 0 2", promotion: .rook)

        let promotion = try ChessPosition(fen: "k7/4P3/8/8/8/8/8/4K3 w - - 0 1")
        precondition(promotion.applyingMove(from: 12, to: 4) == nil)
        precondition(ChessPosition.initial.applyingMove(from: 52, to: 28) == nil)
        precondition(ChessPosition.initial.applyingMove(from: 52, to: 36, promotion: .queen) == nil)
        precondition(ChessPosition.initial.applyingMove(from: -1, to: 36) == nil)
        print("Swift played-move checks passed.")
    }
}
