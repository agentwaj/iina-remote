import SwiftUI

struct AuroraBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 10 / 255, green: 10 / 255, blue: 18 / 255).opacity(0.90), location: 0.00),
                    .init(color: Color(red: 26 / 255, green: 22 / 255, blue: 42 / 255).opacity(0.90), location: 0.45),
                    .init(color: Color(red: 8 / 255, green: 8 / 255, blue: 12 / 255).opacity(0.90), location: 1.00),
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 150 / 255, green: 105 / 255, blue: 255 / 255).opacity(0.34), location: 0.00),
                    .init(color: .clear, location: 0.46),
                ]),
                center: UnitPoint(x: 0.20, y: 0.20),
                startRadius: 0,
                endRadius: 600
            )

            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 0 / 255, green: 220 / 255, blue: 255 / 255).opacity(0.28), location: 0.00),
                    .init(color: .clear, location: 0.52),
                ]),
                center: UnitPoint(x: 0.82, y: 0.28),
                startRadius: 0,
                endRadius: 650
            )

            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 190 / 255, green: 190 / 255, blue: 210 / 255).opacity(0.18), location: 0.00),
                    .init(color: .clear, location: 0.60),
                ]),
                center: UnitPoint(x: 0.50, y: 0.92),
                startRadius: 0,
                endRadius: 700
            )
        }
        .ignoresSafeArea()
    }
}

#Preview {
    NavigationStack {
        AuroraBackground()
            .navigationTitle("Aurora Background")
    }
}
