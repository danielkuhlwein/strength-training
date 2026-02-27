//
//  SettingsView.swift
//  strength-training
//
//  Created by Daniel Kuhlwein on 2026-02-21.
//

import SwiftUI
import SwiftData
import UIKit
internal import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    var healthKitService: HealthKitWorkoutService

    @State private var isImporting = false
    @State private var pendingRestoreData: Data?
    @State private var showRestoreConfirmation = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var successMessage = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if healthKitService.isAvailable {
                        switch healthKitService.authorizationStatus {
                        case .none:
                            Button {
                                Task {
                                    await healthKitService.requestAuthorization()
                                }
                            } label: {
                                Label("Connect Apple Health", systemImage: "heart.fill")
                            }
                        case true?:
                            Label("Apple Health Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case false?:
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Apple Health Not Authorized", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                Text("Open Settings > Privacy > Health to grant access.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Label("Apple Health Not Available", systemImage: "heart.slash")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Health")
                } footer: {
                    Text("When connected, workouts are saved to Apple Health for Activity Ring credit and fitness tracking.")
                }

                Section {
                    Button(action: exportBackup) {
                        Label("Export Backup", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        isImporting = true
                    } label: {
                        Label("Restore from Backup", systemImage: "square.and.arrow.down")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Restore replaces all existing data with the contents of the selected backup file.")
                }
            }
            .navigationTitle("Settings")
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
            .confirmationDialog(
                "Restore Backup?",
                isPresented: $showRestoreConfirmation,
                titleVisibility: .visible
            ) {
                Button("Replace All Data", role: .destructive) {
                    if let data = pendingRestoreData {
                        performRestore(data: data)
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingRestoreData = nil
                }
            } message: {
                Text("This will permanently replace all current workout data. This cannot be undone.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("Success", isPresented: $showSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(successMessage)
            }
        }
    }

    // MARK: - Actions

    private func exportBackup() {
        do {
            let data = try BackupService.export(context: modelContext)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let filename = "strength-training-backup-\(formatter.string(from: .now)).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url)

            // Present UIActivityViewController directly from root — embedding it in a
            // SwiftUI .sheet causes a nested modal that renders blank.
            guard let rootVC = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows.first?.rootViewController else { return }

            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            rootVC.present(activityVC, animated: true)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Could not access the selected file."
                showError = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                pendingRestoreData = try Data(contentsOf: url)
                showRestoreConfirmation = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func performRestore(data: Data) {
        do {
            try BackupService.restore(from: data, context: modelContext)
            successMessage = "Backup restored successfully."
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
