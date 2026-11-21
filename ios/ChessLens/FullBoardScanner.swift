import Foundation
import CoreGraphics
import CoreML

struct FullBoardPrediction {
    let pieces: [String]
    let confidence: [Double]
    let margins: [Double]

    var placement: String {
        var position = ChessPosition.initial
        position.squares = pieces
        return position.placement
    }

    func checkedRecognition() throws -> Recognition {
        let white = pieces.filter { $0 != "." && $0 == $0.uppercased() }.count
        let black = pieces.filter { $0 != "." && $0 == $0.lowercased() }.count
        let uncertain = pieces.indices.filter { confidence[$0] < 0.85 || margins[$0] < 0.25 }
            .map { ChessPosition.name(at: $0) }
        guard pieces.filter({ $0 == "K" }).count == 1, pieces.filter({ $0 == "k" }).count == 1,
              white <= 16, black <= 16,
              pieces.filter({ $0 == "P" }).count <= 8, pieces.filter({ $0 == "p" }).count <= 8,
              uncertain.count <= 20 else {
            throw ServiceError(message: "This photo couldn't be read reliably. Your previous position has been kept. Try a clearer photo with all 64 squares visible.")
        }
        return Recognition(placement: placement, uncertainSquares: uncertain,
            warnings: ["Scanned offline with Fenformer. Check every piece, including squares without orange dots.",
                       "Set whose turn it is, castling and en passant before asking Stockfish. A photo cannot show move history."])
    }
}

actor FullBoardScanner {
    static let shared = FullBoardScanner(
        modelURL: Bundle.main.url(forResource: "FenformerBoard", withExtension: "mlmodelc"),
        framingURL: Bundle.main.url(forResource: "FenformerFraming", withExtension: "mlmodelc")
    )
    private let modelURL: URL?
    private let framingURL: URL?
    private var models: (board: MLModel, framing: MLModel)?
    private static let codes = Array(".PNBRQKpnbrqk").map(String.init)
    private static let boardSize = 644
    private static let maskSize = 320

    init(modelURL: URL?, framingURL: URL?) {
        self.modelURL = modelURL
        self.framingURL = framingURL
    }

    private func loadModels() throws -> (board: MLModel, framing: MLModel) {
        if let models { return models }
        guard let modelURL, let framingURL else {
            throw ServiceError(message: "The Fenformer scanner is missing. Reinstall this app update.")
        }
        let boardConfiguration = MLModelConfiguration()
        boardConfiguration.computeUnits = .cpuAndGPU
        let framingConfiguration = MLModelConfiguration()
        framingConfiguration.computeUnits = .cpuOnly
        let board = try MLModel(contentsOf: modelURL, configuration: boardConfiguration)
        let framing = try MLModel(contentsOf: framingURL, configuration: framingConfiguration)
        guard Self.hasShape(board.modelDescription.inputDescriptionsByName["image"], [1, 3, 644, 644]),
              Self.hasShape(board.modelDescription.outputDescriptionsByName["logits"], [1, 64, 13]),
              Self.hasShape(framing.modelDescription.inputDescriptionsByName["image"], [1, 3, 320, 320]),
              Self.hasShape(framing.modelDescription.outputDescriptionsByName["mask"], [1, 1, 320, 320]) else {
            throw ServiceError(message: "The Fenformer scanner has an incompatible format. Reinstall this app update.")
        }
        models = (board, framing)
        return (board, framing)
    }

    private static func hasShape(_ description: MLFeatureDescription?, _ shape: [Int]) -> Bool {
        guard let constraint = description?.multiArrayConstraint else { return false }
        return constraint.shape.map(\.intValue) == shape && constraint.dataType == .float32
    }

    func predict(image: CGImage) throws -> FullBoardPrediction {
        try Task.checkCancellation()
        let (board, framing) = try loadModels()
        let framed = try Self.frame(image, using: framing)
        let input = try Self.tensor(for: framed)
        try Task.checkCancellation()
        let features = try MLDictionaryFeatureProvider(dictionary: ["image": input])
        guard let values = try board.prediction(from: features).featureValue(for: "logits")?.multiArrayValue,
              values.shape.map(\.intValue) == [1, 64, 13], values.dataType == .float32 else {
            throw ServiceError(message: "Fenformer returned an incomplete board. Try another photo.")
        }
        let scores = (0..<64).map { square in
            Self.codes.indices.map { values[[0, NSNumber(value: square), NSNumber(value: $0)]].doubleValue }
        }
        guard scores.allSatisfy({ $0.allSatisfy(\.isFinite) }) else {
            throw ServiceError(message: "Fenformer couldn't finish this image. Try again.")
        }
        let rankings = scores.map { row in
            row.indices.sorted { row[$0] == row[$1] ? $0 < $1 : row[$0] > row[$1] }
        }
        let highest = rankings.map { $0[0] }
        let labels = Self.constrainedLabels(scores: scores, rankings: rankings, highest: highest)
        let probabilities = zip(scores, highest).map { row, best in
            let weights = row.map { exp($0 - row[best]) }
            let total = weights.reduce(0, +)
            return weights.map { $0 / total }
        }
        return FullBoardPrediction(
            pieces: labels.map { Self.codes[$0] },
            confidence: labels.indices.map { probabilities[$0][labels[$0]] },
            margins: labels.indices.map { square in
                guard labels[square] == highest[square] else { return 0 }
                let row = probabilities[square]
                return row[highest[square]] - row[rankings[square][1]]
            }
        )
    }

    func recognize(image: CGImage) throws -> Recognition {
        try predict(image: image).checkedRecognition()
    }

    // Fenformer's reference decoder maximizes summed logits over placements
    // with one king per side, nonadjacent kings, and no pawns on the back ranks.
    private static func constrainedLabels(scores: [[Double]], rankings: [[Int]], highest: [Int]) -> [Int] {
        let whiteKing = 6, blackKing = 12
        func allowedPair(_ white: Int, _ black: Int) -> Bool {
            abs(white / 8 - black / 8) > 1 || abs(white % 8 - black % 8) > 1
        }
        func pawnOnBackRank(_ label: Int, _ square: Int) -> Bool {
            (label == 1 || label == 7) && (square < 8 || square >= 56)
        }
        let white = highest.indices.filter { highest[$0] == whiteKing }
        let black = highest.indices.filter { highest[$0] == blackKing }
        if white.count == 1, black.count == 1, allowedPair(white[0], black[0]),
           !highest.indices.contains(where: { pawnOnBackRank(highest[$0], $0) }) {
            return highest
        }

        var labels = rankings.indices.map { square in
            rankings[square].first {
                $0 != whiteKing && $0 != blackKing && !pawnOnBackRank($0, square)
            }! // Empty is allowed on every square.
        }
        let base = labels.indices.map { scores[$0][labels[$0]] }
        let whiteGain = base.indices.map { scores[$0][whiteKing] - base[$0] }
        let blackGain = base.indices.map { scores[$0][blackKing] - base[$0] }
        var bestPair = (white: 0, black: 2)
        var best = -Double.infinity
        for w in whiteGain.indices {
            for b in blackGain.indices where allowedPair(w, b) {
                let score = whiteGain[w] + blackGain[b]
                if score > best { best = score; bestPair = (w, b) }
            }
        }
        labels[bestPair.white] = whiteKing
        labels[bestPair.black] = blackKing
        return labels
    }

    private static func frame(_ image: CGImage, using model: MLModel) throws -> ScannerPixels {
        let full = try ScannerPixels(sRGB: image).letterbox(to: boardSize)
        let small = try full.resized(width: maskSize, height: maskSize, using: .lanczos)
        let input = try tensor(for: small, normalizeForMask: true)
        try Task.checkCancellation()
        let features = try MLDictionaryFeatureProvider(dictionary: ["image": input])
        guard let mask = try model.prediction(from: features).featureValue(for: "mask")?.multiArrayValue,
              mask.shape.map(\.intValue) == [1, 1, maskSize, maskSize], mask.dataType == .float32 else {
            throw ServiceError(message: "Fenformer couldn't locate the board in this photo.")
        }
        let data = mask.dataPointer.assumingMemoryBound(to: Float.self)
        let row = mask.strides[2].intValue, column = mask.strides[3].intValue
        let values = (0..<(maskSize * maskSize)).map { data[$0 / maskSize * row + $0 % maskSize * column] }
        guard values.allSatisfy(\.isFinite) else {
            throw ServiceError(message: "Fenformer couldn't locate the board in this photo.")
        }
        guard let low = values.min(), let high = values.max(), high > low else { return full }
        let maskPixels = ScannerPixels(width: maskSize, height: maskSize, channels: 1,
            bytes: values.map { UInt8(min(255, max(0, ($0 - low) / (high - low) * 255))) })
        let resized = try maskPixels.resized(width: boardSize, height: boardSize, using: .lanczos)
        var left = boardSize, right = 0, top = boardSize, bottom = 0
        for index in resized.bytes.indices where resized.bytes[index] >= 128 {
            let x = index % boardSize, y = index / boardSize
            left = min(left, x); top = min(top, y)
            right = max(right, x + 1); bottom = max(bottom, y + 1)
        }
        guard left < right, top < bottom else { return full }
        let margin = Int(ceil(Double(max(right - left, bottom - top)) * 0.05))
        let crop = full.cropped(left: max(0, left - margin), top: max(0, top - margin),
                                right: min(boardSize, right + margin), bottom: min(boardSize, bottom + margin))
        return try crop.letterbox(to: boardSize)
    }

    private static func tensor(for image: ScannerPixels, normalizeForMask: Bool = false) throws -> MLMultiArray {
        let result = try MLMultiArray(shape: [1, 3, NSNumber(value: image.height), NSNumber(value: image.width)],
                                      dataType: .float32)
        let output = result.dataPointer.assumingMemoryBound(to: Float.self)
        let count = image.width * image.height
        let peak = normalizeForMask ? Float(max(1, image.bytes.max() ?? 0)) : 255
        let means: [Float] = [0.485, 0.456, 0.406]
        let deviations: [Float] = [0.229, 0.224, 0.225]
        for channel in 0..<3 {
            for index in 0..<count {
                let value = Float(image.bytes[index * 3 + channel]) / peak
                output[channel * count + index] = normalizeForMask ? (value - means[channel]) / deviations[channel] : value
            }
        }
        return result
    }
}

private struct ScannerPixels {
    let width: Int
    let height: Int
    let channels: Int
    let bytes: [UInt8]

    init(width: Int, height: Int, channels: Int, bytes: [UInt8]) {
        self.width = width; self.height = height; self.channels = channels; self.bytes = bytes
    }

    init(sRGB image: CGImage) throws {
        let w = image.width, h = image.height
        guard w > 0, h > 0, w <= 8192, h <= 8192, w * h <= 25_000_000 else {
            throw ServiceError(message: "Choose a photo under 25 megapixels.")
        }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let success = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8,
                    bytesPerRow: w * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard success else { throw ServiceError(message: "Couldn't prepare the photo's colors.") }
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        for index in 0..<(w * h) {
            rgb[index * 3] = pixels[index * 4]
            rgb[index * 3 + 1] = pixels[index * 4 + 1]
            rgb[index * 3 + 2] = pixels[index * 4 + 2]
        }
        self.init(width: w, height: h, channels: 3, bytes: rgb)
    }

    func letterbox(to size: Int) throws -> Self {
        let scale = Double(size) / Double(max(width, height))
        let w = max(1, Int((Double(width) * scale).rounded(.toNearestOrEven)))
        let h = max(1, Int((Double(height) * scale).rounded(.toNearestOrEven)))
        let image = try resized(width: w, height: h, using: .bilinear)
        guard w != size || h != size else { return image }
        var padded = [UInt8](repeating: 0, count: size * size * channels)
        let x = (size - w) / 2, y = (size - h) / 2
        for row in 0..<h {
            let source = row * w * channels
            let target = ((y + row) * size + x) * channels
            padded.replaceSubrange(target..<(target + w * channels),
                                   with: image.bytes[source..<(source + w * channels)])
        }
        return Self(width: size, height: size, channels: channels, bytes: padded)
    }

    func cropped(left: Int, top: Int, right: Int, bottom: Int) -> Self {
        let w = right - left, h = bottom - top
        if w == width && h == height { return self }
        var crop = [UInt8]()
        crop.reserveCapacity(w * h * channels)
        for row in top..<bottom {
            let start = (row * width + left) * channels
            crop.append(contentsOf: bytes[start..<(start + w * channels)])
        }
        return Self(width: w, height: h, channels: channels, bytes: crop)
    }

    enum Kernel {
        case bilinear, lanczos

        var radius: Double { self == .bilinear ? 1 : 3 }

        func weight(_ distance: Double) -> Double {
            let x = abs(distance)
            if self == .bilinear { return max(0, 1 - x) }
            if x == 0 { return 1 }
            guard x < 3 else { return 0 }
            return sin(.pi * x) / (.pi * x) * sin(.pi * x / 3) / (.pi * x / 3)
        }
    }

    // Pillow-style separable resampling with an eight-bit intermediate.
    private static func filters(input: Int, output: Int, kernel: Kernel) -> [(start: Int, weights: [Double])] {
        let ratio = Double(input) / Double(output), scale = max(1, ratio)
        let support = kernel.radius * scale
        return (0..<output).map { pixel in
            let center = (Double(pixel) + 0.5) * ratio - 0.5
            let start = max(0, Int(ceil(center - support)))
            let end = min(input - 1, Int(floor(center + support)))
            let weights = (start...end).map { kernel.weight((Double($0) - center) / scale) }
            let sum = weights.reduce(0, +)
            return (start, weights.map { $0 / sum })
        }
    }

    func resized(width w: Int, height h: Int, using kernel: Kernel) throws -> Self {
        if width == w && height == h { return self }
        var horizontal = bytes
        if width != w {
            horizontal = [UInt8](repeating: 0, count: w * height * channels)
            let filters = Self.filters(input: width, output: w, kernel: kernel)
            for y in 0..<height {
                if y.isMultiple(of: 64) { try Task.checkCancellation() }
                for (x, filter) in filters.enumerated() {
                    let source = (y * width + filter.start) * channels
                    let target = (y * w + x) * channels
                    for channel in 0..<channels {
                        var value = 0.0
                        for (offset, weight) in filter.weights.enumerated() {
                            value += Double(bytes[source + offset * channels + channel]) * weight
                        }
                        horizontal[target + channel] = UInt8(min(255, max(0, value.rounded())))
                    }
                }
            }
        }
        if height == h { return Self(width: w, height: h, channels: channels, bytes: horizontal) }
        let pitch = w * channels
        var output = [UInt8](repeating: 0, count: pitch * h)
        let filters = Self.filters(input: height, output: h, kernel: kernel)
        for (y, filter) in filters.enumerated() {
            if y.isMultiple(of: 64) { try Task.checkCancellation() }
            for x in 0..<pitch {
                var value = 0.0
                let source = filter.start * pitch + x
                for (offset, weight) in filter.weights.enumerated() {
                    value += Double(horizontal[source + offset * pitch]) * weight
                }
                output[y * pitch + x] = UInt8(min(255, max(0, value.rounded())))
            }
        }
        return Self(width: w, height: h, channels: channels, bytes: output)
    }
}
