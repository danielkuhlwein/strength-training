//
//  ContentView.swift
//  strength-training
//
//  Created by Daniel Kuhlwein on 2026-02-21.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var workoutViewModel: WorkoutViewModel?
    @State private var healthKitService = HealthKitWorkoutService()

    var body: some View {
        Group {
            if let vm = workoutViewModel {
                TabView {
                    Tab("Workout", systemImage: "dumbbell") {
                        WorkoutTabView(viewModel: vm)
                    }
                    Tab("History", systemImage: "clock") {
                        HistoryListView()
                    }
                    Tab("Progress", systemImage: "chart.line.uptrend.xyaxis") {
                        ProgressDashboardView()
                    }
                    Tab("Exercises", systemImage: "list.bullet") {
                        ExerciseLibraryView()
                    }
                    Tab("Settings", systemImage: "gear") {
                        SettingsView(healthKitService: healthKitService)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .onAppear {
            SeedData.seedIfNeeded(context: modelContext)
            if workoutViewModel == nil {
                workoutViewModel = WorkoutViewModel(modelContext: modelContext, healthKitService: healthKitService)
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(previewContainer)
}
