import SwiftUI
import SwiftData
import AVFoundation

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var audioPlayer = AudioPlayerManager()
    @StateObject private var recordListViewModel = RecordListViewModel()
    @State private var showingFilePicker = false
    @State private var selectedRecord: RecordListModel?

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                headerView
                recordListView
                Spacer()
                if selectedRecord == nil {
                    addRecordButton
                }
            }
            if let record = selectedRecord {
                MiniPlayerView(
                    record: record,
                    audioPlayer: audioPlayer,
                    onDelete: {
                        deleteRecord(record)
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .onAppear {
            recordListViewModel.fetchEpisodes()
        }
    }

    private var headerView: some View {
        HStack {
            Text("AngelsRecord")
                .font(.largeTitle)
                .fontWeight(.bold)

            Spacer()
        }
        .padding()
    }

    private var recordListView: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(recordListViewModel.episodes, id: \.id) { episode in
                    episodeCard(for: episode)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, selectedRecord != nil ? 100 : 20)
        }
    }

    private func episodeCard(for episode: Episode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(episode.title)
                .font(.headline)
            Text(episode.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("업로드: \(formatted(date: episode.uploadedAt))")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .onTapGesture {
            let localURL = recordListViewModel.getLocalFileURL(for: episode.fileName)
            let asset = AVURLAsset(url: localURL)
            let duration = CMTimeGetSeconds(asset.duration)
            let record = RecordListModel(title: episode.title, artist: episode.description, duration: duration, fileURL: localURL)

            withAnimation(.spring()) {
                if selectedRecord?.id == record.id {
                    selectedRecord = nil
                    audioPlayer.stop()
                } else {
                    selectedRecord = record
                    audioPlayer.play(record)
                }
            }
        }
    }

    private var addRecordButton: some View {
        Button(action: {
            showingFilePicker = true
        }) {
            Text("add Record File")
                .font(.headline)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
        }
        .padding()
    }

    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destinationURL = documentsPath.appendingPathComponent(url.lastPathComponent)

            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: url, to: destinationURL)

                let asset = AVURLAsset(url: destinationURL)
                let duration = CMTimeGetSeconds(asset.duration)

                let newRecord = RecordListModel(
                    title: url.deletingPathExtension().lastPathComponent,
                    artist: "Unknown Artist",
                    duration: duration,
                    fileURL: destinationURL
                )

                modelContext.insert(newRecord)
                try? modelContext.save()

            } catch {
                print("Error importing file: \(error)")
            }

        case .failure(let error):
            print("File import failed: \(error)")
        }
    }

    private func deleteRecord(_ record: RecordListModel) {
        if audioPlayer.currentRecord?.id == record.id {
            audioPlayer.stop()
        }

        selectedRecord = nil

        if let fileURL = record.fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }

        modelContext.delete(record)
        try? modelContext.save()
    }
}
