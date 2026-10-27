//
//  RunSection.swift
//  Monaka
//
//  DUPLICATED VERBATIM into MonakaShare/ (§10) — both forms use it.
//

import SwiftUI

/// The Run section both forms show, laid out like Calendar's event form:
/// one row per end, the date in a capsule that opens a calendar inline
/// beneath it. Inline rather than a popover, because anything presented
/// from the share sheet risks tearing it down (§8.1).
///
/// An end that isn't set reads "None" — a missing end is a first-class
/// reading of the run (§7.1), not a field left blank.
struct RunSection: View {
    @Binding var draft: SpotDraft

    private enum Edge { case start, end }

    /// One calendar open at a time, as in Calendar.
    @State private var expanded: Edge?

    var body: some View {
        Section {
            // Through `runStart` / `runEnd`, so pushing one end past the
            // other drags it along instead of leaving a backwards run.
            RunDateRow(
                "Starts",
                systemImage: "calendar",
                date: Binding(get: { draft.startDate }, set: { draft.runStart = $0 }),
                defaultDate: draft.defaultRunStart,
                isExpanded: isExpanded(.start)
            )
            RunDateRow(
                "Ends",
                systemImage: "flag.checkered",
                date: Binding(get: { draft.endDate }, set: { draft.runEnd = $0 }),
                defaultDate: draft.defaultRunEnd,
                isExpanded: isExpanded(.end)
            )
        } header: {
            Text("Run")
        } footer: {
            Text(draft.runFooter)
        }
    }

    private func isExpanded(_ edge: Edge) -> Binding<Bool> {
        Binding(
            get: { expanded == edge },
            set: { expanded = $0 ? edge : (expanded == edge ? nil : expanded) }
        )
    }
}

private struct RunDateRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    @Binding var date: Date?
    /// What "None" becomes when tapped.
    let defaultDate: Date
    @Binding var isExpanded: Bool

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        date: Binding<Date?>,
        defaultDate: Date,
        isExpanded: Binding<Bool>
    ) {
        self.title = title
        self.systemImage = systemImage
        _date = date
        self.defaultDate = defaultDate
        _isExpanded = isExpanded
    }

    var body: some View {
        IconRow(systemImage) {
            Text(title)
            Spacer()
            if let date {
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    // The stored yyyy/MM/dd, not the device locale's
                    // rendering a compact DatePicker would give (§6.1).
                    capsule(SpotDraft.dateStyle.format(date))
                        .foregroundStyle(isExpanded ? Color.accentColor : .primary)
                }
                .buttonStyle(.plain)

                // Same glyph as ClearableTextField's: back to "None".
                Button("Clear", systemImage: "xmark.circle.fill") {
                    withAnimation {
                        isExpanded = false
                        self.date = nil
                    }
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            } else {
                Button {
                    withAnimation {
                        date = defaultDate
                        isExpanded = true
                    }
                } label: {
                    capsule("None")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }

        if isExpanded, let date {
            DatePicker(
                title,
                selection: Binding(get: { date }, set: { self.date = $0 }),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
        }
    }

    private func capsule(_ text: String) -> some View {
        Text(text)
            .monospacedDigit()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemFill), in: .capsule)
    }
}
