import SwiftData
import SwiftUI

struct ParticipantsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredParticipant.displayName) private var participants: [StoredParticipant]
    @State private var editor: ParticipantEditorTarget?
    @State private var pendingDeletionID: UUID?
    @State private var errorMessage: String?
    @State private var handledCreationRequestID: UUID?
    private let creationRequestID: UUID?

    init(creationRequestID: UUID? = nil) {
        self.creationRequestID = creationRequestID
    }

    var body: some View {
        List {
            ForEach(participants) { participant in
                Button {
                    editor = ParticipantEditorTarget(participantID: participant.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(participant.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let note = participant.note, !note.isEmpty {
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("削除", role: .destructive) { pendingDeletionID = participant.id }
                }
                .contextMenu {
                    Button("削除", systemImage: "trash", role: .destructive) {
                        pendingDeletionID = participant.id
                    }
                }
            }
        }
        .overlay {
            if participants.isEmpty {
                ContentUnavailableView {
                    Label("Participantがいません", systemImage: "person.2")
                } description: {
                    Text("同行者を登録すると、次の旅行で割り当てられるようになります。")
                } actions: {
                    Button("Participantを追加", systemImage: "plus") {
                        editor = ParticipantEditorTarget(participantID: nil)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("People")
        .onAppear { handleCreationRequest(creationRequestID) }
        .onChange(of: creationRequestID) { _, requestID in
            handleCreationRequest(requestID)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Participantを追加", systemImage: "plus") {
                    editor = ParticipantEditorTarget(participantID: nil)
                }
            }
        }
        .sheet(item: $editor) { target in
            ParticipantEditorView(
                participant: target.participantID.flatMap { id in participants.first(where: { $0.id == id }) },
                onSave: saveParticipant
            )
        }
        .confirmationDialog(
            "\(pendingDeletionParticipant?.displayName ?? "このParticipant")を削除しますか？",
            isPresented: deletionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Participantを削除", role: .destructive) { deletePendingParticipant() }
            Button("キャンセル", role: .cancel) { pendingDeletionID = nil }
        } message: {
            Text("旅行への割り当て機能はまだありません。")
        }
        .alert("保存できませんでした", isPresented: errorAlert) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "不明なエラー")
        }
    }

    private var pendingDeletionParticipant: StoredParticipant? {
        participants.first(where: { $0.id == pendingDeletionID })
    }

    private var deletionConfirmation: Binding<Bool> {
        Binding(get: { pendingDeletionID != nil }, set: { if !$0 { pendingDeletionID = nil } })
    }

    private var errorAlert: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func saveParticipant(_ draft: ParticipantDraft) -> String? {
        let name = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "名前を入力してください。" }
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)

        if let id = draft.id, let participant = participants.first(where: { $0.id == id }) {
            participant.displayName = name
            participant.note = note.isEmpty ? nil : note
        } else {
            modelContext.insert(StoredParticipant(displayName: name, note: note.isEmpty ? nil : note))
        }
        do {
            try modelContext.save()
            return nil
        } catch {
            modelContext.rollback()
            return error.localizedDescription
        }
    }

    private func handleCreationRequest(_ requestID: UUID?) {
        guard let requestID,
              requestID != handledCreationRequestID else {
            return
        }
        handledCreationRequestID = requestID
        editor = ParticipantEditorTarget(participantID: nil)
    }

    private func deletePendingParticipant() {
        guard let participant = pendingDeletionParticipant else { return }
        modelContext.delete(participant)
        do {
            try modelContext.save()
            pendingDeletionID = nil
        } catch {
            modelContext.rollback()
            pendingDeletionID = nil
            errorMessage = error.localizedDescription
        }
    }
}

private struct ParticipantEditorTarget: Identifiable {
    let participantID: UUID?
    let id = UUID()
}

struct ParticipantDraft {
    var id: UUID?
    var displayName: String
    var note: String
}

struct ParticipantEditorView: View {
    let participant: StoredParticipant?
    let onSave: (ParticipantDraft) -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("表示名", text: $displayName)
                TextField("メモ", text: $note, axis: .vertical)
                    .lineLimit(3...6)
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(participant == nil ? "Participantを追加" : "Participantを編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .onAppear {
                displayName = participant?.displayName ?? ""
                note = participant?.note ?? ""
            }
        }
    }

    private func save() {
        errorMessage = onSave(ParticipantDraft(id: participant?.id, displayName: displayName, note: note))
        if errorMessage == nil {
            dismiss()
        }
    }
}
