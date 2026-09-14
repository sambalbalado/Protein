import PhotosUI
import ProteinCore
import SwiftData
import SwiftUI
import UIKit

struct MealAnalysisView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var draft: EditableMealAnalysis?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var retryRequest: MealImageRequest?
    @State private var isLoading = false
    @State private var isShowingCamera = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var analysisTask: Task<Void, Never>?
    private let service: any MealAnalysisService

    init(service: any MealAnalysisService, initialDraft: EditableMealAnalysis? = nil, initialError: String? = nil) {
        self.service = service
        _draft = State(initialValue: initialDraft)
        _errorMessage = State(initialValue: initialError)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ProteinTheme.Spacing.large) {
                    disclosureCard
                    if isLoading { loadingCard }
                    else if draft != nil { reviewCard }
                    else { sourceCard }
                }
                .padding(ProteinTheme.Spacing.medium)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Photo estimate")
        }
        .tint(ProteinTheme.Color.accent)
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker(
                onImage: { image in
                    isShowingCamera = false
                    prepareAndAnalyze(image)
                },
                onCancel: { isShowingCamera = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            loadPhoto(item)
        }
        .alert("Estimate unavailable", isPresented: errorBinding) {
            if retryRequest != nil {
                Button("Retry") { retryAnalysis() }
            }
            Button("Choose another", role: .cancel) { retryRequest = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
        .alert("Saved", isPresented: savedBinding) {
            Button("OK") {}
        } message: {
            Text(savedMessage ?? "")
        }
        .onDisappear {
            analysisTask?.cancel()
            retryRequest = nil
            selectedPhoto = nil
        }
    }

    private var disclosureCard: some View {
        ProteinCard {
            HStack(alignment: .top, spacing: ProteinTheme.Spacing.medium) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(ProteinTheme.Color.accent)
                VStack(alignment: .leading, spacing: 6) {
                    Text("An editable estimate").font(.headline)
                    Text("A photo can only suggest foods, portions, and protein. Review every value before saving—it is never an exact fact.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var sourceCard: some View {
        ProteinCard {
            VStack(alignment: .leading, spacing: ProteinTheme.Spacing.medium) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose your meal photo").font(.title3.bold())
                    Text("Protein sends a resized, metadata-minimized copy to your configured secure proxy. The photo is never added to your tracker or kept after a successful analysis.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    MealPhotoSourceLabel(title: "Choose from Photos", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the system photo picker")

                Button(action: openCamera) {
                    MealPhotoSourceLabel(title: "Take a photo", systemImage: "camera")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the camera to photograph a meal")

                Label("Manual logging stays available offline from Today.", systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var loadingCard: some View {
        ProteinCard {
            VStack(spacing: ProteinTheme.Spacing.medium) {
                ProgressView().controlSize(.large)
                Text("Preparing a cautious estimate…").font(.headline)
                Text("The temporary upload is kept only in memory while this request is active.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Cancel", role: .cancel) { analysisTask?.cancel() }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preparing meal estimate. The temporary photo is kept only in memory.")
    }

    private var reviewCard: some View {
        ProteinCard {
            VStack(alignment: .leading, spacing: ProteinTheme.Spacing.medium) {
                HStack {
                    Text("Review each item").font(.title3.bold())
                    Spacer()
                    Text("\(formattedTotal) g").font(.title2.bold()).monospacedDigit()
                }
                if draft?.hasLowConfidenceItems == true {
                    Label("Low confidence—check the highlighted item carefully.", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                ForEach(Array((draft?.items ?? []).indices), id: \.self) { index in
                    if index > 0 { Divider() }
                    itemEditor(index)
                }
                ForEach(draft?.warnings ?? [], id: \.self) {
                    Label($0, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
                }
                PrimaryActionButton(title: "Confirm and save", systemImage: "checkmark") { confirmAndSave() }
                Button("Discard estimate", role: .destructive) {
                    draft = nil
                    retryRequest = nil
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func itemEditor(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: ProteinTheme.Spacing.small) {
            HStack {
                Text("Item \(index + 1)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                let confidence = draft?.items[index].confidence ?? 0
                Label(
                    confidence < 0.6 ? "Low confidence" : "\(Int(confidence * 100))% confidence",
                    systemImage: confidence < 0.6 ? "exclamationmark.triangle" : "checkmark.circle"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(confidence < 0.6 ? .orange : .secondary)
            }
            TextField("Food name", text: itemBinding(index, \.name)).textFieldStyle(.roundedBorder)
            TextField("Assumed portion", text: itemBinding(index, \.assumedPortion)).textFieldStyle(.roundedBorder)
            HStack {
                Text("Protein")
                Spacer()
                TextField("Grams", value: gramsBinding(index), format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 100)
                Text("g").foregroundStyle(.secondary)
            }
            Button("Remove item", systemImage: "trash", role: .destructive) {
                draft?.items.remove(at: index)
            }
            .font(.footnote)
        }
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = "The camera is unavailable on this device. Choose a photo from the library instead."
            return
        }
        retryRequest = nil
        isShowingCamera = true
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        analysisTask?.cancel()
        isLoading = true
        errorMessage = nil
        analysisTask = Task {
            do {
                selectedPhoto = nil
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    throw MealAnalysisError.invalidImage
                }
                let request = try MealImagePreprocessor.prepare(image)
                analysisTask = nil
                beginAnalysis(request)
            } catch is CancellationError {
                finish(with: MealAnalysisError.cancelled)
            } catch {
                finish(with: error)
            }
        }
    }

    private func prepareAndAnalyze(_ image: UIImage) {
        do {
            beginAnalysis(try MealImagePreprocessor.prepare(image))
        } catch {
            finish(with: error)
        }
    }

    private func beginAnalysis(_ request: MealImageRequest) {
        analysisTask?.cancel()
        retryRequest = request
        isLoading = true
        errorMessage = nil
        analysisTask = Task {
            do {
                let result = try await service.analyze(request)
                try Task.checkCancellation()
                draft = try result.validated()
                retryRequest = nil
                isLoading = false
            } catch is CancellationError {
                finish(with: MealAnalysisError.cancelled)
            } catch {
                finish(with: error)
            }
        }
    }

    private func retryAnalysis() {
        guard let retryRequest else { return }
        beginAnalysis(retryRequest)
    }

    private func finish(with error: Error) {
        isLoading = false
        if let analysisError = error as? MealAnalysisError,
           analysisError == .configurationMissing || analysisError == .invalidImage {
            retryRequest = nil
        }
        errorMessage = error.localizedDescription
    }

    private func confirmAndSave() {
        do {
            guard let draft else { return }
            let entries = try draft.entries(loggedAt: .now)
            try SwiftDataProteinRepository(context: modelContext).add(entries)
            self.draft = nil
            retryRequest = nil
            savedMessage = "\(entries.count) reviewed \(entries.count == 1 ? "entry" : "entries") added to today."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var formattedTotal: String {
        (draft?.totalProteinGrams ?? 0).formatted(.number.precision(.fractionLength(0...1)))
    }

    private var errorBinding: Binding<Bool> {
        .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var savedBinding: Binding<Bool> {
        .init(get: { savedMessage != nil }, set: { if !$0 { savedMessage = nil } })
    }

    private func itemBinding(_ index: Int, _ keyPath: WritableKeyPath<EditableMealItem, String>) -> Binding<String> {
        .init(
            get: { draft?.items[index][keyPath: keyPath] ?? "" },
            set: { draft?.items[index][keyPath: keyPath] = $0 }
        )
    }

    private func gramsBinding(_ index: Int) -> Binding<Double> {
        .init(
            get: { draft?.items[index].proteinGrams ?? 0 },
            set: { draft?.items[index].proteinGrams = $0 }
        )
    }
}

private struct MealPhotoSourceLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ProteinTheme.Spacing.medium)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: ProteinTheme.Radius.button))
    }
}

private enum MealAnalysisPreviewFixtures {
    static let success = try! MealAnalysisResult(
        foods: [.init(name: "Grilled chicken", assumedPortion: "One breast", proteinGrams: 38, confidence: 0.88)],
        totalProteinGrams: 38
    ).validated()
    static let lowConfidence = try! MealAnalysisResult(
        foods: [.init(name: "Mixed tofu dish", assumedPortion: "One bowl", proteinGrams: 22, confidence: 0.42)],
        totalProteinGrams: 22,
        warnings: ["Ingredients are partly obscured."]
    ).validated()
}

#Preview("Photo sources") { MealAnalysisView(service: MockMealAnalysisService(fixture: .success)).modelContainer(try! PersistenceController.makeInMemory()) }
#Preview("Success") { MealAnalysisView(service: MockMealAnalysisService(fixture: .success), initialDraft: MealAnalysisPreviewFixtures.success).modelContainer(try! PersistenceController.makeInMemory()) }
#Preview("Low confidence") { MealAnalysisView(service: MockMealAnalysisService(fixture: .lowConfidence), initialDraft: MealAnalysisPreviewFixtures.lowConfidence).modelContainer(try! PersistenceController.makeInMemory()) }
#Preview("Refusal") { MealAnalysisView(service: MockMealAnalysisService(fixture: .refusal), initialError: MealAnalysisError.refused("This image could not be analyzed as a meal.").localizedDescription).modelContainer(try! PersistenceController.makeInMemory()) }
#Preview("Timeout") { MealAnalysisView(service: MockMealAnalysisService(fixture: .timeout), initialError: MealAnalysisError.timedOut.localizedDescription).modelContainer(try! PersistenceController.makeInMemory()) }
#Preview("Malformed") { MealAnalysisView(service: MockMealAnalysisService(fixture: .malformed), initialError: MealAnalysisError.invalidResponse("Malformed fixture").localizedDescription).modelContainer(try! PersistenceController.makeInMemory()) }
#Preview("Offline") { MealAnalysisView(service: MockMealAnalysisService(fixture: .noNetwork), initialError: MealAnalysisError.noNetwork.localizedDescription).modelContainer(try! PersistenceController.makeInMemory()) }
