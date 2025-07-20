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

class RecordListViewModel: ObservableObject {
    @Published var episodes: [EpisodeModel] = []
    @Published var isLoadingEpisodes: Bool = false

    // MARK: - 로컬 에피소드 불러오기 (SwiftData)
    func loadLocalEpisodes(context: ModelContext) {
        let descriptor = FetchDescriptor<EpisodeModel>(
            sortBy: [SortDescriptor(\.uploadedAt, order: .reverse)]
        )
        if let result = try? context.fetch(descriptor) {
            DispatchQueue.main.async {
                self.episodes = result
            }
        }
    }

    // MARK: - Firestore에서 에피소드 받아오고 SwiftData에 저장
    func fetchAndSyncEpisodes(context: ModelContext) {
        print("🔥 Firestore fetch 시작")
        isLoadingEpisodes = true

        let db = Firestore.firestore()
        db.collection("episodes").getDocuments { snapshot, error in
            if let error = error {
                print("❌ Firestore fetch 실패: \(error.localizedDescription)")
                self.isLoadingEpisodes = false
                return
            }

            guard let documents = snapshot?.documents else {
                print("⚠️ 에피소드 문서 없음")
                self.isLoadingEpisodes = false
                return
            }

            print("🔥 Firestore에서 \(documents.count)개 에피소드 수신")

            let group = DispatchGroup()

            DispatchQueue.main.async {
                for document in documents {
                    do {
                        let episode = try document.data(as: Episode.self)
                        print("✅ 파싱 완료: \(episode.title)")

                        let existing = try? context.fetch(
                            FetchDescriptor<EpisodeModel>(
                                predicate: #Predicate { $0.id == episode.id }
                            )
                        ).first

                        if let existing = existing {
                            if existing.uploadedAt >= episode.uploadedAt {
                                print("⚠️ 변경 없음 → 저장 생략: \(episode.id)")
                                continue
                            }
                            context.delete(existing)
                            print("🔁 업데이트 필요 → 기존 삭제: \(episode.id)")
                        }

                        let newModel = EpisodeModel(
                            id: episode.id,
                            title: episode.title,
                            desc: episode.description,
                            uploadedAt: episode.uploadedAt,
                            fileName: episode.fileName
                        )
                        context.insert(newModel)
                        print("💾 새 에피소드 저장: \(episode.id)")

                        // 오디오 다운로드
                        let localURL = self.getLocalFileURL(for: episode.fileName)
                        if self.shouldDownload(localURL: localURL, uploadedAt: episode.uploadedAt) {
                            group.enter()
                            self.downloadFileIfNeeded(fileName: episode.fileName) { result in
                                switch result {
                                case .success(let url):
                                    print("🎧 다운로드 완료: \(url.lastPathComponent)")
                                case .failure(let error):
                                    print("❌ 다운로드 실패: \(error.localizedDescription)")
                                }
                                group.leave()
                            }
                        }

                    } catch {
                        print("❌ 파싱 실패: \(error.localizedDescription)")
                    }
                }

                group.notify(queue: .main) {
                    do {
                        try context.save()
                        print("📦 SwiftData 저장 성공")
                    } catch {
                        print("❌ SwiftData 저장 실패: \(error.localizedDescription)")
                    }

                    self.loadLocalEpisodes(context: context)
                    self.isLoadingEpisodes = false
                }
            }
        }
    }

    func getLocalFileURL(for fileName: String) -> URL {
        let documentDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentDir.appendingPathComponent(fileName)
    }

    private func shouldDownload(localURL: URL, uploadedAt: Date) -> Bool {
        if !FileManager.default.fileExists(atPath: localURL.path) {
            return true
        }

        if let attributes = try? FileManager.default.attributesOfItem(atPath: localURL.path),
           let modified = attributes[.modificationDate] as? Date {
            return modified < uploadedAt
        }

        return true
    }

    private func downloadFileIfNeeded(fileName: String, completion: @escaping (Result<URL, Error>) -> Void) {
        let localURL = getLocalFileURL(for: fileName)

        if FileManager.default.fileExists(atPath: localURL.path) {
            completion(.success(localURL))
            return
        }

        let ref = Storage.storage().reference().child("audios/\(fileName)")
        ref.write(toFile: localURL) { url, error in
            if let error = error {
                completion(.failure(error))
            } else if let url = url {
                completion(.success(url))
            }
        }
    }
}
