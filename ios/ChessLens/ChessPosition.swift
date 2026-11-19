import Foundation

struct ChessPosition: Equatable {
    // Canonical order is a8…h8, a7…h7, …a1…h1, independent of display orientation.
    var squares: [String]
    var turn: String
    var castling: String
    var enPassant: String
    var halfmove: Int
    var fullmove: Int

    static let initial = try! ChessPosition(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    static let sample = try! ChessPosition(fen: "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4")

    init(fen: String) throws {
        let fields = fen.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard fields.count == 6 else { throw PositionError.invalidFEN }
        let rows = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard rows.count == 8 else { throw PositionError.invalidFEN }
        var board: [String] = []
        for row in rows {
            var expanded: [String] = []
            for char in row {
                if "12345678".contains(char), let count = Int(String(char)) {
                    expanded += Array(repeating: ".", count: count)
                } else if "KQRBNPkqrbnp".contains(char) {
                    expanded.append(String(char))
                } else {
                    throw PositionError.invalidFEN
                }
            }
            guard expanded.count == 8 else { throw PositionError.invalidFEN }
            board += expanded
        }
        guard ["w", "b"].contains(fields[1]),
              fields[2] == "-" || (!fields[2].isEmpty && fields[2].allSatisfy({ "KQkq".contains($0) }) && Set(fields[2]).count == fields[2].count),
              fields[3] == "-" || fields[3].range(of: "^[a-h][36]$", options: .regularExpression) != nil,
              let halfmove = Int(fields[4]), halfmove >= 0,
              let fullmove = Int(fields[5]), fullmove >= 1 else { throw PositionError.invalidFEN }
        self.squares = board
        self.turn = fields[1]
        self.castling = fields[2] == "-" ? "" : fields[2]
        self.enPassant = fields[3]
        self.halfmove = halfmove
        self.fullmove = fullmove
    }

    var placement: String {
        (0..<8).map { row in
            var result = "", empty = 0
            for piece in squares[(row * 8)..<(row * 8 + 8)] {
                if piece == "." { empty += 1 }
                else {
                    if empty > 0 { result += String(empty); empty = 0 }
                    result += piece
                }
            }
            if empty > 0 { result += String(empty) }
            return result
        }.joined(separator: "/")
    }

    var fen: String {
        let rights = "KQkq".filter { castling.contains($0) }
        return "\(placement) \(turn) \(rights.isEmpty ? "-" : rights) \(enPassant.isEmpty ? "-" : enPassant) \(halfmove) \(fullmove)"
    }

    mutating func setRight(_ right: String, enabled: Bool) {
        castling = castling.replacingOccurrences(of: right, with: "")
        if enabled { castling += right }
    }

    static func name(at index: Int) -> String {
        "\(Array("abcdefgh")[index % 8])\(8 - index / 8)"
    }

    static func index(of name: String) -> Int? {
        let chars = Array(name)
        guard chars.count == 2, let col = Array("abcdefgh").firstIndex(of: chars[0]),
              let rank = Int(String(chars[1])), (1...8).contains(rank) else { return nil }
        return (8 - rank) * 8 + col
    }
}

enum PositionError: LocalizedError {
    case invalidFEN
    var errorDescription: String? { "That FEN is incomplete. Include all six fields: board, turn, castling, en passant, and move counters." }
}

func pieceName(_ piece: String) -> String {
    guard piece != "." else { return "empty" }
    let names = ["k": "king", "q": "queen", "r": "rook", "b": "bishop", "n": "knight", "p": "pawn"]
    return "\(piece == piece.uppercased() ? "White" : "Black") \(names[piece.lowercased()] ?? "piece")"
}
