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
    /// Opens with the Visited calendar showing — for §4's screenshots only.
    var opensVisitedCalendar = false

    private enum Edge { case start, end, visited }

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
            // Next to the run it was a visit to, as the detail screen shows
            // it. Only a visited spot has one; the share sheet never does.
            if let visitedAt = draft.visitedAt {
                RunDateRow(
                    "Visited",
                    systemImage: "checkmark.circle",
                    date: Binding(get: { visitedAt }, set: { draft.visitedAt = $0 ?? visitedAt }),
                    defaultDate: visitedAt,
                    latest: .now,
                    isClearable: false,
                    isExpanded: isExpanded(.visited)
                )
            }
        } header: {
            Text("Run")
        } footer: {
            Text(draft.runFooter)
        }
        .onAppear {
            if opensVisitedCalendar, draft.visitedAt != nil { expanded = .visited }
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
    /// The last day the calendar offers — a visit can't be in the future.
    let latest: Date?
    /// Whether the date can go back to "None". A visit date can't: being
    /// visited is the detail screen's button, not a field here.
    let isClearable: Bool
    @Binding var isExpanded: Bool

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        date: Binding<Date?>,
        defaultDate: Date,
        latest: Date? = nil,
        isClearable: Bool = true,
        isExpanded: Binding<Bool>
    ) {
        self.title = title
        self.systemImage = systemImage
        _date = date
        self.defaultDate = defaultDate
        self.latest = latest
        self.isClearable = isClearable
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
                if isClearable {
                    Button("Clear", systemImage: "xmark.circle.fill") {
                        withAnimation {
                            isExpanded = false
                            self.date = nil
                        }
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }
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
            Group {
                let selection = Binding(get: { date }, set: { self.date = $0 })
                if let latest {
                    DatePicker(title, selection: selection, in: ...max(latest, date), displayedComponents: .date)
                } else {
                    DatePicker(title, selection: selection, displayedComponents: .date)
                }
            }
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
