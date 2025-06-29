import SwiftUI
import FirebaseCoreInternal
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
                    // 로딩 스피너 (새로고침 시 맨 위에)
                    if isRefreshing {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.8)
                            Spacer()
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 10)
                    }
                    
                    // 팟캐스트 메인 섹션
                    podcastMainSection
                    
                    // 구분선
                    Rectangle()
                        .fill(Color("subText").opacity(0.2))
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                    
                    // 에피소드 목록 또는 로딩 상태
                    if isLoading {
                        loadingSection
                    } else {
                        episodeListContent
                    }
                }
                .padding(.bottom, selectedRecord != nil ? 100 : 20)
            }
            .refreshable {
                await refreshData()
            }
            
            // 미니플레이어 (재생 중일 때만 표시)
            if let record = selectedRecord {
                MiniPlayerView(
                    record: record,
                    audioPlayer: audioPlayer,
                    onDelete: {
                        deleteRecord(record)
                    }
                )
                .onTapGesture {
                    showingPlayerView = true
                }
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
        ) { result in
            handleFileImport(result)
        }
        .onAppear {
            loadInitialData()
        }
    }
    
    // MARK: - 팟캐스트 메인 섹션
    private var podcastMainSection: some View {
        VStack(spacing: 0) {
            // 팟캐스트 커버 이미지
            Image("mainimage_yet")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .cornerRadius(16)
                .padding(.top, 20)
            
            // 제목
            Text("전지적 씨팝 시점: 전팝시")
                .font(Font.SFPro.SemiBold.s16)
                .foregroundColor(Color("mainText"))
                .frame(maxWidth: .infinity, alignment: .center)
                .opacity(0.9)
                .padding(.top, 16)
            
            // 부제목
            Text("엔젤스")
                .font(Font.SFPro.Regular.s14)
                .multilineTextAlignment(.center)
                .foregroundColor(Color("subText"))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 6)
            
            // 최신 에피소드 재생 버튼
            Button(action: {
                playLatestEpisode()
            }) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(Font.custom("SF Pro", size: 17))
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color("mainText"))
                    // Button/Semi16
                    Text("최신 에피소드")
                        .font(Font.SFPro.SemiBold.s16)
                        .foregroundColor(Color("mainText"))
                }
                .padding(.horizontal, 74.5)
                .padding(.vertical, 14)
                .frame(alignment: .center)
                .background(Color("iconBack"))
                .cornerRadius(12)
            }
          
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
    }
    
    // MARK: - 로딩 섹션
    private var loadingSection: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
                .padding(.top, 40)
            
            Text("데이터를 불러오는 중...")
                .font(Font.SFPro.Regular.s14)
                .foregroundColor(Color("subText"))
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 300)
    }
    
    // MARK: - 에피소드 목록 컨텐츠
    private var episodeListContent: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(recordListViewModel.episodes.enumerated()), id: \.element.id) { index, episode in
                VStack(spacing: 0) {
                    episodeRow(for: episode)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    
                    // 에피소드 사이 구분선 (마지막 아이템 제외)
                    if index < recordListViewModel.episodes.count - 1 {
                        Rectangle()
                            .fill(Color("subText").opacity(0.1))
                            .frame(height: 1)
                            .padding(.horizontal, 20)
                    }
                }
            }
        }
    }
    
    // MARK: - 에피소드 행
    private func episodeRow(for episode: Episode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 날짜
            Text(formatted(date: episode.uploadedAt))
                .font(Font.SFPro.SemiBold.s12)
                .foregroundColor(Color("subText"))
                .frame(maxWidth: .infinity, alignment: .topLeading)
            
            // 제목
            Text(episode.title)
                .font(Font.SFPro.SemiBold.s16)
                .foregroundColor(Color("mainText"))
                .frame(width: 345, alignment: .topLeading)
                .opacity(0.9)
                .lineLimit(2)
            
            // 설명
            Text(episode.description)
                .font(Font.SFPro.Regular.s14)
                .foregroundColor(Color("subText"))
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            playEpisode(episode)
        }
    }

    // MARK: - 헬퍼 함수들
    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
    }
    
    private func loadInitialData() {
        isLoading = true
        
        recordListViewModel.fetchEpisodes()
        
        // 로딩 시뮬레이션 (실제로는 fetchEpisodes 완료 후 isLoading을 false로)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.5)) {
                isLoading = false
            }
        }
    }
    
    private func refreshData() async {
        isRefreshing = true
        
        // 새로고침 시뮬레이션
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5초
        
        await MainActor.run {
            recordListViewModel.fetchEpisodes()
            withAnimation(.easeInOut(duration: 0.3)) {
                isRefreshing = false
            }
        }
    }
    
    private func playLatestEpisode() {
        guard let latestEpisode = recordListViewModel.episodes.first else { return }
        playEpisode(latestEpisode)
    }
    

    private func playEpisode(_ episode: Episode) {
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

    // MARK: - 기존 함수들 (수정 없음)
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

#Preview {
    MainView()
}
