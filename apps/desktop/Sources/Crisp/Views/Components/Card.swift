import SwiftUI

extension View {
    /// The app's standard rounded card surface. Centralizes the rounded-rectangle
    /// material fill that every card draws, so radius + material stay consistent.
    func cardBackground<S: ShapeStyle>(_ fill: S, cornerRadius: CGFloat = 14) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius).fill(fill))
    }

    /// The default card surface (subtle quaternary material).
    func cardBackground(cornerRadius: CGFloat = 14) -> some View {
        cardBackground(.quaternary.opacity(0.25), cornerRadius: cornerRadius)
    }
}
