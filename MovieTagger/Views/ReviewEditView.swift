import SwiftUI

struct ReviewEditView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let model = appState.movieEditModel {
            ReviewEditContent(model: model)
                .environmentObject(appState)
        } else {
            Text("No movie selected.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Main content

private struct ReviewEditContent: View {
    @ObservedObject var model: MovieEditModel
    @EnvironmentObject var appState: AppState
    @State private var showPosterPicker = false
    @State private var showCancelConfirm = false
    @State private var showWriteConfirm = false

    private let formatter = FilenameFormatter()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Review & Edit Metadata")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                HStack(alignment: .top, spacing: 24) {
                    posterSection
                    fieldsSection
                }
                .padding()

                Divider().padding(.horizontal)

                namingSection.padding()
            }

            Divider()

            bottomBar
        }
    }

    // MARK: - Poster

    @ViewBuilder
    private var posterSection: some View {
        VStack(spacing: 12) {
            if let data = model.posterImageData, let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200)
                    .cornerRadius(8)
                    .shadow(radius: 4)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 200, height: 300)
                    .overlay(
                        VStack {
                            Image(systemName: "photo").font(.largeTitle).foregroundColor(.gray)
                            Text("No poster").foregroundColor(.gray)
                        }
                    )
            }

            if !model.availablePosters.isEmpty {
                Button("Choose Poster\u{2026}") { showPosterPicker = true }
                    .buttonStyle(.bordered)
                    .sheet(isPresented: $showPosterPicker) {
                        PosterPickerView(model: model, isPresented: $showPosterPicker)
                            .environmentObject(appState)
                    }
            }
        }
        .frame(width: 220)
    }

    // MARK: - Editable fields

    @ViewBuilder
    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledField("Title") {
                TextField("Title", text: $model.title)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 16) {
                LabeledField("Year") {
                    TextField("Year", text: $model.year)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                LabeledField("Runtime (min)") {
                    TextField("Runtime", text: $model.runtime)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }

            LabeledField("Overview") {
                TextEditor(text: $model.overview)
                    .font(.body)
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.gray.opacity(0.3))
                    )
            }

            LabeledField("Tagline") {
                TextField("Tagline", text: $model.tagline)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledField("Genres") {
                Text(model.genres.joined(separator: ", "))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
            }

            HStack(spacing: 16) {
                LabeledField("Content Rating") {
                    TextField("e.g. PG-13", text: $model.contentRating)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                LabeledField("Resolution") {
                    Picker("", selection: $model.resolution) {
                        ForEach(VideoResolution.allCases) { res in
                            Text(res.rawValue).tag(res)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                LabeledField("Studio") {
                    TextField("Studio", text: $model.studio)
                        .textFieldStyle(.roundedBorder)
                }
            }

            LabeledField("Cast") {
                TagListField(items: $model.cast, placeholder: "Add actor\u{2026}")
            }

            LabeledField("Directors") {
                TagListField(items: $model.directors, placeholder: "Add director\u{2026}")
            }

            HStack(spacing: 16) {
                LabeledField("Screenwriters") {
                    TagListField(items: $model.screenwriters, placeholder: "Add writer\u{2026}")
                }
                LabeledField("Producers") {
                    TagListField(items: $model.producers, placeholder: "Add producer\u{2026}")
                }
            }

            HStack(spacing: 16) {
                LabeledField("Original Title") {
                    Text(model.originalTitle).foregroundColor(.secondary)
                }
                LabeledField("Language") {
                    Text(model.originalLanguage).foregroundColor(.secondary)
                }
            }

            HStack(spacing: 16) {
                LabeledField("TMDb ID") {
                    Text(model.tmdbId).foregroundColor(.secondary).textSelection(.enabled)
                }
                LabeledField("IMDb ID") {
                    Text(model.imdbId.isEmpty ? "N/A" : model.imdbId)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Naming

    @ViewBuilder
    private var namingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Rename file on save", isOn: $model.renameFile)

            if model.renameFile {
                HStack {
                    Text("Pattern:").foregroundColor(.secondary)
                    TextField("Pattern", text: $model.namingPattern)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 8) {
                    Text("Tokens:").font(.caption).foregroundColor(.secondary)
                    ForEach(["{title}", "{year}", "{tmdb_id}", "{imdb_id}"], id: \.self) { token in
                        Button(token) { model.namingPattern += token }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                HStack {
                    Text("Preview:").foregroundColor(.secondary)
                    if let preview = previewName {
                        Text(preview).fontWeight(.medium)
                    } else {
                        Text("Invalid pattern \u{2014} file won\u{2019}t be renamed")
                            .foregroundColor(.orange)
                    }
                }
            }
        }
    }

    /// The exact name the rename step will produce — same formatting AND the same
    /// collision resolution as the actual write, so the preview never lies.
    private var previewName: String? {
        guard let name = formatter.formatIfValid(pattern: model.namingPattern, model: model) else {
            return nil
        }
        guard let source = appState.selectedFileURL else { return name }
        return formatter.resolveCollision(
            directoryURL: source.deletingLastPathComponent(),
            desiredName: name,
            excluding: source
        ).lastPathComponent
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            Button("Back") { appState.currentScreen = .movieSearch }
                .buttonStyle(.bordered)

            Spacer()

            Button("Cancel") { showCancelConfirm = true }
                .buttonStyle(.bordered)
                .confirmationDialog(
                    "Discard this session?",
                    isPresented: $showCancelConfirm
                ) {
                    Button("Discard Edits", role: .destructive) { appState.reset() }
                    Button("Keep Editing", role: .cancel) {}
                } message: {
                    Text("Your metadata edits will be lost.")
                }

            Button("Write Metadata") { showWriteConfirm = true }
                .buttonStyle(.borderedProminent)
                .confirmationDialog(
                    "Write metadata to \u{201C}\(appState.selectedFileURL?.lastPathComponent ?? "file")\u{201D}?",
                    isPresented: $showWriteConfirm
                ) {
                    Button("Write Metadata") { appState.currentScreen = .progress }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(writeConfirmMessage)
                }
        }
        .padding()
    }

    private var writeConfirmMessage: String {
        var message = "Metadata is written directly into the file and can\u{2019}t be undone."
        if model.renameFile, let preview = previewName,
           preview != appState.selectedFileURL?.lastPathComponent {
            message += " The file will then be renamed to \u{201C}\(preview)\u{201D}."
        }
        return message
    }
}

// MARK: - Reusable label helper

struct LabeledField<Content: View>: View {
    let label: String
    let content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.secondary)
            content()
        }
    }
}

// MARK: - Tag list field (editable list of names)

struct TagListField: View {
    @Binding var items: [String]
    let placeholder: String
    @State private var newItem = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Wrapped flow of tags
            FlowLayout(spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 4) {
                        Text(item)
                            .font(.caption)
                            .lineLimit(1)
                        Button {
                            items.remove(at: index)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12))
                    .cornerRadius(4)
                }
            }

            // Add new
            HStack(spacing: 4) {
                TextField(placeholder, text: $newItem)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit { addItem() }
                Button {
                    addItem()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addItem() {
        let trimmed = newItem.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        items.append(trimmed)
        newItem = ""
    }
}

/// Simple horizontal wrapping layout for tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            guard index < result.positions.count else { break }
            let pos = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private struct ArrangeResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x)
            totalHeight = y + rowHeight
        }

        return ArrangeResult(size: CGSize(width: totalWidth, height: totalHeight), positions: positions)
    }
}

// MARK: - Poster picker sheet

struct PosterPickerView: View {
    @ObservedObject var model: MovieEditModel
    @Binding var isPresented: Bool
    @EnvironmentObject var appState: AppState
    @State private var loadedImages: [String: NSImage] = [:]

    var body: some View {
        VStack(spacing: 0) {
            Text("Choose Poster")
                .font(.title3)
                .fontWeight(.semibold)
                .padding()

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
                    ForEach(model.availablePosters) { poster in
                        posterCell(poster)
                    }
                }
                .padding()
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.bordered)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }

    @ViewBuilder
    private func posterCell(_ poster: TMDbImage) -> some View {
        Button { selectPoster(poster) } label: {
            VStack {
                if let img = loadedImages[poster.filePath] {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 150)
                        .cornerRadius(6)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 100, height: 150)
                        .overlay(ProgressView())
                        .task { await loadThumbnail(poster) }
                }

                if model.selectedPosterPath == poster.filePath {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    model.selectedPosterPath == poster.filePath ? Color.accentColor : .clear,
                    lineWidth: 3
                )
        )
    }

    private func loadThumbnail(_ poster: TMDbImage) async {
        guard let url = URL(string: "https://image.tmdb.org/t/p/w185\(poster.filePath)") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = NSImage(data: data) {
                await MainActor.run { loadedImages[poster.filePath] = img }
            }
        } catch { }
    }

    private func selectPoster(_ poster: TMDbImage) {
        model.selectedPosterPath = poster.filePath
        guard let client = appState.tmdbClient else { return }

        Task {
            do {
                let url = try await client.posterURL(path: poster.filePath)
                let data = try await client.fetchImageData(from: url)
                await MainActor.run {
                    model.posterImageData = data
                    model.posterURL = url.absoluteString
                    isPresented = false
                }
            } catch {
                await MainActor.run { appState.showError(error.localizedDescription) }
            }
        }
    }
}
