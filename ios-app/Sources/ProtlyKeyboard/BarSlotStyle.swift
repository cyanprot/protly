import SwiftUI

/// One slot of the bar (audit B1, B8). The whole third of the width and the whole band above row 1 is the target,
/// not only the text. The label sits on a 44 pt row at the top of the band, so its center is 22 pt below the glass
/// top, where Apple's bar text is. A press shows Apple's rounded systemFill highlight behind the slot; the label is
/// not dimmed. No haptics (D6).
struct BarSlotStyle: ButtonStyle {
    /// The label's row, from the top of the band.
    static let rowHeight: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: Self.rowHeight)
            // One view whose style changes, not an `if`: the slot keeps its identity while pressed.
            .background(configuration.isPressed ? AnyShapeStyle(Color(.systemFill)) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: 8))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(.rect)
    }
}
