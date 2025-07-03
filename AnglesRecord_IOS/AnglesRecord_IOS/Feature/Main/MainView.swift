import SwiftUI
import FirebaseStorage
import SwiftData
import AVFoundation

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var audioPlayer = AudioPlayerManager()
    @StateObject private var recordListViewModel = RecordListViewModel()
    @State private var showingFilePicker = false
    @State private var selectedRecord: RecordListModel?
    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var showingPlayerView = false
    @State private var isLoading = false
    @State private var isRefreshing = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    if isRefreshing {
                        ProgressView().padding(.vertical, 12)
                    }

                    podcastMainSection

                    Divider().padding(.horizontal)

                    if isLoading {
                        loadingSection
                    } else {
                        episodeListContent
                    }
                }
                .padding(.bottom, selectedRecord != nil ? 100 : 20)
            }
            .refreshable {
                await MainActor.run {
                    recordListViewModel.fetchAndSyncEpisodes(context: modelContext)
                    isRefreshing = false
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
                .onTapGesture { showingPlayerView = true }
                .fullScreenCover(isPresented: $showingPlayerView) {
                    if let selected = selectedRecord {
                        PlayerView(record: selected, audioPlayer: audioPlayer) {
                            showingPlayerView = false
                        }
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { handleFileImport($0) }
        .onAppear {
            loadInitialData()
        }
    }

    // MARK: - 섹션 구성

    private var podcastMainSection: some View {
        VStack(spacing: 0) {
            Image("mainimage_yet")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .cornerRadius(16)
                .padding(.top, 20)

            Text("전지적 씨팝 시점: 전팝시")
                .font(Font.SFPro.SemiBold.s16)
                .foregroundColor(Color("mainText"))
                .padding(.top, 16)

            Text("엔젤스")
                .font(Font.SFPro.Regular.s14)
                .foregroundColor(Color("subText"))
                .padding(.top, 6)

            Button(action: playLatestEpisode) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("최신 에피소드")
                }
                .font(Font.SFPro.SemiBold.s16)
                .foregroundColor(Color("mainText"))
                .padding(.vertical, 14)
                .padding(.horizontal, 74.5)
                .background(Color("iconBack"))
                .cornerRadius(12)
            }
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
    }

    private var loadingSection: some View {
        VStack(spacing: 20) {
            ProgressView().scaleEffect(1.2).padding(.top, 40)
            Text("데이터를 불러오는 중...")
                .font(Font.SFPro.Regular.s14)
                .foregroundColor(Color("subText"))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 300)
    }

    private var episodeListContent: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(recordListViewModel.episodes.enumerated()), id: \.element.id) { index, episode in
                VStack(spacing: 0) {
                    episodeRow(for: episode)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)

                    if index < recordListViewModel.episodes.count - 1 {
                        Divider().padding(.horizontal, 20)
                    }
                }
            }
        }
    }

    private func episodeRow(for episode: EpisodeModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(formatted(date: episode.uploadedAt))
                .font(Font.SFPro.SemiBold.s12)
                .foregroundColor(Color("subText"))

            Text(episode.title)
                .font(Font.SFPro.SemiBold.s16)
                .foregroundColor(Color("mainText"))
                .frame(width: 345, alignment: .leading)
                .lineLimit(2)

            Text(episode.desc)
                .font(Font.SFPro.Regular.s14)
                .foregroundColor(Color("subText"))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            playEpisode(episode)
        }
    }

    // MARK: - 헬퍼

    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
    }

    private func loadInitialData() {
        isLoading = true
        recordListViewModel.loadLocalEpisodes(context: modelContext)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { isLoading = false }
        }
    }

    private func playLatestEpisode() {
        guard let latestEpisode = recordListViewModel.episodes.first else { return }
        playEpisode(latestEpisode)
    }

    private func playEpisode(_ episode: EpisodeModel) {
        let localURL = recordListViewModel.getLocalFileURL(for: episode.fileName)
        let asset = AVURLAsset(url: localURL)
        let duration = CMTimeGetSeconds(asset.duration)

        let record = RecordListModel(
            title: episode.title,
            artist: episode.desc,
            duration: duration,
            fileURL: localURL
        )

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
