//
//  kodaibackground.swift
//  kodai_macos
//
//  Created by Charles Thomas Xavier Austin III on 6/10/26.
//
import SwiftUI

struct KodaiBackground: View {
    @Environment(\.kodaiTheme) private var theme
    @State private var drift = false

    var body: some View {
        ZStack {
            theme.backgroundBase

            LinearGradient(
                colors: [
                    theme.backgroundRaised.opacity(0.22),
                    theme.backgroundDeep.opacity(0.48),
                    theme.backgroundBase.opacity(1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(theme.backgroundGlow.opacity(0.13))
                .frame(width: 520, height: 520)
                .blur(radius: 120)
                .offset(
                    x: drift ? -90 : -210,
                    y: drift ? -180 : -280
                )

            Circle()
                .fill(theme.backgroundDeep.opacity(0.42))
                .frame(width: 620, height: 620)
                .blur(radius: 150)
                .offset(
                    x: drift ? 230 : 120,
                    y: drift ? 260 : 360
                )

            Circle()
                .fill(theme.backgroundRaised.opacity(0.16))
                .frame(width: 460, height: 460)
                .blur(radius: 130)
                .offset(
                    x: drift ? 320 : 420,
                    y: drift ? -180 : -80
                )

            LinearGradient(
                colors: [
                    .white.opacity(0.045),
                    .clear,
                    .black.opacity(0.26)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}
