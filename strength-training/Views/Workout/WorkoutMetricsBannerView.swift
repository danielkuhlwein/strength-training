//
//  WorkoutMetricsBannerView.swift
//  strength-training
//
//  Created by Daniel Kuhlwein on 2026-02-26.
//

import SwiftUI

struct WorkoutMetricsBannerView: View {
    let service: HealthKitWorkoutService

    var body: some View {
        if service.isSessionActive || service.elapsedSeconds > 0 {
            HStack(spacing: 20) {
                metricItem(
                    icon: "timer",
                    value: formattedDuration,
                    label: "Duration"
                )

                metricItem(
                    icon: "flame.fill",
                    value: "\(Int(service.activeCalories))",
                    label: "kcal",
                    tint: .orange
                )

                if let hr = service.heartRate {
                    metricItem(
                        icon: "heart.fill",
                        value: "\(Int(hr))",
                        label: "BPM",
                        tint: .red
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
    }

    private var formattedDuration: String {
        let total = Int(service.elapsedSeconds)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    @ViewBuilder
    private func metricItem(
        icon: String,
        value: String,
        label: String,
        tint: Color = .primary
    ) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(tint)
                Text(value)
                    .font(.title3.monospacedDigit().bold())
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
