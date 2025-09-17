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
    @EnvironmentObject var playQueue: PlayQueueManager
    
    @StateObject private var audioPlayer = AudioPlayerManager()
    @State private var showingFilePicker = false
    @State private var selectedRecord: RecordListModel?
    
    @AppStorage("isDarkMode") private var isDarkMode = false
    @AppStorage("shouldFetchNewEpisodes") private var shouldFetchNewEpisodes = false
    @AppStorage("didBackfillUploadedAt") private var didBackfillUploadedAt = false
    
    @State private var showingPlayerView = false
    @State private var isLoading = false
    @State private var isRefreshing = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    GradientBackground()
                        .frame(height: UIScreen.main.bounds.height * 0.57)
                        .frame(maxWidth: .infinity)
                        .ignoresSafeArea(.keyboard, edges: .top)
                    Spacer()
                }
            }
            .ignoresSafeArea(.all)
            .allowsHitTesting(false)
            ScrollView {
                VStack(spacing: 0) {
                    
                    podcastMainSection
                    descriptionSection
                    
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .zIndex(1)
            
            if let record = selectedRecord {
                MiniPlayerView(
                    record: record,
                    audioPlayer: audioPlayer,
                    onDelete: { deleteRecord(record) },
                    onNextEpisode: { playNextEpisode() }
                )
                .background(Color.clear)
                .allowsHitTesting(true)
                .zIndex(2)
                .onTapGesture { showingPlayerView = true }
                .fullScreenCover(isPresented: $showingPlayerView) {
                    if let selected = selectedRecord {
                        PlayerView(
                            record: selected,
                            audioPlayer: audioPlayer,
                            onDismiss: { showingPlayerView = false }
                        )
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { handleFileImport($0) }
            .onAppear {
                print("👀 [\(TS())] MainView.onAppear")
                // 1) 로컬 먼저
                recordListViewModel.loadLocalEpisodes(context: modelContext)
                
                // 2) (필요 시) 1회 백필
                backfillUploadedAtOnceIfNeeded()
                
                // 3) 푸시 플래그 감지 시 자동 동기화
                if shouldFetchNewEpisodes {
                    print("📥 [\(TS())] 푸시 감지됨 → 자동 동기화")
                    Task { await refreshNow(trigger: "onAppear-flag") }
                }
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
    
    // MARK: - 1회 백필
    /// 기존에 저장된 RecordListModel 중 uploadedAt이 비어있는 항목을 채워줍니다.
    /// - 우선순위: 파일명 매칭 → 제목 매칭 → 기존 addedDate
    private func backfillUploadedAtOnceIfNeeded() {
        guard !didBackfillUploadedAt else {
            print("↪️ [\(TS())] 백필 스킵: 이미 완료됨")
            return
        }
        print("🛠️ [\(TS())] 백필 시작")
        
        do {
            // 1) 모든 에피소드와 레코드 로드
            let episodes = try modelContext.fetch(FetchDescriptor<EpisodeModel>())
            var episodeByFileName: [String: EpisodeModel] = [:]
            var episodeByTitle: [String: EpisodeModel] = [:]
            for ep in episodes {
                episodeByFileName[ep.fileName] = ep
                episodeByTitle[ep.title] = ep
            }
            
            let records = try modelContext.fetch(FetchDescriptor<RecordListModel>())
            var patched = 0
            
            for rec in records {
                // 이미 채워져 있으면 스킵 (모델에 uploadedAt이 Optional이라고 가정)
                if rec.uploadedAt != nil { continue }
                
                // 파일명 매칭
                var matchedDate: Date? = nil
                if let url = rec.fileURL {
                    let name = url.lastPathComponent
                    if let ep = episodeByFileName[name] {
                        matchedDate = ep.uploadedAt
                    }
                }
                
                // 제목 매칭(보조)
                if matchedDate == nil, let ep = episodeByTitle[rec.title] {
                    matchedDate = ep.uploadedAt
                }
                
                // 최종 fallback: 기존 추가일
                rec.uploadedAt = matchedDate ?? rec.addedDate
                patched += 1
            }
            
            try modelContext.save()
            didBackfillUploadedAt = true
            print("✅ [\(TS())] 백필 완료: \(patched)건 패치됨")
            
        } catch {
            print("❌ [\(TS())] 백필 실패: \(error.localizedDescription)")
            // 실패해도 앱 동작에는 영향 없도록 플래그는 그대로 둠
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
    
    private var descriptionSection: some View {
        Text("친구랑 수다 떠는 듯 편안하게, 때론 진지하게.\n에이캐스트가 매주 수요일, 새로운 에피소드로 찾아옵니다.")
            .font(Font.SFPro.Regular.s14)
            .foregroundColor(Color("mainText"))
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 2)
            .padding(.bottom, 29)
    }
    
    private var loadingSection: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("에피소드 불러오는 중...")
                .font(Font.SFPro.Regular.s14)
                .foregroundColor(Color("subText"))
            Spacer()
        }
        .background(.white)
        .frame(maxWidth: .infinity)
        .frame(minHeight: .infinity)
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
        .background(.white)
        .frame(maxWidth: .infinity)
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
        // ① 큐 재구성 (MainView에서만 reset)
        playQueue.rebuildFromEpisodes(
            recordListViewModel.episodes,
            startAt: episode,
            urlFor: { fileName in recordListViewModel.getLocalFileURL(for: fileName) },
            artistFor: { ep in ep.desc } // 혹은 날짜 표기를 원하면 formatted(date: ep.uploadedAt)
        )
        
        // ② 현재 트랙으로 플레이
        guard let toPlay = playQueue.current else { return }
        withAnimation(.spring()) {
            selectedRecord = toPlay
            audioPlayer.play(toPlay)
        }
        
        // ③ 리모콘(next/prev) → 큐 연동
        audioPlayer.onNextTrack = {
            guard playQueue.hasNext else { audioPlayer.stop(); return }
            playQueue.advance()
            if let next = playQueue.current { audioPlayer.play(next); selectedRecord = next }
        }
        audioPlayer.onPrevTrack = {
            guard playQueue.hasPrev else { return }
            playQueue.back()
            if let prev = playQueue.current { audioPlayer.play(prev); selectedRecord = prev }
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
                
                // ✅ 로컬로 가져온 파일은 uploadedAt이 없으므로 nil (formattedDate가 addedDate로 표시)
                let newRecord = RecordListModel(
                    title: url.deletingPathExtension().lastPathComponent,
                    artist: "Unknown Artist",
                    duration: duration,
                    fileURL: destinationURL,
                    uploadedAt: nil
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
    do {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: EpisodeModel.self, RecordListModel.self, configurations: config)
        
        return MainView()
            .modelContainer(container)
            .environmentObject(RecordListViewModel())
            .environmentObject(PlayQueueManager())
    } catch {
        return Text("Preview Error: \(error.localizedDescription)")
    }
}
