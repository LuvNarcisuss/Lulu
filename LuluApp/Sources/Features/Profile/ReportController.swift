import UIKit

@MainActor
final class ReportController: TravelScreen {
    private let kind: String
    private let targetID: String
    private let details = multilineInput("Report details", height: 150)
    private let reasonSlot = column()
    private let status = text("", 14, color: Palette.muted)
    private let reasons = ["Harassment or bullying", "Hate or discrimination", "Sexual or harmful content", "Scam or impersonation", "Copyright concern", "Unsafe travel advice", "Other"]
    private var selected = 0
    private var built = false
    private var submitting = false
    init(store: TravelStore, kind: String, targetID: String) { self.kind = kind; self.targetID = targetID; super.init(store: store) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func render() {
        guard !built else { return }
        super.render(); built = true; title = "Report"
        content.addArrangedSubview(text("Help keep travel welcoming", 28, display: true))
        content.addArrangedSubview(text("Choose a reason and describe your concern. A submitted report is a saved request; it does not promise a review time or outcome.", 15, color: Palette.muted))
        content.addArrangedSubview(reasonSlot)
        content.addArrangedSubview(text("Details · up to 500 characters", 14, color: Palette.muted))
        content.addArrangedSubview(details)
        content.addArrangedSubview(action("Submit report", icon: "icon-report") { [weak self] in self?.submit() })
        content.addArrangedSubview(status)
        updateReasons()
    }
    private func updateReasons() {
        clearStack(reasonSlot)
        for (index, reason) in reasons.enumerated() {
            reasonSlot.addArrangedSubview(action(reason, icon: selected == index ? "icon-check" : nil, filled: selected == index) { [weak self] in
                guard let self, !self.submitting else { return }; self.selected = index; self.updateReasons()
            })
        }
    }
    private func submit() {
        guard !submitting else { return }
        let body = details.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.count <= 500 else { notice("Keep report details within 500 characters."); return }
        guard selected != reasons.count - 1 || !body.isEmpty else { notice("Please describe your concern."); return }
        let reason = reasons[selected]
        run { [self] in
            submitting = true
            defer { submitting = false }
            try await store.perform("safety.report", ["target_kind": .string(kind), "target_id": .string(targetID), "reason": .string(reason), "details": .string(body)])
            status.text = "Report submitted"
            navigationController?.popViewController(animated: true)
        }
    }
}
