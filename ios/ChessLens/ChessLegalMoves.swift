import Foundation

enum ChessPromotion: String, CaseIterable {
    case queen = "q"
    case rook = "r"
    case bishop = "b"
    case knight = "n"
}

extension ChessPosition {
    func legalDestinations(from source: Int) -> Set<Int> {
        guard let side = Side(rawValue: turn) else { return [] }
        return Set(legalMoves(from: source, side: side).map(\.destination))
    }

    func isPromotion(from source: Int, to destination: Int) -> Bool {
        guard squares.indices.contains(source), squares.indices.contains(destination) else { return false }
        return (squares[source] == "P" && destination / 8 == 0)
            || (squares[source] == "p" && destination / 8 == 7)
    }

    func applyingMove(
        from source: Int, to destination: Int, promotion: ChessPromotion? = nil
    ) -> (position: ChessPosition, rookMove: (from: Int, to: Int)?)? {
        guard let side = Side(rawValue: turn),
              let move = legalMoves(from: source, side: side).first(where: { $0.destination == destination }),
              isPromotion(from: source, to: destination) == (promotion != nil) else { return nil }

        let piece = squares[source]
        let kind = piece.lowercased()
        let captured = squares[destination]
        let placed = promotion.map { side.piece($0.rawValue) } ?? piece
        var next = self
        next.squares = move.placing(placed, from: source, on: squares)
        next.turn = side.opponent.rawValue
        next.enPassant = ""
        if kind == "p" && abs(source - destination) == 16 {
            next.enPassant = Self.name(at: (source + destination) / 2)
        }
        next.halfmove = kind == "p" || captured != "." ? 0 : halfmove + (halfmove < Int.max ? 1 : 0)
        if side == .black && fullmove < Int.max { next.fullmove += 1 }

        switch kind {
        case "k":
            next.setRight(side.piece("k"), enabled: false)
            next.setRight(side.piece("q"), enabled: false)
        case "r":
            next.removeRookRight(at: source, side: side)
        default:
            break
        }
        if captured == side.opponent.piece("r") {
            next.removeRookRight(at: destination, side: side.opponent)
        }
        return (next, move.castlingRook)
    }

    private mutating func removeRookRight(at index: Int, side: Side) {
        switch index - side.homeRow * 8 {
        case 0: setRight(side.piece("q"), enabled: false)
        case 7: setRight(side.piece("k"), enabled: false)
        default: break
        }
    }

    private func legalMoves(from source: Int, side: Side) -> [Candidate] {
        guard squares.indices.contains(source) else { return [] }
        let piece = squares[source]
        let kind = piece.lowercased()
        guard "kqrbnp".contains(kind), !kind.isEmpty, piece == side.piece(kind),
              let king = squares.firstIndex(of: side.piece("k")),
              king == squares.lastIndex(of: side.piece("k")),
              let opponentKing = squares.firstIndex(of: side.opponent.piece("k")),
              opponentKing == squares.lastIndex(of: side.opponent.piece("k")) else { return [] }

        let moves: [Candidate]
        switch kind {
        case "p":
            moves = pawnMoves(from: source, side: side)
        case "n":
            moves = pieceMoves(from: source, directions: knightOffsets, range: 1, side: side)
        case "b":
            moves = pieceMoves(from: source, directions: diagonal, range: 7, side: side)
        case "r":
            moves = pieceMoves(from: source, directions: straight, range: 7, side: side)
        case "q":
            moves = pieceMoves(from: source, directions: straight + diagonal, range: 7, side: side)
        case "k":
            moves = pieceMoves(from: source, directions: straight + diagonal, range: 1, side: side)
                + castlingMoves(from: source, side: side)
        default:
            return []
        }

        return moves.filter { move in
            let board = move.placing(piece, from: source, on: squares)
            let kingSquare = kind == "k" ? move.destination : king
            return !isAttacked(kingSquare, by: side.opponent, on: board)
        }
    }

    private func pawnMoves(from source: Int, side: Side) -> [Candidate] {
        var moves: [Candidate] = []
        if let next = shifted(source, row: side.pawnStep, file: 0), squares[next] == "." {
            moves.append(Candidate(destination: next))
            let startRow = side.homeRow + side.pawnStep
            if source / 8 == startRow,
               let double = shifted(next, row: side.pawnStep, file: 0), squares[double] == "." {
                moves.append(Candidate(destination: double))
            }
        }
        for file in [-1, 1] {
            guard let target = shifted(source, row: side.pawnStep, file: file) else { continue }
            if canCapture(squares[target], as: side) {
                moves.append(Candidate(destination: target))
            } else if squares[target] == ".", target / 8 == side.opponent.homeRow - 2 * side.pawnStep,
                      target == Self.index(of: enPassant),
                      let captured = shifted(source, row: 0, file: file), squares[captured] == side.opponent.piece("p"),
                      let origin = shifted(target, row: side.pawnStep, file: 0), squares[origin] == "." {
                moves.append(Candidate(destination: target, capturedPawn: captured))
            }
        }
        // Promotion changes the piece placed on the destination, which has no effect on our king's safety.
        return moves
    }

    private func pieceMoves(from source: Int, directions: [Offset], range: Int, side: Side) -> [Candidate] {
        var moves: [Candidate] = []
        for direction in directions {
            for distance in 1...range {
                guard let target = shifted(source, row: direction.row * distance, file: direction.file * distance) else { break }
                let occupant = squares[target]
                if occupant == "." || canCapture(occupant, as: side) {
                    moves.append(Candidate(destination: target))
                }
                if occupant != "." { break }
            }
        }
        return moves
    }

    private func castlingMoves(from source: Int, side: Side) -> [Candidate] {
        let home = side.homeRow * 8
        let enemy = side.opponent
        guard source == home + 4, !isAttacked(source, by: enemy, on: squares) else { return [] }

        let options = [
            (right: "k", rookFile: 7, step: 1, emptyFiles: 5...6),
            (right: "q", rookFile: 0, step: -1, emptyFiles: 1...3),
        ]
        return options.compactMap { option in
            let rook = home + option.rookFile
            guard castling.contains(side.piece(option.right)), squares[rook] == side.piece("r"),
                  option.emptyFiles.allSatisfy({ squares[home + $0] == "." }) else { return nil }
            let transit = source + option.step
            var board = squares
            board[source] = "."
            board[transit] = side.piece("k")
            guard !isAttacked(transit, by: enemy, on: board) else { return nil }
            return Candidate(destination: source + 2 * option.step, castlingRook: (from: rook, to: transit))
        }
    }
}

private struct Candidate {
    let destination: Int
    var capturedPawn: Int?
    var castlingRook: (from: Int, to: Int)?

    func placing(_ piece: String, from source: Int, on squares: [String]) -> [String] {
        var board = squares
        board[source] = "."
        board[destination] = piece
        if let capturedPawn {
            board[capturedPawn] = "."
        }
        if let rook = castlingRook {
            board[rook.to] = board[rook.from]
            board[rook.from] = "."
        }
        return board
    }
}

private enum Side: String {
    case white = "w"
    case black = "b"

    var opponent: Side { self == .white ? .black : .white }
    var homeRow: Int { self == .white ? 7 : 0 }
    var pawnStep: Int { self == .white ? -1 : 1 }

    func piece(_ kind: String) -> String {
        self == .white ? kind.uppercased() : kind
    }
}

private typealias Offset = (row: Int, file: Int)
private let straight: [Offset] = [(1, 0), (-1, 0), (0, 1), (0, -1)]
private let diagonal: [Offset] = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
private let knightOffsets: [Offset] = [(2, 1), (2, -1), (-2, 1), (-2, -1), (1, 2), (1, -2), (-1, 2), (-1, -2)]

private func shifted(_ index: Int, row: Int, file: Int) -> Int? {
    let nextRow = index / 8 + row
    let nextFile = index % 8 + file
    guard (0..<8).contains(nextRow), (0..<8).contains(nextFile) else { return nil }
    return nextRow * 8 + nextFile
}

private func canCapture(_ piece: String, as side: Side) -> Bool {
    piece != "." && piece == side.opponent.piece(piece.lowercased()) && piece.lowercased() != "k"
}

private func isAttacked(_ target: Int, by enemy: Side, on board: [String]) -> Bool {
    func attackedBy(_ kind: String, from offsets: [Offset]) -> Bool {
        let piece = enemy.piece(kind)
        return offsets.contains { offset in
            guard let index = shifted(target, row: offset.row, file: offset.file) else { return false }
            return board[index] == piece
        }
    }

    if attackedBy("p", from: [(-enemy.pawnStep, -1), (-enemy.pawnStep, 1)])
        || attackedBy("n", from: knightOffsets)
        || attackedBy("k", from: straight + diagonal) {
        return true
    }

    func attackedAlong(_ directions: [Offset], by kind: String) -> Bool {
        let slider = enemy.piece(kind)
        let queen = enemy.piece("q")
        for direction in directions {
            var index = target
            while let next = shifted(index, row: direction.row, file: direction.file) {
                let piece = board[next]
                if piece == slider || piece == queen { return true }
                if piece != "." { break }
                index = next
            }
        }
        return false
    }

    return attackedAlong(straight, by: "r") || attackedAlong(diagonal, by: "b")
}

// Shared by local engine validation and SAN display. A recognized board must be
// checked before entering the C++ engine, which assumes a legal chess position.
extension ChessPosition {
    var isInCheck: Bool {
        guard let side = Side(rawValue: turn), let king = squares.firstIndex(of: side.piece("k")) else { return false }
        return isAttacked(king, by: side.opponent, on: squares)
    }

    var hasLegalMoves: Bool {
        squares.indices.contains { !legalDestinations(from: $0).isEmpty }
    }

    func validateForLocalAnalysis() throws {
        func invalid(_ detail: String) -> LocalAnalysisPositionError {
            LocalAnalysisPositionError(message: "Review the board before analysis: " + detail)
        }
        guard squares.count == 64, let side = Side(rawValue: turn),
              squares.filter({ $0 == "K" }).count == 1,
              squares.filter({ $0 == "k" }).count == 1 else {
            throw invalid("place exactly one king of each color.")
        }
        for color in [Side.white, Side.black] {
            guard squares.filter({ $0 == color.piece("p") }).count <= 8,
                  squares.filter({ $0 != "." && $0 == color.piece($0.lowercased()) }).count <= 16 else {
                throw invalid("there are too many pieces of one color.")
            }
        }
        guard !(Array(squares[0..<8]) + Array(squares[56..<64])).contains(where: { $0.lowercased() == "p" }) else {
            throw invalid("a pawn cannot be on the first or eighth rank.")
        }
        let otherKing = squares.firstIndex(of: side.opponent.piece("k"))!
        guard !isAttacked(otherKing, by: side, on: squares) else {
            throw invalid("the king of the side that just moved is in check. Check whose turn it is.")
        }
        for (right, king, rook, piece) in [("K",60,63,"R"),("Q",60,56,"R"),("k",4,7,"r"),("q",4,0,"r")] {
            if castling.contains(right), (squares[king] != (piece == "R" ? "K" : "k") || squares[rook] != piece) {
                throw invalid("remove castling rights that do not match the king and rook.")
            }
        }
        if enPassant != "-", !enPassant.isEmpty {
            guard let target = Self.index(of: enPassant), squares[target] == ".",
                  target / 8 == (turn == "w" ? 2 : 5),
                  squares[target + (turn == "w" ? 8 : -8)] == (turn == "w" ? "p" : "P"),
                  squares[target + (turn == "w" ? -8 : 8)] == "." else {
                throw invalid("clear the en passant square or set it to the last double pawn move.")
            }
        }
        guard halfmove <= 1_000_000, fullmove <= 1_000_000 else {
            throw invalid("the move counters are too large.")
        }
    }

    var isAutomaticDraw: Bool {
        if halfmove >= 150 { return true }
        let pieces = squares.enumerated().filter { $0.element != "." && $0.element.lowercased() != "k" }
        if pieces.isEmpty { return true }
        if pieces.count == 1, ["b", "n"].contains(pieces[0].element.lowercased()) { return true }
        if pieces.allSatisfy({ $0.element.lowercased() == "b" }) {
            return Set(pieces.map { ($0.offset / 8 + $0.offset % 8) % 2 }).count == 1
        }
        return false
    }

    func applyingUCI(_ move: String) -> ChessPosition? {
        let chars = Array(move)
        guard chars.count == 4 || chars.count == 5,
              let source = Self.index(of: String(chars[0...1])),
              let destination = Self.index(of: String(chars[2...3])) else { return nil }
        let promotion = chars.count == 5 ? ChessPromotion(rawValue: String(chars[4])) : nil
        if chars.count == 5 && promotion == nil { return nil }
        return applyingMove(from: source, to: destination, promotion: promotion)?.position
    }

    func san(forUCI move: String) -> String? {
        let chars = Array(move)
        guard chars.count >= 4, let source = Self.index(of: String(chars[0...1])),
              let destination = Self.index(of: String(chars[2...3])), let next = applyingUCI(move) else { return nil }
        let piece = squares[source], kind = piece.lowercased()
        var result: String
        if kind == "k", abs(source - destination) == 2 {
            result = destination > source ? "O-O" : "O-O-O"
        } else {
            let capture = squares[destination] != "." || (kind == "p" && source % 8 != destination % 8)
            result = kind == "p" ? "" : piece.uppercased()
            if kind != "p" {
                let alternatives = squares.indices.filter {
                    $0 != source && squares[$0] == piece && legalDestinations(from: $0).contains(destination)
                }
                if !alternatives.isEmpty {
                    if alternatives.allSatisfy({ $0 % 8 != source % 8 }) {
                        result += String(Array("abcdefgh")[source % 8])
                    } else if alternatives.allSatisfy({ $0 / 8 != source / 8 }) {
                        result += String(8 - source / 8)
                    } else { result += Self.name(at: source) }
                }
            } else if capture { result += String(Array("abcdefgh")[source % 8]) }
            if capture { result += "x" }
            result += Self.name(at: destination)
            if chars.count == 5 { result += "=" + String(chars[4]).uppercased() }
        }
        if next.isInCheck { result += next.hasLegalMoves ? "+" : "#" }
        return result
    }
}

struct LocalAnalysisPositionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
