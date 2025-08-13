import SwiftUI
import FirebaseStorage
import SwiftData
import AVFoundation

private func TS() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f.string(from: Date())
}

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var recordListViewModel: RecordListViewModel

    @StateObject private var audioPlayer = AudioPlayerManager()
    @State private var showingFilePicker = false
    @State private var selectedRecord: RecordListModel?
    @AppStorage("isDarkMode") private var isDarkMode = false
    @AppStorage("shouldFetchNewEpisodes") private var shouldFetchNewEpisodes = false
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

                    if recordListViewModel.isLoadingEpisodes {
                        loadingSection
                    } else {
                        episodeListContent
                    }
                }
                .padding(.bottom, selectedRecord != nil ? 100 : 20)
            }
            .refreshable {
                print("🔄 [\(TS())] pull-to-refresh 시작")
                await refreshNow(trigger: "pull-to-refresh")
            }

            if let record = selectedRecord {
                MiniPlayerView(
                    record: record,
                    audioPlayer: audioPlayer,
                    onDelete: { deleteRecord(record) },
                    onNextEpisode: { playNextEpisode() }
                )
                .onTapGesture { showingPlayerView = true }
                .fullScreenCover(isPresented: $showingPlayerView) {
                    if let selected = selectedRecord {
                        let nextItems = recordListViewModel.episodes
                            .map { ep in
                                let url = recordListViewModel.getLocalFileURL(for: ep.fileName)
                                let duration = CMTimeGetSeconds(AVURLAsset(url: url).duration)
                                return RecordListModel(title: ep.title, artist: formatted(date: ep.uploadedAt), duration: duration, fileURL: url)
                            }
                            .filter { $0.id != selected.id }

                        PlayerView(
                            record: selected,
                            audioPlayer: audioPlayer,
                            onDismiss: { showingPlayerView = false },
                            nextItems: nextItems
                        )
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
            print("👀 [\(TS())] MainView.onAppear")
            loadInitialData()
        }
        .onChange(of: shouldFetchNewEpisodes) { newVal in
            print("🔁 [\(TS())] shouldFetchNewEpisodes 변경: \(newVal)")
            if newVal {
                Task { await refreshNow(trigger: "flag-onchange") }
            }
        }
    }

    // MARK: - 새로고침 (completion 기반으로 정확히 대기)
    private func refreshNow(trigger: String) async {
        guard !isRefreshing else {
            print("⏳ [\(TS())] refreshNow(\(trigger)) SKIP: 이미 진행 중")
            return
        }
        isRefreshing = true
        print("🚀 [\(TS())] refreshNow 시작 by \(trigger)")

        await withCheckedContinuation { cont in
            recordListViewModel.fetchAndSyncEpisodes(context: modelContext) { ok in
                print("🧩 [\(TS())] fetchAndSyncEpisodes 완료 ok=\(ok)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    cont.resume()
                }
            }
        }

        if shouldFetchNewEpisodes {
            print("✅ [\(TS())] 자동 새로고침 1회 완료 → 플래그 OFF")
            shouldFetchNewEpisodes = false
        }

        isRefreshing = false
        print("🏁 [\(TS())] refreshNow 종료")
    }

    // MARK: - 초기 로딩
    private func loadInitialData() {
        print("📦 [\(TS())] 로컬 먼저 로드")
        recordListViewModel.loadLocalEpisodes(context: modelContext)

        if shouldFetchNewEpisodes {
            print("📥 [\(TS())] 푸시 감지됨 → 자동 동기화")
            Task { await refreshNow(trigger: "onAppear-flag") }
        }
    }

    // MARK: - 섹션 구성

    private var podcastMainSection: some View {
        VStack(spacing: 0) {
            Image("mainimage_yet")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .cornerRadius(8)
                .padding(.top, 41)
                .cornerRadius(8)

            Text("전지적 씨팝 시점: 전팝시")
                .font(Font.SFPro.SemiBold.s16)
                .foregroundColor(Color("mainText"))
                .padding(.top, 20)

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
                .cornerRadius(8)
            }
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
    }

    private var loadingSection: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("에피소드 불러오는 중...")
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
        .onTapGesture { playEpisode(episode) }
    }

    // MARK: - 헬퍼

    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
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

    private func playNextEpisode() {
        guard let currentRecord = selectedRecord else { return }
        guard let currentEpisode = recordListViewModel.episodes.first(where: { $0.title == currentRecord.title }) else { return }

        let nextEpisode = recordListViewModel.episodes
            .filter { $0.uploadedAt > currentEpisode.uploadedAt }
            .min(by: { $0.uploadedAt < $1.uploadedAt })

        let episodeToPlay = nextEpisode ?? recordListViewModel.episodes.min(by: { $0.uploadedAt < $1.uploadedAt })

        if let episode = episodeToPlay {
            playEpisode(episode)
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

#Preview {
    MainView().environmentObject(RecordListViewModel())
}
