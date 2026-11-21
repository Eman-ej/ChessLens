import SwiftUI

struct BoardCornersView: View {
    let photo: UIImage
    let onUse: ([CGPoint]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var points: [CGPoint] = []
    @State private var a1Index: Int?
    @State private var error: String?

    private var canonical: [CGPoint]? {
        guard let a1Index else { return nil }
        return try? RealBoardGeometry.canonicalCorners(points, a1Index: a1Index)
    }
    private var outline: [CGPoint] {
        points.count == 4 ? ((try? RealBoardGeometry.orderCorners(points)) ?? []) : []
    }
    private func label(for index: Int) -> String {
        guard let canonical, let location = canonical.firstIndex(of: points[index]) else { return String(index + 1) }
        return ["a8", "h8", "h1", "a1"][location]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(spacing: 6) {
                    Text(points.count < 4 ? "Tap any corner · \(points.count) of 4 marked" : (a1Index == nil ? "Now tap the a1 corner" : "Check the labels, then scan"))
                        .font(.headline).multilineTextAlignment(.center)
                    Text(points.count < 4
                         ? "Tap the four outer corners of the playing squares in any order. Leave the board’s border outside."
                         : "a1 is the corner on White’s left, normally a dark square. Tap its marker; the other labels are placed automatically.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(.horizontal)
                GeometryReader { proxy in
                    let scale = min(proxy.size.width / photo.size.width, proxy.size.height / photo.size.height)
                    let size = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
                    let origin = CGPoint(x: (proxy.size.width - size.width) / 2, y: (proxy.size.height - size.height) / 2)
                    ZStack {
                        Color.black.opacity(0.04)
                        Image(uiImage: photo).resizable().frame(width: size.width, height: size.height)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        Path { path in
                            for (index, point) in outline.enumerated() {
                                let location = CGPoint(x: origin.x + point.x * size.width, y: origin.y + point.y * size.height)
                                if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
                            }
                            if outline.count == 4 { path.closeSubpath() }
                        }.stroke(Theme.accent, lineWidth: 3).allowsHitTesting(false)
                        ForEach(points.indices, id: \.self) { index in
                            Button {
                                guard points.count == 4 else { return }
                                do {
                                    _ = try RealBoardGeometry.canonicalCorners(points, a1Index: index)
                                    a1Index = index; error = nil
                                } catch { self.error = error.localizedDescription }
                            } label: {
                                Text(label(for: index)).font(.caption.bold()).foregroundStyle(.black)
                                    .frame(minWidth: 42, minHeight: 42)
                                    .background(a1Index == index ? Theme.accent : Color.yellow, in: Circle())
                            }.buttonStyle(.plain)
                            .disabled(points.count < 4)
                            .accessibilityLabel("Corner \(index + 1), \(label(for: index)). Select as a1.")
                            .position(x: origin.x + points[index].x * size.width, y: origin.y + points[index].y * size.height)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard points.count < 4, size.width > 0, size.height > 0 else { return }
                        let point = CGPoint(x: (location.x - origin.x) / size.width,
                                            y: (location.y - origin.y) / size.height)
                        guard (0...1).contains(point.x), (0...1).contains(point.y) else { return }
                        guard points.allSatisfy({ hypot(($0.x - point.x) * size.width, ($0.y - point.y) * size.height) > 18 }) else {
                            error = "That corner is already marked. Tap a different corner."; return
                        }
                        points.append(point); a1Index = nil; error = nil
                        if points.count == 4 {
                            do { _ = try RealBoardGeometry.orderCorners(points) }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                    .accessibilityLabel("Board photo. Mark the four playing-area corners in any order, then select the a1 marker.")
                }
                HStack {
                    Button("Undo last corner") { if !points.isEmpty { points.removeLast(); a1Index = nil; error = nil } }.disabled(points.isEmpty)
                    Spacer()
                    Button("Start over") { points = []; a1Index = nil; error = nil }.disabled(points.isEmpty)
                }.font(.footnote).padding(.horizontal)
                if let error { Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal) }
                Button {
                    guard let canonical else { return }
                    dismiss(); onUse(canonical)
                } label: {
                    Label(a1Index == nil && points.count == 4 ? "Choose a1 to continue" : "Use corners & scan offline", systemImage: "viewfinder")
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                }.buttonStyle(.borderedProminent).disabled(canonical == nil).padding(.horizontal)
            }
            .padding(.bottom).navigationTitle("Mark board corners").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .tint(Theme.accent)
        }
    }
}
