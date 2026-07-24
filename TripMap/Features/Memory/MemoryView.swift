import PhotosUI
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct MemoryView: View {
    let trip: Trip
    let onApplyPlan: (Trip) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var editorTarget: MemoryEditorTarget?
    @State private var errorMessage: String?

    private var summary: MemoryTripSummary {
        MemoryProjection.summary(for: trip)
    }

    private var candidates: [MemoryActivityEntry] {
        trip.orderedDays.flatMap { day in
            day.orderedActivities
                .filter { $0.progress == .planned }
                .map {
                    MemoryActivityEntry(
                        dayID: day.id,
                        daySequence: day.sequence,
                        activity: $0
                    )
                }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("旅行の記録") {
                    LabeledContent("訪問済み", value: "\(summary.visitedCount) / \(summary.totalActivityCount)")
                    LabeledContent("写真・感想あり", value: "\(summary.recordedCount)")
                    if summary.skippedCount > 0 {
                        LabeledContent("スキップ", value: "\(summary.skippedCount)")
                    }
                }

                if summary.entries.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "訪問の記録はまだありません",
                            systemImage: "photo.on.rectangle.angled",
                            description: Text("実際に訪れた予定を選び、写真や短い感想を残せます。")
                        )
                    }
                } else {
                    Section("訪問済み") {
                        ForEach(summary.entries) { entry in
                            Button {
                                editorTarget = MemoryEditorTarget(activityID: entry.activity.id)
                            } label: {
                                MemoryActivityRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("memory-recorded-\(entry.activity.id)")
                        }
                    }
                }

                if !candidates.isEmpty {
                    Section {
                        ForEach(candidates) { entry in
                            Button {
                                editorTarget = MemoryEditorTarget(activityID: entry.activity.id)
                            } label: {
                                Label(
                                    "Day \(entry.daySequence) · \(entry.activity.title)",
                                    systemImage: "checkmark.circle"
                                )
                            }
                            .accessibilityIdentifier("memory-candidate-\(entry.activity.id)")
                        }
                    } header: {
                        Text("訪問を記録")
                    } footer: {
                        Text("選択した予定を訪問済みにしてから、写真や感想を保存します。")
                    }
                }
            }
            .navigationTitle("Memory")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
        .sheet(item: $editorTarget) { target in
            if let activity = trip.days.flatMap(\.activities).first(where: { $0.id == target.activityID }) {
                MemoryEditorSheet(
                    activity: activity,
                    imageInventory: trip.imageStorageInventory
                ) { photoData, reflection in
                    saveMemory(
                        activityID: activity.id,
                        photoData: photoData,
                        reflection: reflection
                    )
                }
            }
        }
        .alert("思い出を保存できませんでした", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "不明なエラー")
        }
        .accessibilityIdentifier("memory-view")
    }

    private func saveMemory(
        activityID: Activity.ID,
        photoData: Data?,
        reflection: String?
    ) -> Bool {
        do {
            var updated = trip
            if updated.days.flatMap(\.activities)
                .first(where: { $0.id == activityID })?.progress != .completed {
                updated = try TripPlanEditor.setActivityProgress(
                    in: updated,
                    activityID: activityID,
                    progress: .completed
                )
            }
            updated = try TripPlanEditor.setActivityMemory(
                in: updated,
                activityID: activityID,
                photoData: photoData,
                reflection: reflection
            )
            if let error = onApplyPlan(updated) {
                errorMessage = error
                return false
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private struct MemoryEditorTarget: Identifiable {
    let activityID: Activity.ID
    var id: Activity.ID { activityID }
}

private struct MemoryActivityRow: View {
    let entry: MemoryActivityEntry

    var body: some View {
        HStack(spacing: 12) {
            MemoryPhoto(data: entry.activity.memoryPhotoData)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("Day \(entry.daySequence)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.activity.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let reflection = entry.activity.reflection {
                    Text(reflection)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text("写真や感想を追加")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MemoryEditorSheet: View {
    let activity: Activity
    let imageInventory: TripImageStorageInventory
    let onSave: (Data?, String?) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var reflection: String
    @State private var imageError: String?
    @State private var isBudgetConfirmationPresented = false

    init(
        activity: Activity,
        imageInventory: TripImageStorageInventory,
        onSave: @escaping (Data?, String?) -> Bool
    ) {
        self.activity = activity
        self.imageInventory = imageInventory
        self.onSave = onSave
        _photoData = State(initialValue: activity.memoryPhotoData)
        _reflection = State(initialValue: activity.reflection ?? "")
    }

    var body: some View {
        let photoPickerTitle = photoData == nil ? "写真を選ぶ" : "写真を変更"

        NavigationStack {
            Form {
                Section("訪問した予定") {
                    Label(activity.title, systemImage: "checkmark.circle.fill")
                }

                Section {
                    MemoryPhoto(data: photoData)
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(
                            photoPickerTitle,
                            systemImage: "photo"
                        )
                    }
                    .accessibilityIdentifier("memory-photo-picker")
                    if photoData != nil {
                        Button("写真を外す", systemImage: "trash", role: .destructive) {
                            photoData = nil
                            pickerItem = nil
                        }
                    }
                } header: {
                    Text("写真")
                } footer: {
                    Text(imageBudgetSummary)
                }

                Section {
                    TextField("短い感想", text: $reflection, axis: .vertical)
                        .lineLimit(3...8)
                        .onChange(of: reflection) { _, value in
                            if value.count > 500 {
                                reflection = String(value.prefix(500))
                            }
                        }
                } header: {
                    Text("感想")
                } footer: {
                    Text("\(reflection.count) / 500")
                }
            }
            .navigationTitle("思い出を記録")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if imageBudgetProposal.requiresConfirmation {
                            isBudgetConfirmationPresented = true
                        } else {
                            saveAndDismiss()
                        }
                    }
                    .accessibilityIdentifier("memory-save-button")
                }
            }
        }
        .task(id: pickerItem) {
            guard let pickerItem else { return }
            guard let original = try? await pickerItem.loadTransferable(type: Data.self),
                  let normalized = TripImageProcessor.normalizedJPEGData(from: original) else {
                imageError = "選択した写真を読み込めませんでした。"
                return
            }
            photoData = normalized
        }
        .alert("写真を読み込めませんでした", isPresented: Binding(
            get: { imageError != nil },
            set: { if !$0 { imageError = nil } }
        )) {
            Button("OK") { imageError = nil }
        } message: {
            Text(imageError ?? "不明なエラー")
        }
        .alert("画像容量の目安を超えます", isPresented: $isBudgetConfirmationPresented) {
            Button("この写真を使用") { saveAndDismiss() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text(
                "保存後は \(formattedByteCount(imageBudgetProposal.proposedTotalByteCount)) です。"
                    + " 写真は削除されませんが、将来の端末間同期に時間がかかる可能性があります。"
            )
        }
        .presentationDetents([.large])
        .accessibilityIdentifier("memory-editor")
    }

    private var imageBudgetProposal: TripImageBudgetProposal {
        imageInventory.proposal(
            replacing: activity.memoryPhotoData,
            with: photoData
        )
    }

    private var imageBudgetSummary: String {
        "Trip の画像 \(formattedByteCount(imageBudgetProposal.proposedTotalByteCount))"
            + " / 目安 \(formattedByteCount(TripImageStorageInventory.softLimitByteCount))"
    }

    private func formattedByteCount(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    private func saveAndDismiss() {
        if onSave(photoData, reflection) {
            dismiss()
        }
    }
}

private struct MemoryPhoto: View {
    let data: Data?

    var body: some View {
        Group {
            #if os(macOS)
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
            #elseif os(iOS)
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
            #else
            placeholder
            #endif
        }
        .clipped()
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [.pink.opacity(0.7), .orange.opacity(0.6)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.title2)
                .foregroundStyle(.white)
        }
    }
}
