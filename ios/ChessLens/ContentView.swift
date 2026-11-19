import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel()
    @State private var showSettings = false
    @State private var fenInput = ""

    var body: some View {
        ScrollViewReader { scroll in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let busy = model.busy {
                    HStack(spacing: 12) { ProgressView(); Text(busy).font(.subheadline) }
                        .frame(maxWidth: .infinity, alignment: .leading).lensCard()
                        .accessibilityAddTraits(.updatesFrequently)
                }
                positionCard.id("position")
                if let analysis = model.analysis {
                    analysisCard(analysis) {
                        withAnimation { scroll.scrollTo("position", anchor: .top) }
                    }.id("analysis")
                }
                Text("A clearer board. A better next move.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .padding(20)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .tint(Theme.accent)
        .sheet(isPresented: $showSettings) { about }
        .alert("Something needs attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onChange(of: model.position.fen) { _, _ in model.invalidateAnalysis() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.stopAnalysis() }
        }
        .onChange(of: model.analysis?.fen) { _, fen in
            if fen != nil {
                withAnimation { scroll.scrollTo("analysis", anchor: .bottom) }
            }
        }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(.chessLensLogo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .accessibilityHidden(true)
                    Text("CHESSLENS").font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(2)
                }
                Text("Find your\nnext move.")
                    .font(.system(size: 38, weight: .semibold, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.title3)
                    .padding(12).background(Theme.card, in: Circle())
            }
            .accessibilityLabel("Settings")
            .disabled(model.busy != nil)
        }.padding(.bottom, 2)
    }

    private func step(_ number: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            Text(number).font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accent).padding(7)
                .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            Text(title).font(.headline)
        }
    }

    private var about: some View {
        NavigationStack {
            Form {
                Section("Offline analysis") {
                    Text("Set up a board or paste a FEN. Stockfish 19 analyzes positions on this iPhone without an account or internet connection.")
                }
                Section("Open source") {
                    Link("ChessLens source and license", destination: URL(string: "https://github.com/Eman-ej/ChessLens")!)
                    Link("Stockfish upstream source", destination: URL(string: "https://github.com/official-stockfish/Stockfish")!)
                }
            }
            .navigationTitle("About ChessLens")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSettings = false }
                }
            }
        }.tint(Theme.accent)
    }

    private var positionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                step("01", "Set up a position")
                Spacer(minLength: 4)
                Button { model.whiteAtBottom.toggle() } label: { Image(systemName: "arrow.up.arrow.down") }
                    .accessibilityLabel("Flip board display")
            }
            BoardView(model: model)
            Text(model.selectedSquare.map { "\(ChessPosition.name(at: $0)) selected · use the picker below to edit" }
                 ?? "Tap a piece, then a dot or ring to move.")
                .font(.footnote).foregroundStyle(.secondary)
            if model.selectedSquare != nil { piecePalette }
            if !model.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(model.warnings.enumerated()), id: \.offset) { entry in
                        Text(entry.element).font(.footnote).foregroundStyle(.secondary)
                    }
                    if !model.uncertainSquares.isEmpty {
                        Label("Check orange dots: " + model.uncertainSquares.joined(separator: ", "), systemImage: "exclamationmark.circle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
            }
            Text("Whose turn is it?").font(.subheadline.weight(.medium))
            Picker("Side to move", selection: $model.position.turn) {
                Text("White to move").tag("w"); Text("Black to move").tag("b")
            }.pickerStyle(.segmented)
            positionDetails
            Button("Try a sample position") { model.loadExample() }
                .font(.subheadline)
            Button { Task { await model.analyze() } } label: {
                Label("Find best move", systemImage: "sparkle.magnifyingglass")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent).foregroundStyle(Theme.background)
        }
        .lensCard()
        .disabled(model.busy != nil)
    }

    private var piecePalette: some View {
        VStack(spacing: 8) {
            ForEach(["KQRBNP", "kqrbnp"], id: \.self) { pieces in
                HStack(spacing: 6) {
                    ForEach(pieces.map { String($0) }, id: \.self) { piece in
                        pieceButton(piece)
                    }
                }
            }
            Button { model.setPiece(".") } label: {
                Label("Empty this square", systemImage: "eraser").font(.footnote)
            }.buttonStyle(.bordered)
        }
    }

    private func pieceButton(_ piece: String) -> some View {
        let isWhite = piece == piece.uppercased()
        let background: Color = isWhite ? Theme.darkSquare : Theme.lightSquare
        return Button { model.setPiece(piece) } label: {
            ChessPieceView(piece: piece)
                .frame(width: 32, height: 32)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(background, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Place \(pieceName(piece))")
    }

    private var positionDetails: some View {
        VStack(alignment: .leading, spacing: 13) {
            DisclosureGroup("Position details") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("For a custom position, set the castling rights and en passant square to match the game.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(["K", "Q", "k", "q"], id: \.self) { right in
                        Toggle(castlingLabel(right), isOn: Binding(
                            get: { model.position.castling.contains(right) },
                            set: { model.position.setRight(right, enabled: $0) }
                        )).font(.footnote)
                    }
                    TextField("En passant square, or -", text: $model.position.enPassant)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder).font(.footnote)
                }.padding(.top, 10)
            }.font(.subheadline)
            DisclosureGroup("Import or copy FEN") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.position.fen).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary).textSelection(.enabled)
                    Button("Copy current FEN") { UIPasteboard.general.string = model.position.fen }.font(.footnote)
                    TextField("Paste a complete FEN", text: $fenInput, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
                    Button("Load FEN") { model.loadFEN(fenInput) }.font(.footnote).disabled(fenInput.isEmpty)
                }.padding(.top, 10)
            }.font(.subheadline)
        }
    }

    private func castlingLabel(_ right: String) -> String {
        switch right {
        case "K": return "White can castle kingside"
        case "Q": return "White can castle queenside"
        case "k": return "Black can castle kingside"
        default: return "Black can castle queenside"
        }
    }

    private func analysisCard(_ analysis: Analysis, showBoard: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            step("02", "The engine's pick")
            if let san = analysis.bestMoveSAN {
                HStack(alignment: .firstTextBaseline) {
                    Text(san).font(.system(size: 46, weight: .semibold, design: .serif)).foregroundStyle(Theme.accent)
                    Spacer()
                    if let best = analysis.variations.first { Text(best.evaluation).font(.subheadline.weight(.medium)) }
                }
                if let from = analysis.fromSquare, let to = analysis.toSquare {
                    Text("\(model.position.turn == "w" ? "White" : "Black"): \(from) → \(to)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button(action: showBoard) {
                    Label("Show move on board", systemImage: "arrow.up.to.line")
                        .font(.subheadline)
                }
                ForEach(Array(analysis.variations.enumerated()), id: \.element.id) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("\(entry.offset + 1). \(entry.element.san)").font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(entry.element.evaluation).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(entry.element.line.joined(separator: "  "))
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    if entry.offset < analysis.variations.count - 1 { Divider() }
                }
                if let depth = analysis.variations.first?.depth {
                    Text("\(analysis.engine) · search depth \(depth)").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(analysis.terminalMessage).font(.headline)
            }
        }.lensCard()
    }
}
