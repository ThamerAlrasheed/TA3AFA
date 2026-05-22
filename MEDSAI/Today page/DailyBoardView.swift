import SwiftUI

struct DailyMedicationGroup: Identifiable, Equatable {
    let id: String
    let medicationID: String
    let name: String
    let doseText: String?
    let medicationForm: String?
    let visualShape: String?
    let visualColor: String?
    let visualBackgroundColor: String?
    let doses: [DailyDoseDisplayItem]
    let isPRN: Bool
}

struct DailyDoseDisplayItem: Identifiable, Equatable {
    let id: String
    let medicationID: String
    let scheduledAt: Date
    let displayTime: String
    let status: DoseDisplayStatus
}

enum DoseDisplayStatus: Equatable {
    case pending
    case taken
    case skipped
    case missed
}

struct DailyAppointmentGroup: Identifiable, Equatable {
    let id: String
    let type: AppointmentType
    let title: String
    let subtitle: String?
    let items: [DailyAppointmentDisplayItem]
}

struct DailyAppointmentDisplayItem: Identifiable, Equatable {
    let id: String
    let appointmentID: String
    let scheduledAt: Date
    let displayTime: String
    let isCompleted: Bool
}

struct DailyBoardView: View {
    let selectedDate: Date
    let medicationGroups: [DailyMedicationGroup]
    let appointmentGroups: [DailyAppointmentGroup]
    let showsDateHeader: Bool
    let onToggleDose: (DailyDoseDisplayItem) -> Void
    let onSkipDose: (DailyDoseDisplayItem) -> Void
    let onOpenMedication: (DailyMedicationGroup) -> Void
    let onToggleAppointment: (DailyAppointmentDisplayItem) -> Void
    let onOpenAppointment: (DailyAppointmentDisplayItem?) -> Void

    init(
        selectedDate: Date,
        medicationGroups: [DailyMedicationGroup],
        appointmentGroups: [DailyAppointmentGroup],
        showsDateHeader: Bool = true,
        onToggleDose: @escaping (DailyDoseDisplayItem) -> Void,
        onSkipDose: @escaping (DailyDoseDisplayItem) -> Void = { _ in },
        onOpenMedication: @escaping (DailyMedicationGroup) -> Void,
        onToggleAppointment: @escaping (DailyAppointmentDisplayItem) -> Void,
        onOpenAppointment: @escaping (DailyAppointmentDisplayItem?) -> Void
    ) {
        self.selectedDate = selectedDate
        self.medicationGroups = medicationGroups
        self.appointmentGroups = appointmentGroups
        self.showsDateHeader = showsDateHeader
        self.onToggleDose = onToggleDose
        self.onSkipDose = onSkipDose
        self.onOpenMedication = onOpenMedication
        self.onToggleAppointment = onToggleAppointment
        self.onOpenAppointment = onOpenAppointment
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if showsDateHeader {
                    Text(selectedDate.formatted(date: .complete, time: .omitted))
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.istsehTextPrimary)
                        .padding(.horizontal)
                }

                DailyMedicationSection(
                    groups: medicationGroups,
                    onToggleDose: onToggleDose,
                    onSkipDose: onSkipDose,
                    onOpenMedication: onOpenMedication
                )

                DailyAppointmentsSection(
                    groups: appointmentGroups,
                    onToggleAppointment: onToggleAppointment,
                    onOpenAppointment: onOpenAppointment
                )
            }
            .padding(.vertical, 16)
        }
        .avoidsTabBar()
        .background(appBackground)
    }

    private var appBackground: some View {
        LinearGradient(
            colors: [
                Color.istsehGreenSoft.opacity(0.45),
                Color.istsehPageBackground
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct DailyMedicationSection: View {
    let groups: [DailyMedicationGroup]
    let onToggleDose: (DailyDoseDisplayItem) -> Void
    let onSkipDose: (DailyDoseDisplayItem) -> Void
    let onOpenMedication: (DailyMedicationGroup) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Medications")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Color.istsehTextPrimary)
                .padding(.horizontal)

            if groups.isEmpty {
                DailyEmptyState(icon: "pills", title: "No medications scheduled for this day")
                    .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(groups) { group in
                            DailyMedicationCard(
                                group: group,
                                onToggleDose: onToggleDose,
                                onSkipDose: onSkipDose,
                                onOpenMedication: { onOpenMedication(group) }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

struct DailyMedicationCard: View {
    @Environment(\.layoutDirection) private var layoutDirection
    let group: DailyMedicationGroup
    let onToggleDose: (DailyDoseDisplayItem) -> Void
    let onSkipDose: (DailyDoseDisplayItem) -> Void
    let onOpenMedication: () -> Void

    private var isRTL: Bool { layoutDirection == .rightToLeft }

    private var fallbackText: String {
        if group.isPRN {
            return isRTL ? "عند الحاجة" : "As needed"
        } else {
            return isRTL ? "لم يتم تحديد وقت للجرعة" : "No dose time set"
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onOpenMedication) {
                VStack(spacing: 6) {
                    MedicationVisualView(
                        form: group.medicationForm,
                        shapeID: group.visualShape,
                        medicationColorID: group.visualColor,
                        backgroundColorID: group.visualBackgroundColor,
                        size: 44
                    )

                    Text(group.name)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.istsehTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if let doseText = group.doseText,
                       !doseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(doseText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(spacing: 8) {
                if group.doses.isEmpty {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: 6, height: 6)

                        Text(fallbackText)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .minimumScaleFactor(0.75)
                        
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(group.doses) { dose in
                        DailyMedicationDoseRow(item: dose, onToggle: { onToggleDose(dose) })
                            .contextMenu {
                                if dose.status == .pending || dose.status == .missed {
                                    Button {
                                        onSkipDose(dose)
                                    } label: {
                                        Label("Skip Dose", systemImage: "minus.circle")
                                    }
                                }
                            }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 126)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.istsehCard)
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.istsehCardStroke, lineWidth: 1)
        )
    }
}

struct DailyMedicationDoseRow: View {
    let item: DailyDoseDisplayItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(item.displayTime)
                .font(.caption)
                .foregroundStyle(Color.istsehTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 4)

            Button(action: onToggle) {
                statusIcon
                    .font(.system(size: 17, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityText)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .taken:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.istsehGreen)
        case .skipped:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.orange)
        case .missed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(Color.istsehGreenDark)
        }
    }

    private var accessibilityText: String {
        switch item.status {
        case .taken: return "Dose taken"
        case .skipped: return "Dose skipped"
        case .missed: return "Dose missed"
        case .pending: return "Dose pending"
        }
    }
}

struct DailyAppointmentsSection: View {
    let groups: [DailyAppointmentGroup]
    let onToggleAppointment: (DailyAppointmentDisplayItem) -> Void
    let onOpenAppointment: (DailyAppointmentDisplayItem?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appointments")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Color.istsehTextPrimary)
                .padding(.horizontal)

            if groups.isEmpty {
                DailyEmptyState(icon: "calendar", title: "No appointments for this day")
                    .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(groups) { group in
                            DailyAppointmentCard(
                                group: group,
                                onToggleAppointment: onToggleAppointment,
                                onOpenAppointment: onOpenAppointment
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

struct DailyAppointmentCard: View {
    let group: DailyAppointmentGroup
    let onToggleAppointment: (DailyAppointmentDisplayItem) -> Void
    let onOpenAppointment: (DailyAppointmentDisplayItem?) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: { onOpenAppointment(group.items.first) }) {
                VStack(spacing: 6) {
                    AppointmentTypeIconView(type: group.type, size: 44)

                    Text(group.title.isEmpty ? group.type.title : group.title)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.istsehTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if let subtitle = group.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(spacing: 8) {
                ForEach(group.items) { item in
                    DailyAppointmentTimeRow(
                        item: item,
                        onToggle: { onToggleAppointment(item) }
                    )
                }
            }
        }
        .padding(12)
        .frame(width: 140)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.istsehCard)
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.istsehCardStroke, lineWidth: 1)
        )
    }
}

struct AppointmentTypeIconView: View {
    let type: AppointmentType
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color.istsehGreenSoft)
                .frame(width: size, height: size)

            Text(type.emoji)
                .font(.system(size: size * 0.48))
        }
        .accessibilityLabel(type.title)
    }
}

struct DailyAppointmentTimeRow: View {
    let item: DailyAppointmentDisplayItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(item.displayTime)
                .font(.caption)
                .foregroundStyle(Color.istsehTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 4)

            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(item.isCompleted ? Color.istsehGreen : Color.istsehGreenDark)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "Appointment completed" : "Appointment pending")
        }
    }
}

struct DailyEmptyState: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.istsehGreenDark)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.istsehGreenSoft.opacity(0.55))
        )
    }
}

enum DailyBoardBuilder {
    static func buildMedicationGroups(
        medications: [LocalMed],
        doseItems: [DailyDoseDisplayItem],
        for date: Date,
        calendar: Calendar = .current
    ) -> [DailyMedicationGroup] {
        medications.compactMap { med in
            let dosesForMed = doseItems
                .filter {
                    $0.medicationID == med.id &&
                    calendar.isDate($0.scheduledAt, inSameDayAs: date)
                }
                .sorted { $0.scheduledAt < $1.scheduledAt }

            guard dosesForMed.isEmpty ? med.shouldShowOnDate(date, calendar: calendar) : true else {
                return nil
            }

            return DailyMedicationGroup(
                id: med.id,
                medicationID: med.id,
                name: DoseTextFormatter.medicationTitle(med.name),
                doseText: doseText(for: med),
                medicationForm: med.medicationForm,
                visualShape: med.visualShape,
                visualColor: med.visualColor,
                visualBackgroundColor: med.visualBackgroundColor,
                doses: dosesForMed,
                isPRN: med.scheduleMode.isPRN || med.asNeeded
            )
        }
    }

    static func buildAppointmentGroups(
        appointments: [Appointment],
        completedAppointmentIDs: Set<String>,
        for date: Date,
        calendar: Calendar = .current
    ) -> [DailyAppointmentGroup] {
        let itemsForDay = appointments
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date < $1.date }

        let grouped = Dictionary(grouping: itemsForDay) { appointment in
            appointment.type
        }

        return grouped.map { type, appointments in
            let displayItems = appointments.map { appointment in
                DailyAppointmentDisplayItem(
                    id: appointment.id,
                    appointmentID: appointment.id,
                    scheduledAt: appointment.date,
                    displayTime: appointment.date.formatted(date: .omitted, time: .shortened),
                    isCompleted: completedAppointmentIDs.contains(appointment.id)
                )
            }

            let subtitle = appointments.compactMap { appointment in
                [appointment.location, appointment.notes]
                    .compactMap { value in
                        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return trimmed.isEmpty ? nil : trimmed
                    }
                    .first
            }.first

            return DailyAppointmentGroup(
                id: type.rawValue,
                type: type,
                title: type.title,
                subtitle: subtitle,
                items: displayItems
            )
        }
        .sorted { $0.type.title < $1.type.title }
    }

    static func doseText(for med: LocalMed) -> String? {
        if let display = med.doseDisplay?.trimmingCharacters(in: .whitespacesAndNewlines), !display.isEmpty {
            return display
        }

        if let text = formatDoseText(amount: med.doseAmount, unit: med.doseAmountUnit ?? med.doseUnit) {
            return text
        }

        let trimmedDosage = med.dosage.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedDosage.isEmpty ? nil : trimmedDosage
    }

    static func formatDoseText(amount: Double?, unit: String?) -> String? {
        guard let amount else { return nil }

        let amountText: String
        if amount.truncatingRemainder(dividingBy: 1) == 0 {
            amountText = String(Int(amount))
        } else {
            amountText = String(amount)
        }

        let trimmedUnit = unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedUnit.isEmpty ? amountText : "\(amountText) \(trimmedUnit)"
    }
}

extension AppointmentType {
    var iconName: String {
        sfSymbol
    }

    var displayName: String {
        title
    }
}
