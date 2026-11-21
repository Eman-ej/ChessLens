import Foundation

struct Recognition {
    let placement: String
    let uncertainSquares: [String]
    let warnings: [String]
}

struct Variation: Decodable, Identifiable {
    var id: String { move }
    let move: String
    let san: String
    let line: [String]
    let scoreForWhiteCp: Int?
    let mateForWhite: Int?
    let depth: Int

    var evaluation: String {
        if let mate = mateForWhite {
            if mate == 0 { return "Checkmate" }
            return "\(mate > 0 ? "White" : "Black") mates in \(abs(mate))"
        }
        guard let cp = scoreForWhiteCp else { return "No evaluation" }
        if abs(cp) < 10 { return "Approximately equal" }
        return String(format: "%@ +%.2f", cp > 0 ? "White" : "Black", Double(abs(cp)) / 100)
    }
}

struct Analysis: Decodable {
    let fen: String
    let status: String
    let engine: String
    let bestMove: String?
    let bestMoveSAN: String?
    let fromSquare: String?
    let toSquare: String?
    let variations: [Variation]

    var terminalMessage: String {
        switch status {
        case "checkmate": return "Checkmate. There are no legal moves."
        case "stalemate": return "Stalemate. The position is drawn."
        default: return "This position is a draw."
        }
    }
}

struct ServiceError: LocalizedError {
    let message: String
    let statusCode: Int?
    init(message: String, statusCode: Int? = nil) {
        self.message = message; self.statusCode = statusCode
    }
    var errorDescription: String? { message }
}

