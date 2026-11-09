import UIKit
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation

final class CreationController: TravelScreen, PHPickerViewControllerDelegate {
    private let titleField = input("A title for your travel film")
    private let caption = UITextView()
    private let selectedLabel = text("Choose a video up to 3 minutes and 50 MB.", 15, color: Palette.muted)
    private let preview = UIImageView()
    private var fileURL: URL?
    private var coverData: Data?
    private var rightsAccepted = false
    private var loading = false
    private var submitting = false
    private var selectedPlaceID: String?
    private var importedRequestID = UUID()
    private var uploadedVideoPath: String?
    private var uploadedCoverPath: String?
    private let submissionID = UUID().uuidString.lowercased()
    override func viewDidLoad() {
        automaticRefresh = false
        title = "Create a travel film"
        caption.font = FontBook.font(17); caption.backgroundColor = Palette.paper; caption.layer.cornerRadius = 16
        caption.textContainerInset = UIEdgeInsets(top: 13, left: 12, bottom: 13, right: 12)
        caption.heightAnchor.constraint(equalToConstant: 130).isActive = true; caption.accessibilityLabel = "Video caption"
        preview.contentMode = .scaleAspectFill; preview.clipsToBounds = true; preview.layer.cornerRadius = 20
        preview.heightAnchor.constraint(equalToConstant: 210).isActive = true
        super.viewDidLoad()
    }
    override func render() {
        super.render()
        content.addArrangedSubview(text("Bring back a story.", 34, display: true))
        content.addArrangedSubview(text("Share a real place through your own lens.", 17, color: Palette.muted))
        content.addArrangedSubview(text("Title", 15, color: Palette.muted)); content.addArrangedSubview(titleField)
        content.addArrangedSubview(text("Caption", 15, color: Palette.muted)); content.addArrangedSubview(caption)
        if preview.image != nil { content.addArrangedSubview(preview) }
        content.addArrangedSubview(selectedLabel)
        let choose = action(loading ? "Reading your video…" : "Choose a video", icon: "icon-video", filled: false) { [weak self] in self?.chooseVideo() }
        choose.isEnabled = !loading && !submitting; content.addArrangedSubview(choose)
        let placeName = store.rows("places").first { $0.id == selectedPlaceID }?.string("name") ?? "Add a destination (optional)"
        content.addArrangedSubview(action(placeName, icon: "icon-location", filled: false) { [weak self] in self?.choosePlace() })
        content.addArrangedSubview(action(rightsAccepted ? "Content & sharing rights confirmed" : "Confirm content & sharing rights", icon: rightsAccepted ? "icon-check" : "icon-save", filled: false) { [weak self] in
            guard let self else { return }
            self.rightsAccepted.toggle(); self.render()
        })
        content.addArrangedSubview(text("Upload only travel footage you own or are licensed to share. Do not include private information or people without appropriate permission. Submissions remain private while awaiting actual review.", 14, color: Palette.muted))
        let submit = action(submitting ? "Uploading your film…" : "Submit for review", icon: "icon-send") { [weak self] in self?.submit() }
        submit.isEnabled = !loading && !submitting
        content.addArrangedSubview(submit)
    }
    private func chooseVideo() {
        guard !loading, !submitting else { return }
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos; config.selectionLimit = 1; config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config); picker.delegate = self; present(picker, animated: true)
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        loading = true; importedRequestID = UUID(); let identity = importedRequestID; render()
        provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
            var owned: URL?
            var copyError: Error? = error
            if let url {
                do {
                    let values = try url.resourceValues(forKeys: [.fileSizeKey])
                    guard let size = values.fileSize, size > 0, size <= 50 * 1024 * 1024 else { throw VideoImportError.size }
                    let target = FileManager.default.temporaryDirectory.appendingPathComponent("travel-" + UUID().uuidString).appendingPathExtension(url.pathExtension.isEmpty ? "mov" : url.pathExtension)
                    try FileManager.default.copyItem(at: url, to: target); owned = target
                } catch { copyError = error }
            }
            Task { @MainActor [weak self] in
                guard let self, self.importedRequestID == identity else { if let owned { try? FileManager.default.removeItem(at: owned) }; return }
                guard let owned else { self.loading = false; self.render(); self.notice(copyError?.localizedDescription ?? "The selected video could not be read."); return }
                do {
                    let asset = AVURLAsset(url: owned)
                    let duration = try await asset.load(.duration).seconds
                    let tracks = try await asset.loadTracks(withMediaType: .video)
                    guard duration.isFinite, duration > 0, duration <= 180, !tracks.isEmpty else { throw VideoImportError.duration }
                    let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 1080, height: 1080)
                    let image = try await generator.image(at: CMTime(seconds: min(1, duration / 2), preferredTimescale: 600)).image
                    guard self.importedRequestID == identity else { try? FileManager.default.removeItem(at: owned); return }
                    guard let cover = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else { throw VideoImportError.read }
                    if let previous = self.fileURL { try? FileManager.default.removeItem(at: previous) }
                    self.fileURL = owned; self.coverData = cover; self.preview.image = UIImage(cgImage: image)
                    self.uploadedVideoPath = nil; self.uploadedCoverPath = nil
                    self.selectedLabel.text = "\(Int(duration)) seconds · \(ByteCountFormatter.string(fromByteCount: Int64((try? Data(contentsOf: owned, options: .mappedIfSafe).count) ?? 0), countStyle: .file))"
                    self.loading = false; self.render()
                } catch {
                    try? FileManager.default.removeItem(at: owned); self.loading = false; self.render(); self.notice(error.localizedDescription)
                }
            }
        }
    }
    private func choosePlace() {
        var choices: [(String, Bool, () -> Void)] = [("No destination", false, { [weak self] in self?.selectedPlaceID = nil; self?.render() })]
        choices += store.rows("places").map { place in (place.string("name"), false, { [weak self] in self?.selectedPlaceID = place.id; self?.render() }) }
        present(TravelDialogController(title: "Choose a destination", message: "Link your video to a place travelers can explore.", choices: choices), animated: true)
    }
    private func submit() {
        guard !submitting, !loading else { return }
        let title = (titleField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = caption.text ?? ""
        guard !title.isEmpty, title.count <= 80, body.count <= 500, rightsAccepted, let url = fileURL, let coverData else {
            notice("Add a title up to 80 characters, a caption up to 500 characters, a valid travel video and confirm your sharing rights."); return
        }
        submitting = true; render()
        Task { [weak self] in
            guard let self else { return }
            do {
                if self.uploadedVideoPath == nil {
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    self.uploadedVideoPath = try await self.store.upload(data: data, contentType: url.pathExtension.lowercased() == "mov" ? "video/quicktime" : "video/mp4", purpose: "video")
                }
                if self.uploadedCoverPath == nil { self.uploadedCoverPath = try await self.store.upload(data: coverData, contentType: "image/jpeg", purpose: "cover") }
                try await self.store.perform("submission.create", ["id": .string(self.submissionID), "title": .string(title), "caption": .string(body), "video_path": .string(self.uploadedVideoPath ?? ""), "cover_path": .string(self.uploadedCoverPath ?? ""), "place_id": self.selectedPlaceID.map(JSONValue.string) ?? .null])
                self.submitting = false
                self.navigationController?.popViewController(animated: true)
            } catch { self.submitting = false; self.render(); self.notice(error.localizedDescription) }
        }
    }
    deinit { if let fileURL { try? FileManager.default.removeItem(at: fileURL) } }
}

private enum VideoImportError: LocalizedError {
    case size, duration, read
    var errorDescription: String? {
        switch self {
        case .size: return "Choose a video smaller than 50 MB."
        case .duration: return "Choose a readable video up to 3 minutes long."
        case .read: return "A cover could not be created for this video. Please choose another."
        }
    }
}
