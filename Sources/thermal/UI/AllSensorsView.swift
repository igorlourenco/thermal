import SwiftUI

// =============================================================================
// AllSensorsView.swift — every group, searchable (§4.3)
// Search filters on both the group label and raw sensor IDs, so "vrm"-style
// queries work where the IDs carry the meaning.
// =============================================================================

struct AllSensorsView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var model: ThermalModel

    var filtered: [GroupedReading] {
        let q = model.query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.allGroups }
        return model.allGroups.filter { row in
            row.group.specLabel.lowercased().contains(q)
                || row.sensors.contains { $0.name.lowercased().contains(q) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 12)

            groupList
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
    }

    private var searchField: some View {
        TextField("Search sensors", text: $model.query)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .foregroundStyle(theme.textStrong)
            .padding(.vertical, 8)
            .padding(.horizontal, 11)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.chipBg))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
    }

    private var groupList: some View {
        let rows = filtered
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if rows.isEmpty {
                    Text("No sensor matches that.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textDim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        groupRow(row, divider: index < rows.count - 1)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .card()
    }

    private func groupRow(_ row: GroupedReading, divider: Bool) -> some View {
        let peak = model.sessionPeak(for: row.group) ?? row.celsius
        let count = row.sensors.count

        return HStack(spacing: 10) {
            RampDot(color: theme.ramp(row.celsius))

            VStack(alignment: .leading, spacing: 3) {
                Text(row.group.specLabel)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.textStrong)
                Text("\(count) sensor\(count == 1 ? "" : "s") · peak \(model.fmt(peak))")
                    .microcaps(10, tracking: 0.1)
                    .foregroundStyle(theme.textDim)
            }

            Spacer()

            Text(model.fmt(row.celsius))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(theme.textMid)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .hoverFill()
        .onTapGesture { model.openDetail(row.group) }
        .overlay(alignment: .bottom) {
            if divider {
                Rectangle().fill(theme.rowBorder).frame(height: 1)
            }
        }
    }
}
