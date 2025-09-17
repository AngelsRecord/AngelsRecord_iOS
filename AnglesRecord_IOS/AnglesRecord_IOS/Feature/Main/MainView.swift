import AVFoundation
import SwiftData
import SwiftUI

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
    @State private var showingReport = false
    
    var body: some View {
        ZStack {
            Color("Background")
                .frame(height: 1)
                .ignoresSafeArea(edges: .top)
        }
        
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Spacer() // 오른쪽 끝으로 밀기
                        HStack(spacing: 16) {
                            RefreshButton(isRefreshing: $isRefreshing) {
                                Task { await refreshNow(trigger: "manual") }
                            }
                            
                            Menu {
                                // 1. 에이캐스트 설정 → 앱 자체 설정 화면
                                Button("에이케스트 설정") {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                                
                                // 2. 알림 설정 → 앱 알림 화면 (실제로는 앱 설정 화면까지 이동 가능)
                                Button("알림 설정") {
                                    let url = URL(string: UIApplication.openNotificationSettingsURLString)!
                                    UIApplication.shared.open(url)
                                }
                                
                                Divider()
                                
                                // 3. 문제 리포트 → 커스텀 액션 (아이콘 포함)
                                Button {
                                    showingReport = true
                                } label: {
                                    Label("문제 리포트", systemImage: "exclamationmark.bubble")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle.fill")
                                    .resizable()
                                    .frame(width: 28, height: 28)
                                    .foregroundColor(Color("subText"))
                            }
                        }
                        .padding(.trailing, 20)
                    }
                    .padding(.top, 8)
                    
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
                        PlayerView(
                            record: selected,
                            audioPlayer: audioPlayer,
                            onDismiss: { showingPlayerView = false }
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showingReport) {
            ReportSheet(
                onClose: { showingReport = false }
            )
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
    
    /// 기존에 저장된 RecordListModel 중 uploadedAt이 비어있는 항목을 채움.
    /// - 우선순위: 파일명 매칭 → 제목 매칭 → 기존 addedDate
    private func backfillUploadedAtOnceIfNeeded() {
        guard !didBackfillUploadedAt else {
            print("↪️ [\(TS())] 백필 스킵: 이미 완료됨")
            return
        }
        print("🛠️ [\(TS())] 백필 시작")
        
        do {
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
                if rec.uploadedAt != nil { continue }
                
                var matchedDate: Date? = nil
                if let url = rec.fileURL {
                    let name = url.lastPathComponent
                    if let ep = episodeByFileName[name] {
                        matchedDate = ep.uploadedAt
                    }
                }
                
                if matchedDate == nil, let ep = episodeByTitle[rec.title] {
                    matchedDate = ep.uploadedAt
                }
                
                rec.uploadedAt = matchedDate ?? rec.addedDate
                patched += 1
            }
            
            try modelContext.save()
            didBackfillUploadedAt = true
            print("✅ [\(TS())] 백필 완료: \(patched)건 패치됨")
            
        } catch {
            print("❌ [\(TS())] 백필 실패: \(error.localizedDescription)")
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
        // ① 큐 재구성 (MainView에서만 reset)
        playQueue.rebuildFromEpisodes(
            recordListViewModel.episodes,
            startAt: episode,
            urlFor: { fileName in recordListViewModel.getLocalFileURL(for: fileName) },
            artistFor: { ep in ep.desc }
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
                
                let newRecord = RecordListModel(
                    title: url.deletingPathExtension().lastPathComponent,
                    artist: "Unknown Artist",
                    duration: duration,
                    fileURL: destinationURL,
                    uploadedAt: nil // 로컬 가져온 파일은 업로드일 없음
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

    // MARK: - UI Components
    
    private struct RefreshButton: View {
        @Binding var isRefreshing: Bool
        var action: () -> Void
        
        @State private var spin = false
        
        var body: some View {
            Button {
                guard !isRefreshing else { return }
                action()
            } label: {
                ZStack {
                    if isRefreshing {
                        // Background circle track
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 28, height: 28)
                        
                        // Rotating arc
                        Circle()
                            .trim(from: 0, to: 0.28)
                            .stroke(
                                Color("subText"),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 28, height: 28)
                            .rotationEffect(.degrees(spin ? 360 : 0))
                            .animation(
                                isRefreshing
                                    ? .linear(duration: 1.0).repeatForever(autoreverses: false)
                                    : .default,
                                value: spin
                            )
                            .onAppear { spin = true }
                            .onDisappear { spin = false }
                        
                        // Stop square inside
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .resizable()
                            .frame(width: 28, height: 28)
                            .foregroundColor(Color("subText"))
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRefreshing ? "다운로드 중" : "새로고침")
        }
    }
    
    // MARK: - Report Sheet
    
    private struct ReportSheet: View {
        @Environment(\.dismiss) private var dismiss
        @State private var title: String = ""
        @State private var detail: String = ""
        @State private var includeDiagnostics: Bool = true
        @State private var email: String = ""
        
        var onClose: () -> Void
        
        var body: some View {
            NavigationView {
                Form {
                    Section(header: Text("제목")) {
                        TextField("문제 제목 (필수)", text: $title)
                            .textInputAutocapitalization(.never)
                    }
                    
                    Section(header: Text("설명")) {
                        TextEditor(text: $detail)
                            .frame(minHeight: 120)
                            .overlay(
                                Group {
                                    if detail.isEmpty {
                                        Text("내용을 작성해주세요.")
                                            .foregroundColor(.secondary)
                                            .padding(.top, 8)
                                            .padding(.leading, 4)
                                        Spacer(minLength: 0)
                                    }
                                }, alignment: .topLeading
                            )
                    }

                    Section {
                        Toggle("진단 정보 포함 (기기/OS/앱 버전)", isOn: $includeDiagnostics)
                    } footer: {
                        Text("개인 데이터는 수집하지 않습니다.")
                    }
                    
                    ZStack(alignment: .leading) {
                        if email.isEmpty {
                            Text("your@email.com")
                                .tint(.gray)
                                .padding(.leading, 4)
                        }
                        TextField("", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    
                    Section {
                        Button {
                            sendEmail()
                        } label: {
                            Label("이메일로 보내기", systemImage: "envelope")
                        }
                        .disabled(
                            title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                }
                .navigationTitle("문제 리포트")
                .navigationBarTitleDisplayMode(.inline)
//                .onTapGesture { endTextEditing() }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") {
                            onClose()
                            dismiss()
                        }
                    }
                }
            }
        }
        
        private func sendEmail() {
            let to = "se020122@naver.com"
            let subject = "[Report] \(title)"
            var body = detail
            
            if includeDiagnostics {
                let diag = diagnosticsBlock()
                body += "\n\n---- 진단 정보 ----\n\(diag)"
            }
            if !email.trimmingCharacters(in: .whitespaces).isEmpty {
                body += "\n\n회신 이메일: \(email)"
            }
            
            let comps = mailtoURL(to: to, subject: subject, body: body)
            if let url = comps, UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
            onClose()
            dismiss()
        }
        
        private func diagnosticsBlock() -> String {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
            let os = UIDevice.current.systemVersion
            let model = UIDevice.current.model
            let ts = ISO8601DateFormatter().string(from: Date())
            return """
            App \(version) (\(build))
            iOS \(os), \(model)
            Time \(ts)
            """
        }
        
        private func mailtoURL(to: String, subject: String, body: String) -> URL? {
            var components = URLComponents()
            components.scheme = "mailto"
            components.path = to
            components.queryItems = [
                URLQueryItem(name: "subject", value: subject),
                URLQueryItem(name: "body", value: body)
            ]
            return components.url
        }
    }
}
