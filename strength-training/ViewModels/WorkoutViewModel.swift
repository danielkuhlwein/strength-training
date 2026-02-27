//
//  WorkoutViewModel.swift
//  strength-training
//
//  Created by Daniel Kuhlwein on 2026-02-21.
//

import SwiftUI
import SwiftData

@Observable
final class WorkoutViewModel {
    var modelContext: ModelContext
    var activeSession: WorkoutSession?
    /// A session the user navigated away from without finishing.
    /// Kept alive so it can be resumed or explicitly abandoned.
    var suspendedSession: WorkoutSession?
    var selectedMode: TrainingMode = .highWeightLowReps
    let healthKitService: HealthKitWorkoutService

    init(modelContext: ModelContext, healthKitService: HealthKitWorkoutService) {
        self.modelContext = modelContext
        self.healthKitService = healthKitService
        healthKitService.checkAuthorization()
        healthKitService.cleanUpOrphanedState()
        resolveSessionState()
    }

    // MARK: - Session Lifecycle

    /// On launch: resume today's session, auto-complete stale ones, or start fresh.
    func resolveSessionState() {
        autoCompleteStaleSession()

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!

        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> {
                $0.isCompleted == false &&
                $0.date >= startOfToday &&
                $0.date < endOfToday
            }
        )
        descriptor.fetchLimit = 1

        activeSession = try? modelContext.fetch(descriptor).first
    }

    /// Auto-complete any sessions from previous days that were never finished.
    func autoCompleteStaleSession() {
        let startOfToday = Calendar.current.startOfDay(for: .now)

        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> {
                $0.isCompleted == false &&
                $0.date < startOfToday
            }
        )

        if let staleSessions = try? modelContext.fetch(descriptor) {
            for session in staleSessions {
                session.isCompleted = true
            }
            try? modelContext.save()
        }
    }

    func startSession(dayType: DayType) {
        // Resume a suspended session of the same type
        if let suspended = suspendedSession, suspended.dayType == dayType {
            activeSession = suspended
            suspendedSession = nil
            healthKitService.resumeWorkout()
            return
        }
        // Silently discard a suspended session that has no sets
        if let suspended = suspendedSession {
            if !suspended.exerciseRecords.contains(where: { !$0.sets.isEmpty }) {
                modelContext.delete(suspended)
                try? modelContext.save()
            }
            suspendedSession = nil
        }
        let session = WorkoutSession(dayType: dayType)
        modelContext.insert(session)
        try? modelContext.save()
        activeSession = session
        startHealthKitWorkout()
    }

    /// Move the active session to the background without completing it.
    func suspendSession() {
        suspendedSession = activeSession
        activeSession = nil
        healthKitService.pauseWorkout()
    }

    /// Discard the suspended session and immediately start a new one.
    func abandonSuspendedAndStart(dayType: DayType) {
        if let suspended = suspendedSession {
            modelContext.delete(suspended)
            try? modelContext.save()
            suspendedSession = nil
        }
        let session = WorkoutSession(dayType: dayType)
        modelContext.insert(session)
        try? modelContext.save()
        activeSession = session
        Task {
            await healthKitService.endWorkout()
            try? await healthKitService.startWorkout()
        }
    }

    /// Number of exercises in the suspended session that have at least one set.
    var suspendedInProgressExerciseCount: Int {
        suspendedSession?.exerciseRecords.filter { !$0.sets.isEmpty }.count ?? 0
    }

    /// True when the suspended session has at least one set logged.
    var suspendedHasSets: Bool {
        suspendedSession?.exerciseRecords.contains { !$0.sets.isEmpty } ?? false
    }

    func finishSession() {
        guard let session = activeSession else { return }
        session.isCompleted = true
        try? modelContext.save()
        activeSession = nil
        Task {
            await healthKitService.endWorkout()
        }
    }

    // MARK: - Exercises

    func exercises(for dayType: DayType) -> [Exercise] {
        // Fetch all exercises then filter in Swift — avoids #Predicate enum comparison issues
        let descriptor = FetchDescriptor<Exercise>(
            sortBy: [SortDescriptor(\Exercise.sortOrder)]
        )
        let all = (try? modelContext.fetch(descriptor)) ?? []
        if dayType == .fullBody { return all }
        return all.filter { $0.dayType == dayType }
    }

    // MARK: - Last Session Query

    /// The key query: what did I do last time for this exercise in this mode?
    /// Uses the existing relationship on Exercise instead of a fetch — avoids
    /// #Predicate limitations with optional chaining and enum rawValue.
    func lastRecord(for exercise: Exercise, mode: TrainingMode) -> ExerciseRecord? {
        exercise.records
            .filter { $0.trainingMode == mode && $0.session?.isCompleted == true }
            .sorted { ($0.session?.date ?? .distantPast) > ($1.session?.date ?? .distantPast) }
            .first
    }

    /// Get the current session's record for an exercise in the active mode.
    func currentRecord(for exercise: Exercise) -> ExerciseRecord? {
        guard let session = activeSession else { return nil }
        let modeRaw = selectedMode.rawValue
        return session.exerciseRecords.first {
            $0.exercise?.id == exercise.id &&
            $0.trainingMode.rawValue == modeRaw
        }
    }

    // MARK: - Set Logging

    func addSet(exercise: Exercise, weight: Double, reps: Int) {
        let record = findOrCreateRecord(for: exercise)
        let setNumber = record.sets.count + 1
        let set = SetRecord(setNumber: setNumber, weightLbs: weight, reps: reps)
        set.exerciseRecord = record
        record.sets.append(set)
        modelContext.insert(set)
        try? modelContext.save()
    }

    func deleteSet(_ set: SetRecord, from exercise: Exercise) {
        modelContext.delete(set)
        // Renumber remaining sets
        if let record = currentRecord(for: exercise) {
            let sorted = record.sets.sorted { $0.setNumber < $1.setNumber }
            for (index, s) in sorted.enumerated() {
                s.setNumber = index + 1
            }
        }
        try? modelContext.save()
    }

    // MARK: - Helpers

    private func startHealthKitWorkout() {
        Task {
            if healthKitService.authorizationStatus == nil {
                let authorized = await healthKitService.requestAuthorization()
                if authorized {
                    try? await healthKitService.startWorkout()
                }
            } else if healthKitService.authorizationStatus == true {
                try? await healthKitService.startWorkout()
            }
        }
    }

    private func findOrCreateRecord(for exercise: Exercise) -> ExerciseRecord {
        if let existing = currentRecord(for: exercise) {
            return existing
        }

        guard let session = activeSession else {
            fatalError("No active session when trying to create ExerciseRecord")
        }

        let record = ExerciseRecord(
            trainingMode: selectedMode,
            sortOrder: session.exerciseRecords.count
        )
        record.exercise = exercise
        record.session = session
        session.exerciseRecords.append(record)
        modelContext.insert(record)
        try? modelContext.save()
        return record
    }
}
