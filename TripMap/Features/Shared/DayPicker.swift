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
