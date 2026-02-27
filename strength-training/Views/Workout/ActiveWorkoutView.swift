//
//  ActiveWorkoutView.swift
//  strength-training
//
//  Created by Daniel Kuhlwein on 2026-02-21.
//

import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    @Bindable var viewModel: WorkoutViewModel
    // Fetch all exercises reactively — filter in Swift to avoid #Predicate enum issues
    @Query(sort: \Exercise.sortOrder) private var allExercises: [Exercise]
    @State private var expandedExerciseID: UUID?
    @State private var showFinishConfirmation = false
    @State private var showAddExercise = false
    @State private var addExercisePreselectedType: DayType = .arms

    private var dayType: DayType {
        viewModel.activeSession?.dayType ?? .arms
    }

    var body: some View {
        NavigationStack {
            // VStack keeps the picker outside the scroll view entirely.
            // Scroll content is physically below the picker, so it can never
            // reach the picker or nav bar — no z-fighting or overscroll bleed.
            VStack(spacing: 0) {
                TrainingModePickerView(selectedMode: $viewModel.selectedMode)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.systemGroupedBackground))

                WorkoutMetricsBannerView(service: viewModel.healthKitService)
                    .padding(.bottom, 4)

                ScrollView {
                    LazyVStack(spacing: 16, pinnedViews: .sectionHeaders) {
                        if dayType == .fullBody {
                            exerciseSection(for: .arms)
                            exerciseSection(for: .legs)
                        } else {
                            exerciseSection(for: dayType)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("\(dayType.rawValue) Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Workouts", systemImage: "chevron.backward") {
                        viewModel.suspendSession()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFinishConfirmation = true
                    } label: {
                        Text("Finish")
                            .fontWeight(.semibold)
                    }
                }
            }
            .confirmationDialog(
                "Finish Workout?",
                isPresented: $showFinishConfirmation,
                titleVisibility: .visible
            ) {
                Button("Finish Workout") {
                    viewModel.finishSession()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                let completedCount = completedExerciseCount
                Text("You completed \(completedCount) exercise\(completedCount == 1 ? "" : "s") this session.")
            }
            .sheet(isPresented: $showAddExercise) {
                AddExerciseView(preselectedDayType: addExercisePreselectedType)
            }
        }
    }

    @ViewBuilder
    private func exerciseSection(for sectionDayType: DayType) -> some View {
        Section {
            VStack(spacing: 0) {
                let exercises = allExercises.filter { $0.dayType == sectionDayType }
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                    ExerciseRowView(
                        exercise: exercise,
                        viewModel: viewModel,
                        isExpanded: Binding(
                            get: { expandedExerciseID == exercise.id },
                            set: { newValue in
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    expandedExerciseID = newValue ? exercise.id : nil
                                }
                            }
                        )
                    )
                    .padding(.top, 8)

                    if index < exercises.count - 1 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }

                Divider()
                    .padding(.leading, 16)

                Button {
                    addExercisePreselectedType = sectionDayType
                    showAddExercise = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle")
                        .foregroundStyle(.tint)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
        } header: {
            Text("\(sectionDayType.rawValue) Exercises")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 32)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGroupedBackground))
                // Gradient curtain that hangs 20 pt below the header into the
                // content area. Pinned headers render above scroll content, so
                // this overlay also sits above it — content fades as it scrolls
                // up toward the header rather than cutting off abruptly.
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [Color(.systemGroupedBackground), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 20)
                    .offset(y: 20)
                    .allowsHitTesting(false)
                }
        }
    }

    private var completedExerciseCount: Int {
        guard let session = viewModel.activeSession else { return 0 }
        return session.exerciseRecords.filter { !$0.sets.isEmpty }.count
    }
}
