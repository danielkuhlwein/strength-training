//
//  HealthKitWorkoutService.swift
//  strength-training
//
//  Created by Daniel Kuhlwein on 2026-02-26.
//

import Foundation
internal import HealthKit

@Observable
final class HealthKitWorkoutService {
    // MARK: - Public State

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    /// nil = never asked, true = authorized, false = denied
    private(set) var authorizationStatus: Bool?
    private(set) var isSessionActive = false
    private(set) var activeCalories: Double = 0
    private(set) var heartRate: Double?
    private(set) var elapsedSeconds: TimeInterval = 0

    // MARK: - Private State

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKWorkoutBuilder?
    private var sessionStartDate: Date?
    private var elapsedTimer: Timer?

    private let kIsHKSessionActive = "hk_isSessionActive"
    private let kHKWorkoutStartDate = "hk_workoutStartDate"

    // MARK: - Data Types

    private var typesToWrite: Set<HKSampleType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
        ]
    }

    private var typesToRead: Set<HKObjectType> {
        [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
        ]
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }

        do {
            try await healthStore.requestAuthorization(
                toShare: typesToWrite,
                read: typesToRead
            )
            let status = healthStore.authorizationStatus(for: HKObjectType.workoutType())
            authorizationStatus = (status == .sharingAuthorized)
            return authorizationStatus ?? false
        } catch {
            authorizationStatus = false
            return false
        }
    }

    func checkAuthorization() {
        guard isAvailable else {
            authorizationStatus = false
            return
        }
        let status = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        authorizationStatus = (status == .sharingAuthorized)
    }

    // MARK: - Workout Session Lifecycle

    func startWorkout() async throws {
        guard isAvailable, authorizationStatus == true else { return }

        if workoutSession != nil {
            await endWorkout()
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let session = try HKWorkoutSession(
            healthStore: healthStore,
            configuration: configuration
        )
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: configuration
        )

        self.workoutSession = session
        self.workoutBuilder = builder

        let startDate = Date()
        self.sessionStartDate = startDate

        session.prepare()
        session.startActivity(with: startDate)
        try await builder.beginCollection(at: startDate)

        isSessionActive = true

        UserDefaults.standard.set(true, forKey: kIsHKSessionActive)
        UserDefaults.standard.set(startDate, forKey: kHKWorkoutStartDate)

        startElapsedTimer()
    }

    func pauseWorkout() {
        workoutSession?.pause()
        isSessionActive = false
        stopElapsedTimer()
    }

    func resumeWorkout() {
        workoutSession?.resume()
        isSessionActive = true
        startElapsedTimer()
    }

    func endWorkout() async {
        guard let session = workoutSession, let builder = workoutBuilder else {
            clearState()
            return
        }

        let endDate = Date()
        session.end()

        do {
            try await builder.endCollection(at: endDate)
            try await builder.finishWorkout()
        } catch {
            print("HealthKit workout finish error: \(error)")
        }

        clearState()
    }

    func cleanUpOrphanedState() {
        let wasActive = UserDefaults.standard.bool(forKey: kIsHKSessionActive)
        if wasActive && workoutSession == nil {
            UserDefaults.standard.set(false, forKey: kIsHKSessionActive)
            UserDefaults.standard.removeObject(forKey: kHKWorkoutStartDate)
        }
    }

    // MARK: - Private

    private func startElapsedTimer() {
        stopElapsedTimer()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let start = self.sessionStartDate else { return }
            self.elapsedSeconds = Date().timeIntervalSince(start)
            self.updateStatistics()
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func updateStatistics() {
        guard let builder = workoutBuilder else { return }

        if let energyStats = builder.statistics(for: HKQuantityType(.activeEnergyBurned)) {
            activeCalories = energyStats.sumQuantity()?.doubleValue(
                for: .kilocalorie()
            ) ?? 0
        }

        if let hrStats = builder.statistics(for: HKQuantityType(.heartRate)) {
            heartRate = hrStats.mostRecentQuantity()?.doubleValue(
                for: HKUnit.count().unitDivided(by: .minute())
            )
        }
    }

    private func clearState() {
        stopElapsedTimer()
        workoutSession = nil
        workoutBuilder = nil
        sessionStartDate = nil
        isSessionActive = false
        activeCalories = 0
        heartRate = nil
        elapsedSeconds = 0

        UserDefaults.standard.set(false, forKey: kIsHKSessionActive)
        UserDefaults.standard.removeObject(forKey: kHKWorkoutStartDate)
    }
}
