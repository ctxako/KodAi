//
//  kodaibackground.swift
//  kodai_macos
//
//  Created by Charles Thomas Xavier Austin III on 6/10/26.
//
import SwiftUI

struct KodaiBackground: View {
    @State private var drift = false

    private let base = Color(red: 28.0 / 255.0, green: 36.0 / 255.0, blue: 42.0 / 255.0)
    private let deepBlue = Color(red: 18.0 / 255.0, green: 35.0 / 255.0, blue: 45.0 / 255.0)
    private let graphite = Color(red: 72.0 / 255.0, green: 84.0 / 255.0, blue: 94.0 / 255.0)
    private let mist = Color(red: 118.0 / 255.0, green: 137.0 / 255.0, blue: 145.0 / 255.0)

    var body: some View {
        ZStack {
            base

            LinearGradient(
                colors: [
                    graphite.opacity(0.22),
                    deepBlue.opacity(0.48),
                    base.opacity(1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(mist.opacity(0.13))
                .frame(width: 520, height: 520)
                .blur(radius: 120)
                .offset(
                    x: drift ? -90 : -210,
                    y: drift ? -180 : -280
                )

            Circle()
                .fill(deepBlue.opacity(0.42))
                .frame(width: 620, height: 620)
                .blur(radius: 150)
                .offset(
                    x: drift ? 230 : 120,
                    y: drift ? 260 : 360
                )

            Circle()
                .fill(graphite.opacity(0.16))
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
