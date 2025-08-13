//
//  RecordListViewModel.swift
//  AnglesRecord_IOS
//
//  Created by 성현 on 6/22/25.
//

import Foundation
import FirebaseFirestore
import FirebaseStorage
import SwiftUI
import SwiftData

private func TS() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f.string(from: Date())
}

class RecordListViewModel: ObservableObject {
    @Published var episodes: [EpisodeModel] = []
    @Published var isLoadingEpisodes: Bool = false

    /// 로컬(SwiftData) 로드
    func loadLocalEpisodes(context: ModelContext) {
        print("🗂️ [\(TS())] loadLocalEpisodes() 시작")
        let descriptor = FetchDescriptor<EpisodeModel>(
            sortBy: [SortDescriptor(\.uploadedAt, order: .reverse)]
        )
        if let result = try? context.fetch(descriptor) {
            DispatchQueue.main.async {
                self.episodes = result
                print("🗂️ [\(TS())] 로컬 로드 완료: \(result.count)개")
            }
        } else {
            print("⚠️ [\(TS())] 로컬 로드 실패")
        }
    }

    /// Firestore에서 받아와 SwiftData에 반영 (+ 완료핸들러)
    func fetchAndSyncEpisodes(context: ModelContext, completion: @escaping (Bool) -> Void) {
        print("🔥 [\(TS())] fetchAndSyncEpisodes() 호출")
        isLoadingEpisodes = true

        let db = Firestore.firestore()
        db.collection("episodes").getDocuments { snapshot, error in
            if let error = error {
                print("❌ [\(TS())] Firestore fetch 실패: \(error.localizedDescription)")
                self.isLoadingEpisodes = false
                completion(false)
                return
            }

            guard let documents = snapshot?.documents else {
                print("⚠️ [\(TS())] Firestore: 문서 없음")
                self.isLoadingEpisodes = false
                completion(false)
                return
            }

            print("🔥 [\(TS())] Firestore에서 \(documents.count)개 문서 수신")

            let group = DispatchGroup()
            var changedCount = 0

            DispatchQueue.main.async {
                for document in documents {
                    do {
                        // Episode는 Codable 모델이어야 함
                        let episode = try document.data(as: Episode.self)
                        print("✅ [\(TS())] 파싱 OK: \(episode.id) / \(episode.title)")

                        // 기존 존재 여부 확인
                        let existing = try? context.fetch(
                            FetchDescriptor<EpisodeModel>(
                                predicate: #Predicate { $0.id == episode.id }
                            )
                        ).first

                        if let existing = existing {
                            if existing.uploadedAt >= episode.uploadedAt {
                                print("↪️ [\(TS())] 변경 없음(스킵): \(episode.id)")
                            } else {
                                context.delete(existing)
                                print("🔁 [\(TS())] 업데이트 필요 → 기존 삭제: \(episode.id)")
                                let newModel = EpisodeModel(
                                    id: episode.id,
                                    title: episode.title,
                                    desc: episode.description,
                                    uploadedAt: episode.uploadedAt,
                                    fileName: episode.fileName
                                )
                                context.insert(newModel)
                                changedCount += 1
                                // 파일 필요 시 다운로드
                                group.enter()
                                self.downloadIfNeeded(fileName: episode.fileName, newerThan: episode.uploadedAt) { _ in
                                    group.leave()
                                }
                            }
                        } else {
                            // 신규 삽입
                            let newModel = EpisodeModel(
                                id: episode.id,
                                title: episode.title,
                                desc: episode.description,
                                uploadedAt: episode.uploadedAt,
                                fileName: episode.fileName
                            )
                            context.insert(newModel)
                            changedCount += 1
                            print("🆕 [\(TS())] 신규 저장: \(episode.id)")

                            group.enter()
                            self.downloadIfNeeded(fileName: episode.fileName, newerThan: episode.uploadedAt) { _ in
                                group.leave()
                            }
                        }

                    } catch {
                        print("❌ [\(TS())] 파싱 실패(\(document.documentID)): \(error.localizedDescription)")
                    }
                }

                group.notify(queue: .main) {
                    do {
                        try context.save()
                        print("📦 [\(TS())] SwiftData 저장 성공 (변경 \(changedCount)건)")
                        // 최신 로컬 로드
                        self.loadLocalEpisodes(context: context)
                        // 마지막 새로고침 시각 기록 (AppDelegate 비교용)
                        UserDefaults.standard.set(Date(), forKey: "lastEpisodesRefreshAt")
                        self.isLoadingEpisodes = false
                        completion(true)
                    } catch {
                        print("❌ [\(TS())] SwiftData 저장 실패: \(error.localizedDescription)")
                        self.isLoadingEpisodes = false
                        completion(false)
                    }
                }
            }
        }
    }

    // MARK: - 파일 다운로드 보조

    func getLocalFileURL(for fileName: String) -> URL {
        let doc = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return doc.appendingPathComponent(fileName)
    }

    private func shouldDownload(localURL: URL, uploadedAt: Date) -> Bool {
        if !FileManager.default.fileExists(atPath: localURL.path) {
            return true
        }
        if let attr = try? FileManager.default.attributesOfItem(atPath: localURL.path),
           let modified = attr[.modificationDate] as? Date {
            return modified < uploadedAt
        }
        return true
    }

    private func downloadIfNeeded(fileName: String, newerThan: Date, completion: @escaping (Bool) -> Void) {
        let localURL = getLocalFileURL(for: fileName)
        if !shouldDownload(localURL: localURL, uploadedAt: newerThan) {
            print("📦 [\(TS())] 로컬 최신 파일 유지: \(fileName)")
            completion(true)
            return
        }

        let ref = Storage.storage().reference().child("audios/\(fileName)")
        print("⬇️ [\(TS())] 다운로드 시작: \(fileName)")
        ref.write(toFile: localURL) { url, error in
            if let error = error {
                print("❌ [\(TS())] 다운로드 실패: \(error.localizedDescription)")
                completion(false)
            } else {
                print("✅ [\(TS())] 다운로드 완료: \(url?.lastPathComponent ?? fileName)")
                completion(true)
            }
        }
    }
}
