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
    
    
    @State private var pendingTapToken: UUID? = nil
    // 미니플레이어에서 다운로드 상태 감지용(파일명)
    @State private var miniPlayerEpisodeFileName: String? = nil
    
    
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
                    onNextEpisode: { playNextEpisode() },
                    episodeFileName: miniPlayerEpisodeFileName
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
                            onDismiss: { showingPlayerView = false },
                            episodeFileName: miniPlayerEpisodeFileName
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
            recordListViewModel.syncEpisodesMetadataOnly(context: modelContext) { ok in
                print("🧩 [\(TS())] syncEpisodesMetadataOnly 완료 ok=\(ok)")
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
            
            
            HStack(alignment: .center, spacing: 2) {
                Text(episode.title)
                    .font(Font.SFPro.SemiBold.s16)
                    .foregroundColor(Color("mainText"))
                    .lineLimit(2)
                    .padding(.trailing, 6)
                
                if recordListViewModel.isDownloading(fileName: episode.fileName)
                    || recordListViewModel.isDownloaded(episode) {
                    DownloadLoadingIndicator(episode: episode)
                }
            }
            .frame(width: 345, alignment: .leading)
            
            Text(episode.desc)
                .font(Font.SFPro.Regular.s14)
                .foregroundColor(Color("subText"))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { ensureLocalThenPlay(episode) }
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
        ensureLocalThenPlay(latestEpisode)
    }
    
    // Download-if-needed → (다운로드된 것만 정렬 큐) → 재생
    private func ensureLocalThenPlay(_ episode: EpisodeModel) {
        // 1) 마지막 탭 토큰 (연달아 탭해도 마지막 것만 유효)
        let token = UUID()
        pendingTapToken = token

        // 2) 미니플레이어를 즉시 로딩 상태로 띄우기
        selectedRecord = makeTempRecord(from: episode)
        miniPlayerEpisodeFileName = episode.fileName

        // 3) 이미 로컬에 있으면 바로 큐 재구성 후 재생
        if recordListViewModel.isDownloaded(episode) {
            rebuildQueueFromDownloaded(startEpisode: episode)
            playEpisode(episode)          // ⚠️ 이 함수는 큐를 다시 만들지 않도록 수정된 버전이어야 함
            return
        }

        // 4) 없으면 다운로드 → 완료 시 마지막 탭인지 확인 → 큐 재구성 → 재생
        recordListViewModel.downloadIfNeeded(
            fileName: episode.fileName,
            uploadedAt: episode.uploadedAt
        ) { ok in
            DispatchQueue.main.async {
                // 이전 탭의 콜백이면 무시
                guard self.pendingTapToken == token else { return }

                if ok {
                    self.rebuildQueueFromDownloaded(startEpisode: episode)
                    self.playEpisode(episode)  // 큐를 덮어쓰지 않는 버전
                } else {
                    // 실패 처리 (필요 시 로딩 해제/알럿 등)
                    // self.selectedRecord = nil
                    print("❌ download failed: \(episode.fileName)")
                }
            }
        }
    }


    // 파일명/타이틀에서 "에피소드 번호"를 추출 (ep.14, EP 14, e14, 14 등 유연하게)
    private func episodeNumber(of ep: EpisodeModel) -> Int? {
        let candidates = [ep.fileName.lowercased(), ep.title.lowercased()]
        for s in candidates {
            // ep.14 / ep 14 / e14 / episode 14
            let patterns = [
                #"e(p(isode)?)?[\.\s]*([0-9]{1,4})"#,
                #"(?:^|[^\d])([0-9]{1,4})(?:[^\d]|$)"# // fallback: 고립된 숫자
            ]
            for p in patterns {
                if let m = try? NSRegularExpression(pattern: p)
                    .firstMatch(in: s, range: NSRange(location: 0, length: s.utf16.count)),
                   m.numberOfRanges >= 2 {
                    // 마지막 캡쳐그룹을 우선
                    for idx in stride(from: m.numberOfRanges - 1, through: 1, by: -1) {
                        let r = m.range(at: idx)
                        if r.location != NSNotFound,
                           let range = Range(r, in: s),
                           let n = Int(s[range]) { return n }
                    }
                }
            }
        }
        return nil
    }

    // "다운로드된 것들만" 모아 에피소드 넘버 오름차순 → RecordListModel 배열로 변환
    private func buildDownloadedRecordsSorted() -> [RecordListModel] {
        let downloaded = recordListViewModel.episodes.filter { recordListViewModel.isDownloaded($0) }

        // 정렬: 1) 에피소드 번호(오름차순) 2) 번호가 없으면 업로드 날짜(오름차순)
        let sorted = downloaded.sorted { a, b in
            let na = episodeNumber(of: a)
            let nb = episodeNumber(of: b)
            if let na, let nb { return na < nb }
            if na != nil { return true }
            if nb != nil { return false }
            return a.uploadedAt < b.uploadedAt
        }

        // 레코드로 변환
        return sorted.map { e in
            let url = recordListViewModel.getLocalFileURL(for: e.fileName)
            let duration = CMTimeGetSeconds(AVURLAsset(url: url).duration)
            return RecordListModel(
                title: e.title,
                artist: "엔젤스",
                duration: duration,
                fileURL: url,
                uploadedAt: e.uploadedAt
            )
        }
    }

    // 큐 재구성: 다운로드된 것들만, 넘버링대로. 시작 포지션은 startEpisode에 맞춤
    private func rebuildQueueFromDownloaded(startEpisode: EpisodeModel) {
        let records = buildDownloadedRecordsSorted()
        // startEpisode가 records 안 어디에 있는지(파일명 매칭) 찾기
        let targetFile = startEpisode.fileName
        let startIndex = records.firstIndex { $0.fileURL?.lastPathComponent == targetFile } ?? 0
        playQueue.setFromRecords(records, startAt: startIndex)  // UserDefaults 스냅샷까지 저장됨 :contentReference[oaicite:2]{index=2}
    }

    private func needsDownload(_ localURL: URL, uploadedAt: Date) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: localURL.path) else { return true }
        if let attr = try? fm.attributesOfItem(atPath: localURL.path),
           let modified = attr[.modificationDate] as? Date {
            return modified < uploadedAt
        }
        return true
    }

    private func playEpisode(_ episode: EpisodeModel) {
        // 큐는 이미 '다운로드된 것만'으로 구성되어 있다는 가정.
        // 해당 에피소드를 큐에서 찾아 startAt으로 맞추고 재생.
        if let idx = playQueue.items.firstIndex(where: {
            $0.fileURL?.lastPathComponent == episode.fileName
        }) {
            playQueue.setFromRecords(playQueue.items, startAt: idx)
        }
        playFromQueue()
    }
    
    // 큐의 current를 실제로 재생하고, 리모컨 next/prev도 큐와 연동
    private func playFromQueue() {

        guard let toPlay = playQueue.current else { return }
        withAnimation(.spring()) {
            selectedRecord = toPlay
            audioPlayer.play(toPlay)
        }

        audioPlayer.onNextTrack = {
            guard playQueue.hasNext else { audioPlayer.stop(); return }
            playQueue.advance()
            if let next = playQueue.current {
                audioPlayer.play(next)
                selectedRecord = next
            }
        }
        audioPlayer.onPrevTrack = {
            guard playQueue.hasPrev else { return }
            playQueue.back()
            if let prev = playQueue.current {
                audioPlayer.play(prev)
                selectedRecord = prev
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

        guard playQueue.hasNext else { return }
        playQueue.advance()
        playFromQueue()

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
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
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
        
        // 탭 즉시 미니플레이어를 띄우기 위한 임시(비영구) 레코드
        private func makeTempRecord(from ep: EpisodeModel) -> RecordListModel {
            // SwiftData에 자동 저장되지 않음(삽입 안 하면 메모리 객체)
            RecordListModel(
                title: ep.title,
                artist: "",          // 필요 시 채워도 OK
                duration: 0,
                fileURL: nil,
                uploadedAt: ep.uploadedAt
            )
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
