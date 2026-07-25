import SwiftUI

struct DayPicker: View {
    let days: [Day]
    @Binding var selectedDayID: Day.ID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(days) { day in
                    Button {
                        selectedDayID = day.id
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Day \(day.sequence)")
                                .font(.headline)
                            Text(day.date, format: .dateTime.month(.abbreviated).day())
                                .font(.caption)
                                .foregroundStyle(selectedDayID == day.id ? .primary : .secondary)
                        }
                        .frame(minWidth: 72, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            selectedDayID == day.id ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.09),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedDayID == day.id ? .isSelected : [])
                }
            }
            .padding(.horizontal)
        }
    }
}
struct TripDateRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let timeZone: TimeZone
    let onSave: (Date, Date) -> Bool
    @State private var startDate: Date
    @State private var endDate: Date

    init(
        startDate: Date,
        endDate: Date,
        timeZoneIdentifier: String,
        onSave: @escaping (Date, Date) -> Bool
    ) {
        timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        self.onSave = onSave
        _startDate = State(initialValue: startDate)
        _endDate = State(initialValue: endDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "開始日",
                    selection: $startDate,
                    displayedComponents: .date
                )
                DatePicker(
                    "終了日",
                    selection: $endDate,
                    in: startDate...,
                    displayedComponents: .date
                )

                Text("予定があるDayは日程から削除できません。先に予定を移動または削除してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .environment(\.timeZone, timeZone)
            .navigationTitle("旅行の日程を変更")
            .onChange(of: startDate) { _, newStartDate in
                if endDate < newStartDate {
                    endDate = newStartDate
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if onSave(startDate, endDate) {
                            dismiss()
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 240)
        #else
        .presentationDetents([.medium])
        #endif
        .accessibilityIdentifier("trip-date-range-editor")
    }
}
