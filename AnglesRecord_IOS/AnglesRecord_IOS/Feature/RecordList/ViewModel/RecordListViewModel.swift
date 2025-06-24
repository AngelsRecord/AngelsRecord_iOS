//
//  RecordListViewModel.swift
//  AnglesRecord_IOS
//
//  Created by 성현 on 6/22/25.
//

import Foundation
import FirebaseFirestore
import FirebaseStorage
import AVFoundation
import SwiftUI

class RecordListViewModel: ObservableObject {
    @Published var episodes: [Episode] = []

    // Firestore에서 에피소드 목록을 불러오는 함수
    func fetchEpisodes() {
        let db = Firestore.firestore()
        db.collection("episodes").getDocuments { snapshot, error in
            if let error = error {
                print("❌ Firestore 읽기 실패: \(error)")
                return
            }

            guard let documents = snapshot?.documents else {
                print("⚠️ 문서 없음")
                return
            }

            print("✅ Firestore 문서 수: \(documents.count)")

            for document in documents {
                do {
                    let episode = try document.data(as: Episode.self)
                    DispatchQueue.main.async {
                        self.episodes.append(episode)
                    }

                    // ✅ 에피소드마다 오디오 자동 다운로드
                    self.downloadFileIfNeeded(fileName: episode.fileName) { result in
                        switch result {
                        case .success(let url):
                            print("✅ \(episode.fileName) 다운로드 완료: \(url.lastPathComponent)")
                        case .failure(let error):
                            print("❌ \(episode.fileName) 다운로드 실패: \(error.localizedDescription)")
                        }
                    }
                } catch {
                    print("❌ 파싱 오류: \(error)")
                }
            }
        }
    }

    // 파일이 로컬에 없다면 Firebase Storage에서 다운로드
    private func downloadFileIfNeeded(fileName: String, completion: @escaping (Result<URL, Error>) -> Void) {
        let localURL = getLocalFileURL(for: fileName)

        if FileManager.default.fileExists(atPath: localURL.path) {
            // 이미 다운로드됨
            completion(.success(localURL))
            return
        }

        let storage = Storage.storage()
        let ref = storage.reference().child("audios/\(fileName)")

        ref.write(toFile: localURL) { url, error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(localURL))
            }
        }
    }

    // 로컬 파일 경로 반환
        func getLocalFileURL(for fileName: String) -> URL{
        let documentDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentDir.appendingPathComponent(fileName)
    }
}
