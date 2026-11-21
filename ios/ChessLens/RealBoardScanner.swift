import Foundation
import CoreGraphics
import CoreImage
import CoreML
import Vision

/// Semantic corner order is a8, h8, h1, a1, regardless of camera orientation.
struct RealBoardGeometry {
    private let coefficients: [Double]
    let size: CGSize

    /// Sort location taps before assigning chess-square names, so marking
    /// opposite corners consecutively cannot create a crossed polygon.
    static func orderCorners(_ points: [CGPoint]) throws -> [CGPoint] {
        guard points.count == 4, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw ServiceError(message: "Tap all four corners of the playing area.")
        }
        let center = CGPoint(x: points.map(\.x).reduce(0, +) / 4, y: points.map(\.y).reduce(0, +) / 4)
        let ordered = points.sorted { atan2($0.y - center.y, $0.x - center.x) < atan2($1.y - center.y, $1.x - center.x) }
        try validate(ordered)
        return ordered
    }

    static func canonicalCorners(_ points: [CGPoint], a1Index: Int) throws -> [CGPoint] {
        guard points.indices.contains(a1Index) else {
            throw ServiceError(message: "Tap the marked corner that is a1, on White’s left.")
        }
        let ordered = try orderCorners(points)
        guard let origin = ordered.firstIndex(of: points[a1Index]) else {
            throw ServiceError(message: "Choose the a1 corner again.")
        }
        // Clockwise from a1 is a8, h8, h1 in an unmirrored photo from above.
        return [ordered[(origin + 1) % 4], ordered[(origin + 2) % 4], ordered[(origin + 3) % 4], ordered[origin]]
    }

    static func validate(_ corners: [CGPoint]) throws {
        guard corners.count == 4, corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite &&
            (0...1).contains($0.x) && (0...1).contains($0.y) }) else {
            throw ServiceError(message: "Mark all four corners inside the photo.")
        }
        var crosses: [CGFloat] = []
        var area: CGFloat = 0
        for i in 0..<4 {
            let a = corners[i], b = corners[(i + 1) % 4], c = corners[(i + 2) % 4]
            crosses.append((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x))
            area += a.x * b.y - b.x * a.y
        }
        guard abs(area) > 0.02,
              crosses.allSatisfy({ $0 > 0.00001 }) || crosses.allSatisfy({ $0 < -0.00001 }) else {
            throw ServiceError(message: "Tap four different outer corners of the playing squares. Make the board larger in the photo if needed.")
        }
    }

    init(normalizedCorners: [CGPoint], size: CGSize) throws {
        try Self.validate(normalizedCorners)
        self.size = size
        let board = [(0.0, 0.0), (8.0, 0.0), (8.0, 8.0), (0.0, 8.0)]
        var matrix = [[Double]]()
        for i in 0..<4 {
            let (x, y) = board[i]
            let u = Double(normalizedCorners[i].x * size.width), v = Double(normalizedCorners[i].y * size.height)
            matrix.append([x, y, 1, 0, 0, 0, -u * x, -u * y, u])
            matrix.append([0, 0, 0, x, y, 1, -v * x, -v * y, v])
        }
        for column in 0..<8 {
            let pivot = (column..<8).max { abs(matrix[$0][column]) < abs(matrix[$1][column]) }!
            guard abs(matrix[pivot][column]) > 1e-9 else {
                throw ServiceError(message: "Couldn't fit the board. Mark its four corners again.")
            }
            matrix.swapAt(column, pivot)
            let value = matrix[column][column]
            for j in column..<9 { matrix[column][j] /= value }
            for row in 0..<8 where row != column {
                let factor = matrix[row][column]
                for j in column..<9 { matrix[row][j] -= factor * matrix[column][j] }
            }
        }
        coefficients = (0..<8).map { matrix[$0][8] }
    }

    func point(x: Double, y: Double) -> CGPoint {
        let c = coefficients, denominator = c[6] * x + c[7] * y + 1
        return CGPoint(x: (c[0] * x + c[1] * y + c[2]) / denominator,
                       y: (c[3] * x + c[4] * y + c[5]) / denominator)
    }

    func crop(at index: Int) -> CGRect {
        let x = Double(index % 8), y = Double(index / 8)
        let points = [point(x: x, y: y), point(x: x + 1, y: y),
                      point(x: x + 1, y: y + 1), point(x: x, y: y + 1)]
        let left = points.map(\.x).min()!, right = points.map(\.x).max()!
        let top = points.map(\.y).min()!, bottom = points.map(\.y).max()!
        let w = right - left, h = bottom - top
        // Match training: preserve upright pieces above their base square.
        let minX = max(0, floor(left - 0.15 * w)), minY = max(0, floor(top - 1.25 * h))
        let maxX = min(size.width, ceil(right + 0.15 * w)), maxY = min(size.height, ceil(bottom + 0.10 * h))
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func rectifiedBoard(_ image: CGImage, corners: [CGPoint]) throws -> CGImage {
        try validate(corners)
        let vectors = corners.map { point in
            CIVector(x: point.x * CGFloat(image.width), y: (1 - point.y) * CGFloat(image.height))
        }
        let output = CIFilter(name: "CIPerspectiveCorrection", parameters: [
            kCIInputImageKey: CIImage(cgImage: image),
            "inputTopLeft": vectors[0], "inputTopRight": vectors[1],
            "inputBottomRight": vectors[2], "inputBottomLeft": vectors[3]
        ])?.outputImage
        guard let output, !output.extent.isInfinite, !output.extent.isEmpty,
              let board = CIContext().createCGImage(output, from: output.extent.integral) else {
            throw ServiceError(message: "Couldn't straighten the board. Mark the four corners again.")
        }
        return board
    }
}

enum RealBoardScanner {
    static let fallbackWarning = "The automatic scanner read this photo. Check the detected pieces before analysis."

    struct Unreliable: LocalizedError {
        var errorDescription: String? {
            "Couldn't read the board reliably. Your previous position is still open. Check the corners or try a clearer photo."
        }
    }

    static func loadModel(at url: URL) throws -> MLModel {
        let configuration = MLModelConfiguration(); configuration.computeUnits = .all
        let model = try MLModel(contentsOf: url, configuration: configuration)
        let expected = Set("PRNBQKprnbqk.".map(String.init))
        guard Set(model.modelDescription.classLabels as? [String] ?? []) == expected,
              let input = model.modelDescription.inputDescriptionsByName["image"]?.imageConstraint,
              input.pixelsWide == 128, input.pixelsHigh == 128 else {
            throw ServiceError(message: "The real-board model is missing or incompatible. Reinstall the app update.")
        }
        return model
    }

    static func recognize(image: CGImage, normalizedCorners: [CGPoint], modelURL: URL) throws -> Recognition {
        try recognize(image: image, normalizedCorners: normalizedCorners, model: loadModel(at: modelURL))
    }

    static func recognizeWithFallback(image: CGImage, corners: [CGPoint], model: MLModel,
                                      automatic: (CGImage) async throws -> Recognition) async throws -> Recognition {
        do {
            let result = try recognize(image: image, normalizedCorners: corners, model: model)
            let squares = try ChessPosition(fen: result.placement + " w - - 0 1").squares
            guard squares.filter({ $0 == "K" }).count == 1, squares.filter({ $0 == "k" }).count == 1,
                  squares.filter({ "PRNBQK".contains($0) }).count <= 16,
                  squares.filter({ "prnbqk".contains($0) }).count <= 16,
                  squares.filter({ $0 == "P" }).count <= 8, squares.filter({ $0 == "p" }).count <= 8,
                  result.uncertainSquares.count <= 20 else { throw Unreliable() }
            return result
        } catch is Unreliable {
            try Task.checkCancellation()
            let board = try RealBoardGeometry.rectifiedBoard(image, corners: corners)
            do {
                let result = try await automatic(board)
                // The crop is in chess-square order, as specified by the a1 marker.
                return Recognition(placement: result.placement, uncertainSquares: result.uncertainSquares,
                                   warnings: [fallbackWarning] + Array(result.warnings.dropFirst()))
            } catch is CancellationError { throw CancellationError() }
            catch { throw Unreliable() }
        }
    }

    static func recognize(image: CGImage, normalizedCorners: [CGPoint], model: MLModel) throws -> Recognition {
        let geometry = try RealBoardGeometry(normalizedCorners: normalizedCorners,
                                             size: CGSize(width: image.width, height: image.height))
        guard let probabilitiesName = model.modelDescription.predictedProbabilitiesName,
              let input = model.modelDescription.inputDescriptionsByName["image"]?.imageConstraint else {
            throw ServiceError(message: "The real-board model couldn't be opened.")
        }
        var squares: [String] = [], uncertain: [String] = []
        for index in 0..<64 {
            try Task.checkCancellation()
            let rectangle = geometry.crop(at: index)
            guard rectangle.width > 1, rectangle.height > 1, let tile = image.cropping(to: rectangle) else {
                throw ServiceError(message: "Couldn't read every square. Mark the board corners again.")
            }
            let feature = try MLFeatureValue(cgImage: tile, constraint: input,
                options: [.cropAndScale: VNImageCropAndScaleOption.scaleFill.rawValue])
            let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": feature]))
            let ranked = (output.featureValue(for: probabilitiesName)?.dictionaryValue ?? [:]).compactMap { key, value -> (String, Double)? in
                guard let code = key as? String else { return nil }
                return (code, value.doubleValue)
            }.sorted { $0.1 > $1.1 }
            guard let best = ranked.first else { throw ServiceError(message: "Couldn't identify a piece. Try a clearer photo.") }
            squares.append(best.0)
            // This checkpoint uses label smoothing and class balancing. On its
            // validation photos, correct empty squares commonly score near 0.62.
            if best.1 < 0.60 || (ranked.count > 1 && best.1 - ranked[1].1 < 0.25) {
                uncertain.append(ChessPosition.name(at: index))
            }
        }
        var position = ChessPosition.initial
        position.squares = squares
        let warnings = ["Scanned with the trained physical-piece model. Review every square, including pieces without orange dots.",
                        "Set whose turn it is, castling rights and en passant before analysis. A photo cannot show move history."]
        return Recognition(placement: position.placement, uncertainSquares: uncertain, warnings: warnings)
    }
}
