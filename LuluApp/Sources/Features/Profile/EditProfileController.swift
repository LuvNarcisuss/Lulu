import PhotosUI
import UIKit

@MainActor
final class EditProfileController: TravelScreen, PHPickerViewControllerDelegate {
    private let name = input("Display name")
    private let biography = multilineInput("Biography", height: 130)
    private let photoState = text("", 14, color: Palette.muted)
    private var photo: Data?
    private var uploadedPath: String?
    private var built = false
    private var accountID = ""
    private var photoGeneration = UUID()
    private var loading = false
    private var saving = false
    override func render() {
        guard !built else { return }
        super.render(); built = true; title = "Edit profile"; accountID = store.userID
        name.text = store.profile.string("display_name"); biography.text = store.profile.string("bio")
        content.addArrangedSubview(text("Your traveler story", 30, display: true))
        content.addArrangedSubview(text("Display name · up to 30 characters", 14, color: Palette.muted))
        content.addArrangedSubview(name)
        content.addArrangedSubview(text("Biography · up to 160 characters", 14, color: Palette.muted))
        content.addArrangedSubview(biography)
        content.addArrangedSubview(action("Choose avatar", icon: "icon-camera", filled: false) { [weak self] in self?.pickPhoto() })
        content.addArrangedSubview(photoState)
        content.addArrangedSubview(action("Save profile", icon: "icon-check") { [weak self] in self?.save() })
    }
    private func save() {
        guard !loading, !saving, accountID == store.userID else { return }
        let displayName = (name.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let bio = biography.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty, displayName.count <= 30, bio.count <= 160 else { notice("Enter a name up to 30 characters and a biography up to 160 characters."); return }
        run { [self] in
            saving = true
            defer { saving = false }
            if let photo, uploadedPath == nil { uploadedPath = try await store.upload(data: photo, contentType: "image/jpeg", purpose: "avatar") }
            guard accountID == store.userID, store.isAuthenticated else { return }
            var payload: [String: JSONValue] = ["display_name": .string(displayName), "bio": .string(bio)]
            if let uploadedPath { payload["avatar_path"] = .string(uploadedPath) }
            try await store.perform("profile.update", payload)
            navigationController?.popViewController(animated: true)
        }
    }
    private func pickPhoto() {
        guard !loading, !saving else { return }
        var configuration = PHPickerConfiguration(); configuration.filter = .images; configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration); picker.delegate = self
        present(picker, animated: true)
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else { return }
        loading = true; photoState.text = "Preparing photo…"
        let generation = UUID(); photoGeneration = generation
        loadTravelPhoto(result.itemProvider) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.photoGeneration == generation, self.accountID == self.store.userID else { return }
                self.loading = false
                switch result {
                case .success(let data): self.photo = data; self.uploadedPath = nil; self.photoState.text = "New avatar ready to save"
                case .failure(let error): self.photoState.text = error.localizedDescription
                }
            }
        }
    }
}
