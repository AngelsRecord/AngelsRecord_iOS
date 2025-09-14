import Foundation
import SwiftUI
import SwiftData
import FirebaseFirestore

private func TS() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f.string(from: Date())
}

final class RecordListViewModel: NSObject, ObservableObject {

    // MARK: - Public State
    @Published var episodes: [EpisodeModel] = []
    @Published var isLoadingEpisodes: Bool = false

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

    // MARK: - Fetch + Sync (직렬 다운로드)
    func fetchAndSyncEpisodes(context: ModelContext, completion: @escaping (Bool) -> Void) {
        print("🔥 [\(TS())] Firestore 동기화 시작")
        isLoadingEpisodes = true

        let db = Firestore.firestore()
        db.collection("episodes").getDocuments { snapshot, error in
            if let error = error {
                print("❌ [\(TS())] Firestore fetch 실패: \(error.localizedDescription)")
                self.isLoadingEpisodes = false
                completion(false)
                return
            }
            guard let docs = snapshot?.documents else {
                print("⚠️ [\(TS())] 문서 없음")
                self.isLoadingEpisodes = false
                completion(false)
                return
            }

            print("📥 [\(TS())] 수신: \(docs.count)개")

            DispatchQueue.main.async {
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

                        // 직렬 다운로드 큐 구성
                        let dst = self.documentsURL(for: ep.fileName)
                        if self.shouldDownload(to: dst, uploadedAt: ep.uploadedAt) {
                            toDownload.append((ep.fileName, ep.uploadedAt))
                        }

                    } catch {
                        print("❌ [\(TS())] 파싱 실패(\(d.documentID)): \(error.localizedDescription)")
                    }
                }

                do {
                    try context.save()
                } catch {
                    print("❌ [\(TS())] SwiftData 저장 실패(프리-다운로드): \(error.localizedDescription)")
                }

                // 직렬 다운로드 시작
                self.downloadSequentially(items: toDownload) { _ in
                    self.loadLocalEpisodes(context: context)
                    self.isLoadingEpisodes = false
                    print("📦 [\(TS())] 저장/동기화 완료, 변경 \(changed)건, 다운로드 \(toDownload.count)건(직렬)")
                    completion(true)
                }
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

    private func shouldDownload(to localURL: URL, uploadedAt: Date) -> Bool {
        if !FileManager.default.fileExists(atPath: localURL.path) {
            print("⬇️ [\(TS())] 로컬 없음 → 다운로드 필요: \(localURL.lastPathComponent)")
            return true
        }
        if let attr = try? FileManager.default.attributesOfItem(atPath: localURL.path),
           let modified = attr[.modificationDate] as? Date {
            let need = modified < uploadedAt
            print("\(need ? "⚠️" : "✅") [\(TS())] 수정일 비교: local=\(modified) vs up=\(uploadedAt) → \(need ? "다운로드" : "유지")")
            return need
        }
        return true
    }

    // MARK: - Serial Download Queue
    private func downloadSequentially(
        items: [(fileName: String, uploadedAt: Date)],
        index: Int = 0,
        aggregatedOK: Bool = true,
        completion: @escaping (Bool) -> Void
    ) {
        guard index < items.count else {
            completion(aggregatedOK); return
        }
        let item = items[index]
        downloadOne(fileName: item.fileName, uploadedAt: item.uploadedAt) { ok in
            self.downloadSequentially(
                items: items,
                index: index + 1,
                aggregatedOK: aggregatedOK && ok,
                completion: completion
            )
        }
    }

    private func downloadOne(fileName: String, uploadedAt: Date, completion: @escaping (Bool) -> Void) {
        // NCPDownloader는 Caches에 저장 → 완료 후 Documents로 이동
        downloader.download(fileName: fileName, progress: { frac in
            let p = Int(frac * 100)
            if p % 10 == 0 { print("📊 [\(TS())] 진행률 \(p)%: \(fileName)") }
        }) { result in
            switch result {
            case .failure(let err):
                print("❌ [\(TS())] 다운로드 실패: \(fileName), \(err.localizedDescription)")
                completion(false)

            case .success(let out):
                let finalURL = self.documentsURL(for: fileName)
                do {
                    if FileManager.default.fileExists(atPath: finalURL.path) {
                        try FileManager.default.removeItem(at: finalURL)
                    }
                    try FileManager.default.moveItem(at: out.localURL, to: finalURL)
                    // 다음 비교를 위해 파일 수정일을 업로드일로 맞춤
                    try FileManager.default.setAttributes(
                        [.modificationDate: uploadedAt],
                        ofItemAtPath: finalURL.path
                    )
                    print("✅ [\(TS())] 저장 완료: \(fileName) → Documents")
                    completion(true)
                } catch {
                    print("❌ [\(TS())] 파일 이동 실패: \(fileName), \(error.localizedDescription)")
                    completion(false)
                }
            }
        }
    }
}
