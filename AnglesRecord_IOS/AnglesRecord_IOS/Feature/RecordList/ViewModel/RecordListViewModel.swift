import Foundation
import SwiftUI
import SwiftData
import FirebaseFirestore

private func TS() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f.string(from: Date())
}

extension RecordListViewModel {
    enum BulkStopMode { case immediatePurge, finishCurrent }
}

final class RecordListViewModel: NSObject, ObservableObject {

    // MARK: - Public State
    @Published var episodes: [EpisodeModel] = []
    @Published var isLoadingEpisodes: Bool = false
    
    @Published var activeDownloads: Set<String> = []
    @Published var downloadProgress: [String: Double] = [:]
    
    private let stalenessThreshold: TimeInterval = 86_400 // 24h
    private let enableSkipLogs = false
    
    @Published var isBulkDownloading: Bool = false
    @Published var bulkTotal: Int = 0
    @Published var bulkDone: Int = 0
    var bulkProgress: Double { bulkTotal == 0 ? 0 : Double(bulkDone) / Double(bulkTotal) }
    
    private var bulkStopRequested: Bool = false
    private var bulkStopMode: BulkStopMode = .finishCurrent
    private var bulkToken = UUID() // 새 토큰이 발급되면 이전 벌크 체인은 무시


    // MARK: - Config (B안: "/$()/" → "//")
    private func read(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
    }

    private lazy var endpoint: String = {
        read("AWS_ENDPOINT").replacingOccurrences(of: "/$()/", with: "//")
    }()

    private lazy var bucket: String = {
        read("AWS_BUCKET")
    }()

    private lazy var keyPrefix: String = {
        (Bundle.main.object(forInfoDictionaryKey: "AWS_KEY_PREFIX") as? String) ?? "audios"
    }()

    private lazy var accessKey: String = {
        read("AWS_ACCESS_KEY")
    }()

    private lazy var secretKey: String = {
        read("AWS_SECRET_KEY")
    }()

    // MARK: - Downloader (단일 경로)
    private lazy var downloader: NCPDownloader = {
        NCPDownloader(cfg: .init(
            endpoint: endpoint,
            bucket: bucket,
            keyPrefix: keyPrefix, // 예: "audios"
            accessKey: accessKey,
            secretKey: secretKey,
            normalizeExtensionLowercased: true
        ))
    }()

    // MARK: - LifeCycle
    override init() {
        super.init()
        print("🛠️ [\(TS())] RecordListViewModel init: endpoint=\(endpoint), bucket=\(bucket), prefix=\(keyPrefix)")
    }

    // MARK: - Local Episodes
    func loadLocalEpisodes(context: ModelContext) {
        print("🗂️ [\(TS())] loadLocalEpisodes()")
        let desc = FetchDescriptor<EpisodeModel>(sortBy: [SortDescriptor(\.uploadedAt, order: .reverse)])
        if let result = try? context.fetch(desc) {
            DispatchQueue.main.async {
                self.episodes = result
                print("✅ [\(TS())] 로컬 로드: \(result.count)개")
            }
        } else {
            print("⚠️ [\(TS())] 로컬 로드 실패")
        }
    }

    func fetchAndSyncEpisodes(context: ModelContext, completion: @escaping (Bool) -> Void) {
        print("🔥 [\(TS())] Firestore 동기화 시작")

        // 새 벌크 시작: 플래그 초기화 + 새 토큰
        self.bulkStopRequested = false
        self.bulkStopMode = .finishCurrent
        let token = UUID()
        self.bulkToken = token

        let db = Firestore.firestore()
        db.collection("episodes").getDocuments { snapshot, error in
            if let error = error {
                print("❌ [\(TS())] Firestore fetch 실패: \(error.localizedDescription)")
                DispatchQueue.main.async { self.isBulkDownloading = false }
                completion(false); return
            }
            guard let docs = snapshot?.documents else {
                print("⚠️ [\(TS())] 문서 없음")
                DispatchQueue.main.async { self.isBulkDownloading = false }
                completion(false); return
            }

            print("📥 [\(TS())] 수신: \(docs.count)개")

            DispatchQueue.main.async {
                self.isBulkDownloading = true

                var toDownload: [(fileName: String, uploadedAt: Date)] = []
                var changed = 0

                for d in docs {
                    do {
                        let ep = try d.data(as: Episode.self)
                        let existing = try? context
                            .fetch(FetchDescriptor<EpisodeModel>(predicate: #Predicate { $0.id == ep.id }))
                            .first

                        let mustUpdate = (existing == nil) || (existing!.uploadedAt < ep.uploadedAt)
                        if mustUpdate {
                            if let ex = existing { context.delete(ex) }
                            context.insert(EpisodeModel(
                                id: ep.id, title: ep.title, desc: ep.description,
                                uploadedAt: ep.uploadedAt, fileName: ep.fileName
                            ))
                            changed += 1
                        }

                        let dst = self.documentsURL(for: ep.fileName)
                        if self.shouldDownload(to: dst, uploadedAt: ep.uploadedAt) {
                            toDownload.append((ep.fileName, ep.uploadedAt))
                        }
                    } catch {
                        print("❌ [\(TS())] 파싱 실패(\(d.documentID)): \(error.localizedDescription)")
                    }
                }

                do { try context.save() } catch {
                    print("❌ [\(TS())] SwiftData 저장 실패(프리-다운로드): \(error.localizedDescription)")
                }

                // 정렬: 숫자 내림차순 → 업로드 최신
                func episodeNumber(from fileName: String) -> Int? {
                    let s = fileName.lowercased()
                    if let r = s.range(of: "ep") {
                        var i = r.upperBound
                        while i < s.endIndex, !s[i].isNumber { i = s.index(after: i) }
                        var d = ""; while i < s.endIndex, s[i].isNumber { d.append(s[i]); i = s.index(after: i) }
                        if let v = Int(d) { return v }
                    }
                    var cur = "", last: String?
                    for ch in s { if ch.isNumber { cur.append(ch) } else { if !cur.isEmpty { last = cur; cur = "" } } }
                    if !cur.isEmpty { last = cur }
                    return last.flatMap(Int.init)
                }
                toDownload.sort { lhs, rhs in
                    let ln = episodeNumber(from: lhs.fileName)
                    let rn = episodeNumber(from: rhs.fileName)
                    switch (ln, rn) {
                    case let (l?, r?):
                        if l != r { return l > r }
                        return lhs.uploadedAt > rhs.uploadedAt
                    case (nil, let _?):
                        return false
                    case (let _?, nil):
                        return true
                    case (nil, nil):
                        return lhs.uploadedAt > rhs.uploadedAt
                    }
                }

                self.bulkTotal = toDownload.count
                self.bulkDone  = 0

                guard !toDownload.isEmpty else {
                    self.loadLocalEpisodes(context: context)
                    self.isBulkDownloading = false
                    print("📦 [\(TS())] 저장/동기화 완료, 변경 \(changed)건, 다운로드 0건")
                    completion(true); return
                }

                // 체인 시작(토큰 전달)
                self.downloadSequentially(items: toDownload, token: token) { _ in
                    self.loadLocalEpisodes(context: context)
                    self.isBulkDownloading = false
                    print("📦 [\(TS())] 저장/동기화 완료, 변경 \(changed)건, 다운로드 \(toDownload.count)건(직렬)")
                    completion(true)
                }
            }
        }
    }

    func requestBulkStop(_ mode: BulkStopMode) {
        DispatchQueue.main.async {
            self.bulkStopRequested = true
            self.bulkStopMode = mode

            if mode == .immediatePurge {
                // 다음 체인부터 중단되도록 토큰 변경
                self.bulkToken = UUID()

                // 네트워크 작업 취소 + 상태 정리
                let targets = Array(self.activeDownloads)
                for f in targets {
                    // ⚠️ NCPDownloader에 취소 API가 있다면 구현/호출하세요.
                    self.downloader.cancel(fileName: f)          // ← 구현 필요
                    self.activeDownloads.remove(f)
                    self.downloadProgress[f] = nil
                }

                // 즉시 UI 종료
                self.isBulkDownloading = false
            }
        }
    }

    
    // MARK: - File Paths & Decisions
    private func documentsURL(for fileName: String) -> URL {
        let doc = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return doc.appendingPathComponent(fileName)
    }

    /// MainView가 쓰는 공개용 래퍼
    func getLocalFileURL(for fileName: String) -> URL {
        return documentsURL(for: fileName)
    }

    
    func isDownloading(fileName: String) -> Bool {
        activeDownloads.contains(fileName)
    }

    func progress(for fileName: String) -> Double {
        downloadProgress[fileName] ?? 0.0
    }

    func isDownloaded(_ episode: EpisodeModel) -> Bool {
        let url = getLocalFileURL(for: episode.fileName)
        return !shouldDownload(to: url, uploadedAt: episode.uploadedAt, log: false)
    }

    /// 벌크 중에 '아직 안 받은' 에피소드는 탭/수동다운로드 차단
    func isBlockedForInteraction(_ ep: EpisodeModel) -> Bool {
        isBulkDownloading
        && !isDownloaded(ep)
        && !isDownloading(fileName: ep.fileName)
    }

    var bulkSmoothProgress: Double {
        guard bulkTotal > 0 else { return 0 }
        // 직렬 다운로드니까 현재 진행 중인 파일의 progress 하나만 보면 됨
        let currentFrac = activeDownloads.compactMap { downloadProgress[$0] }.max() ?? 0
        return (Double(bulkDone) + currentFrac) / Double(bulkTotal)
    }

    // 직렬 벌크 다운로드의 '계단식' 진행률 (0~1)
    var bulkStepProgress: Double {
        guard bulkTotal > 0 else { return 0 }
        return Double(bulkDone) / Double(bulkTotal)
    }
    
    // 단일 다운로드 진입 가드(혹시 다른 경로로 호출돼도 안전)
    func downloadIfNeeded(fileName: String, uploadedAt: Date, completion: @escaping (Bool) -> Void) {
        // ✅ 벌크 도중 신규 수동 다운로드 방지 (이미 진행 중인 아이템은 예외)
        if isBulkDownloading && !activeDownloads.contains(fileName) {
            print("⛔️ [\(TS())] 벌크 중 수동 다운로드 차단: \(fileName)")
            DispatchQueue.main.async { completion(false) }
            return
        }

        let localURL = getLocalFileURL(for: fileName)
        if shouldDownload(to: localURL, uploadedAt: uploadedAt, log: true) {
            downloadOne(fileName: fileName, uploadedAt: uploadedAt, completion: completion)
        } else {
            completion(true)
        }
    }

    
    private func shouldDownload(to localURL: URL, uploadedAt: Date, log: Bool = false) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: localURL.path) else {
            if log { print("⚠️ [\(TS())] 로컬 없음 → 다운로드") }
            return true
        }

        guard let attr = try? fm.attributesOfItem(atPath: localURL.path),
              let modified = attr[.modificationDate] as? Date else {
            if log { print("⚠️ [\(TS())] 수정일 조회 실패 → 다운로드") }
            return true
        }

        let delta = uploadedAt.timeIntervalSince(modified)

        if delta >= stalenessThreshold {
            if log { print("⚠️ [\(TS())] 수정일 비교: local=\(modified) vs up=\(uploadedAt) (Δ=\(Int(delta))s) → 다운로드") }
            return true
        } else {
            if log && enableSkipLogs {
                print("ℹ️ [\(TS())] 수정일 비교: local=\(modified) vs up=\(uploadedAt) (Δ=\(Int(delta))s) → 스킵(24h 미만)")
            }
            return false
        }
    }


    // MARK: - Serial Download Queue
    private func downloadSequentially(
        items: [(fileName: String, uploadedAt: Date)],
        index: Int = 0,
        aggregatedOK: Bool = true,
        token: UUID,
        completion: @escaping (Bool) -> Void
    ) {
        // 토큰 바뀌면(=중단/재시작) 즉시 종료
        guard token == self.bulkToken else {
            completion(false); return
        }
        // finishCurrent 모드에서, "다음으로 넘어가기 전" 중단 체크
        if bulkStopRequested && bulkStopMode == .finishCurrent && index > 0 {
            completion(aggregatedOK); return
        }
        guard index < items.count else {
            completion(aggregatedOK); return
        }

        let item = items[index]

        // immediatePurge 모드: 다음 항목 시작 자체를 막음
        if bulkStopRequested && bulkStopMode == .immediatePurge {
            completion(aggregatedOK); return
        }

        downloadOne(fileName: item.fileName, uploadedAt: item.uploadedAt) { ok in
            // 파일 '성공'일 때만 한 칸 증가(계단식)
            if ok { DispatchQueue.main.async { self.bulkDone += 1 } }

            // completion이 들어왔을 때도 토큰 확인 (중간에 stop → 토큰 변경된 상황)
            guard token == self.bulkToken else {
                completion(false); return
            }

            // finishCurrent 모드: 현재 파일 끝났고 stop 요청되었으면 여기서 종료
            if self.bulkStopRequested && self.bulkStopMode == .finishCurrent {
                completion(aggregatedOK && ok); return
            }

            // 다음으로 진행
            self.downloadSequentially(
                items: items,
                index: index + 1,
                aggregatedOK: aggregatedOK && ok,
                token: token,
                completion: completion
            )
        }
    }

    
    // MARK: - Metadata only sync (no audio downloads)
    func syncEpisodesMetadataOnly(context: ModelContext, completion: @escaping (Bool) -> Void) {
        print("🛈 [\(TS())] Firestore 메타데이터 동기화 시작 (오디오 다운로드 없음)")

        let db = Firestore.firestore()
        db.collection("episodes").getDocuments { snapshot, error in
            if let error = error {
                print("❌ [\(TS())] Firestore fetch 실패: \(error.localizedDescription)")
                completion(false)
                return
            }
            guard let docs = snapshot?.documents else {
                print("⚠️ [\(TS())] 문서 없음")
                completion(false)
                return
            }

            DispatchQueue.main.async {
                var changed = 0

                for d in docs {
                    do {
                        let ep = try d.data(as: Episode.self)

                        let existing = try? context
                            .fetch(FetchDescriptor<EpisodeModel>(predicate: #Predicate { $0.id == ep.id }))
                            .first

                        let mustUpdate = (existing == nil) || (existing!.uploadedAt < ep.uploadedAt)
                        if mustUpdate {
                            if let ex = existing { context.delete(ex) }
                            let model = EpisodeModel(
                                id: ep.id,
                                title: ep.title,
                                desc: ep.description,
                                uploadedAt: ep.uploadedAt,
                                fileName: ep.fileName
                            )
                            context.insert(model)
                            changed += 1
                        }
                    } catch {
                        print("❌ [\(TS())] 파싱 실패(\(d.documentID)): \(error.localizedDescription)")
                    }
                }

                do {
                    try context.save()
                } catch {
                    print("❌ [\(TS())] SwiftData 저장 실패(메타동기화): \(error.localizedDescription)")
                }

                self.loadLocalEpisodes(context: context)
                print("✅ [\(TS())] 메타데이터 동기화 완료, 변경 \(changed)건")
                completion(true)
            }
        }
    }

    /// ep.15.mp3 → 15 를 우선 추출. 없으면 파일명 내 '마지막 숫자 그룹'을 사용.
    private func episodeNumber(from fileName: String) -> Int? {
        let lower = fileName.lowercased()

        // 1) "ep" 다음의 숫자 우선 탐색
        if let epRange = lower.range(of: "ep") {
            var i = epRange.upperBound
            // 구분자 건너뛰기 (., _, -, 공백 등)
            while i < lower.endIndex, !lower[i].isNumber { i = lower.index(after: i) }
            var digits = ""
            while i < lower.endIndex, lower[i].isNumber {
                digits.append(lower[i]); i = lower.index(after: i)
            }
            if let v = Int(digits) { return v }
        }

        // 2) 폴백: 파일명에서 '마지막' 숫자 그룹 사용
        var current = ""
        var last: String?
        for ch in lower {
            if ch.isNumber {
                current.append(ch)
            } else {
                if !current.isEmpty { last = current; current = "" }
            }
        }
        if !current.isEmpty { last = current }
        return last.flatMap { Int($0) }
    }


    // MARK: - Estimate total download size (bytes) for items needing download
    func estimateTotalDownloadBytes(context: ModelContext, completion: @escaping (Int64) -> Void) {
        print("🧮 [\(TS())] 다운로드 예상 용량 계산 시작 (S3 메타 기반)")

        let db = Firestore.firestore()
        db.collection("episodes").getDocuments { snapshot, error in
            if let error = error {
                print("❌ [\(TS())] Firestore fetch 실패(estimate): \(error.localizedDescription)")
                completion(-1)
                return
            }
            guard let docs = snapshot?.documents else {
                print("⚠️ [\(TS())] 문서 없음(estimate)")
                completion(0)
                return
            }

            // 1) 다운로드 필요한 파일만 추출
            var need: [String] = [] // fileName 목록
            for d in docs {
                if let ep = try? d.data(as: Episode.self) {
                    let dst = self.documentsURL(for: ep.fileName)
                    if self.shouldDownload(to: dst, uploadedAt: ep.uploadedAt) {
                        need.append(ep.fileName)
                    }
                }
            }
            if need.isEmpty {
                print("ℹ️ [\(TS())] 다운로드 필요 항목 없음")
                completion(0)
                return
            }

            // 2) S3에서 prefix 전체를 리스트로 가져와 파일명→사이즈 매핑
            self.downloader.listObjectSizes { listResult in
                switch listResult {
                case .failure(let err):
                    print("⚠️ [\(TS())] listObjects 실패: \(err.localizedDescription) → HEAD로 대체")
                    // 전체를 HEAD로
                    self.sumByHEAD(fileNames: need, completion: completion)

                case .success(let sizeMap):
                    // 3) 매핑으로 빠르게 합산, 누락분만 HEAD
                    var total: Int64 = 0
                    var missing: [String] = []

                    func normalized(_ name: String) -> String {
                        // downloader의 normalize와 동일하게 확장자 소문자화
                        let ns = name as NSString
                        let ext = ns.pathExtension
                        guard !ext.isEmpty else { return name }
                        return "\(ns.deletingPathExtension).\(ext.lowercased())"
                    }

                    for name in need {
                        let n = normalized(name)
                        if let v = sizeMap[n] ?? sizeMap[name] {
                            total &+= v
                        } else {
                            missing.append(name)
                        }
                    }

                    if missing.isEmpty {
                        print("✅ [\(TS())] 예상 총 용량(bytes): \(total) (LIST 기반)")
                        DispatchQueue.main.async { completion(total) }
                    } else {
                        print("ℹ️ [\(TS())] LIST에 없는 \(missing.count)건 → HEAD로 보완")
                        self.sumByHEAD(fileNames: missing) { headBytes in
                            if headBytes < 0 {
                                DispatchQueue.main.async { completion(total > 0 ? total : -1) }
                            } else {
                                DispatchQueue.main.async { completion(total &+ headBytes) }
                            }
                        }
                    }
                }
            }
        }
    }

    /// HEAD 요청으로 여러 파일의 사이즈 합산 (동시성 제한 4)
    private func sumByHEAD(fileNames: [String], completion: @escaping (Int64) -> Void) {
        if fileNames.isEmpty { completion(0); return }
        let group = DispatchGroup()
        let sem = DispatchSemaphore(value: 4)

        var total: Int64 = 0
        var allFailed = true

        for f in fileNames {
            group.enter()
            sem.wait()
            downloader.headSizeBytes(fileName: f) { result in
                switch result {
                case .success(let bytes):
                    total &+= bytes
                    allFailed = false
                case .failure(let e):
                    print("⚠️ [\(TS())] HEAD 실패: \(f) → \(e.localizedDescription)")
                }
                sem.signal()
                group.leave()
            }
        }

        group.notify(queue: .global()) {
            if allFailed {
                completion(-1)
            } else {
                completion(total)
            }
        }
    }



    /// 단일 파일 다운로드 (Caches → Documents 이동, 수정일 = uploadedAt)
    /// 진행률은 `downloadProgress[fileName]` (0.0~1.0), 상태는 `activeDownloads`로 브로드캐스트
    private func downloadOne(fileName: String, uploadedAt: Date, completion: @escaping (Bool) -> Void) {
        // 다운로드 시작: 상태 초기화
        DispatchQueue.main.async {
            self.activeDownloads.insert(fileName)
            self.downloadProgress[fileName] = 0.0
        }

        // NCPDownloader는 Caches에 저장하고, 완료되면 localURL 반환한다고 가정
        downloader.download(fileName: fileName, progress: { frac in
            // 진행률 반영 (0.0 ~ 1.0)
            DispatchQueue.main.async {
                self.downloadProgress[fileName] = frac
            }
            let p = Int(frac * 100)
            if p % 10 == 0 { print("📊 [\(TS())] 진행률 \(p)%: \(fileName)") }
        }) { result in
            switch result {
            case .failure(let err):
                DispatchQueue.main.async {
                    self.activeDownloads.remove(fileName)
                    self.downloadProgress[fileName] = 0.0
                }
                print("❌ [\(TS())] 다운로드 실패: \(fileName), \(err.localizedDescription)")
                DispatchQueue.main.async { completion(false) }

            case .success(let out):
                let finalURL = self.documentsURL(for: fileName)
                do {
                    // 기존 파일이 있으면 삭제
                    if FileManager.default.fileExists(atPath: finalURL.path) {
                        try FileManager.default.removeItem(at: finalURL)
                    }
                    // 상위 폴더 보장
                    try FileManager.default.createDirectory(at: finalURL.deletingLastPathComponent(),
                                                            withIntermediateDirectories: true,
                                                            attributes: nil)
                    // Caches → Documents 이동
                    try FileManager.default.moveItem(at: out.localURL, to: finalURL)

                    // 다음 비교를 위해 파일 수정일을 업로드 시각으로 맞춤
                    try FileManager.default.setAttributes(
                        [.modificationDate: uploadedAt],
                        ofItemAtPath: finalURL.path
                    )

                    DispatchQueue.main.async {
                        self.downloadProgress[fileName] = 1.0
                        self.activeDownloads.remove(fileName)
                    }
                    print("✅ [\(TS())] 저장 완료: \(fileName) → Documents")
                    DispatchQueue.main.async { completion(true) }

                } catch {
                    DispatchQueue.main.async {
                        self.activeDownloads.remove(fileName)
                        self.downloadProgress[fileName] = 0.0
                    }
                    print("❌ [\(TS())] 파일 이동/속성 설정 실패: \(fileName), \(error.localizedDescription)")
                    DispatchQueue.main.async { completion(false) }
                }
            }
        }
    }

}
