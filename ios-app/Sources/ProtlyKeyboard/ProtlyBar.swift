import SwiftUI

/// The predictive bar. Sprint 4: the other reading of the current or last word, centered; tap flips it.
struct ProtlyBar: View {
    @ObservedObject var mode: ProtlyMode
    let flip: () -> Void

    var body: some View {
        HStack {
            Spacer()
            if let alt = mode.alternative, !alt.isEmpty {
                Button(action: flip) {
                    Text("\u{201C}\(alt)\u{201D}").lineLimit(1)
                }
                .foregroundStyle(.primary)
            }
            Spacer()
        }
        .frame(height: ProtlyGeometry.toolbarHeight)
    }
}
