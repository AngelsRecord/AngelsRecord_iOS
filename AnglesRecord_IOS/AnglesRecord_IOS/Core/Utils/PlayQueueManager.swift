//
//  PlayQueueManager.swift
//  A'Cast
//
//  Created by 성현 on 8/25/25.
//

import Foundation
import AVFoundation
import SwiftUI

@MainActor
final class PlayQueueManager: ObservableObject {
    @Published private(set) var items: [RecordListModel] = []
    @Published private(set) var currentIndex: Int?

    private let snapshotKey = "playqueue.snapshot.v1"

    init() { loadSnapshot() }

    // 현재/다음/이전
    var current: RecordListModel? {
        guard let i = currentIndex, items.indices.contains(i) else { return nil }
        return items[i]
    }
    var hasNext: Bool { (currentIndex ?? -1) + 1 < items.count }
    var hasPrev: Bool { (currentIndex ?? 0) - 1 >= 0 }

    // 메인뷰에서만 호출: 전체 에피소드로 큐 재구성(초기화)
    func rebuildFromEpisodes(
        _ episodes: [EpisodeModel],
        startAt selected: EpisodeModel,
        urlFor: (String) -> URL,
        artistFor: (EpisodeModel) -> String
    ) {
        // 올라갈수록 최신이 아래로 오게 "업로드 오름차순"
        let sorted = episodes.sorted { $0.uploadedAt < $1.uploadedAt }
        self.items = sorted.map { e in
            let url = urlFor(e.fileName)
            let duration = CMTimeGetSeconds(AVURLAsset(url: url).duration)
            return RecordListModel(
                title: e.title,
                artist: artistFor(e),
                duration: duration,
                fileURL: url,
                uploadedAt: e.uploadedAt
            )
        }
        self.currentIndex = sorted.firstIndex(where: { $0.id == selected.id })
        saveSnapshot()
    }

    // 수동 설정(필요 시)
    func setFromRecords(_ records: [RecordListModel], startAt index: Int) {
        items = records
        currentIndex = min(max(0, index), records.count - 1)
        saveSnapshot()
    }

    // 이동
    func advance() {
        guard let i = currentIndex, i + 1 < items.count else { return }
        currentIndex = i + 1
        saveSnapshot()
    }

    func back() {
        guard let i = currentIndex, i - 1 >= 0 else { return }
        currentIndex = i - 1
        saveSnapshot()
    }

    // 재정렬
    func move(fromOffsets: IndexSet, toOffset: Int) {
        items.move(fromOffsets: fromOffsets, toOffset: toOffset)
        // 현재 인덱스 보정
        if let i = currentIndex {
            currentIndex = remapIndex(afterMoving: i, fromOffsets: fromOffsets, toOffset: toOffset)
        }
        saveSnapshot()
    }

    private func remapIndex(afterMoving current: Int, fromOffsets: IndexSet, toOffset: Int) -> Int {
        var idx = current
        // 끌어낸 쪽 기준 보정
        for from in fromOffsets.sorted() where from < idx { idx -= 1 }
        // 삽입 위치 기준 보정
        var to = toOffset
        for from in fromOffsets.sorted() where from < to { to -= 1 }
        for _ in fromOffsets.sorted() where to <= idx { idx += 1 }
        return idx
    }

    func reset() {
        items.removeAll()
        currentIndex = nil
        saveSnapshot()
    }

    // MARK: - 영속화(UserDefaults 스냅샷)
    private struct SnapshotItem: Codable {
        let title: String
        let artist: String
        let duration: Double
        let fileName: String?    // documents 파일명
        let fileURL: String?     // 절대경로(백업용)
        let uploadedAt: Date?
    }
    private struct Snapshot: Codable {
        let items: [SnapshotItem]
        let currentIndex: Int?
    }

    private func saveSnapshot() {
        let dto = items.map { r in
            SnapshotItem(
                title: r.title,
                artist: r.artist,
                duration: r.duration,
                fileName: r.fileURL?.lastPathComponent,
                fileURL: r.fileURL?.absoluteString,
                uploadedAt: r.uploadedAt
            )
        }
        let snap = Snapshot(items: dto, currentIndex: currentIndex)
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: snapshotKey)
        }
    }

    private func loadSnapshot() {
        guard
            let data = UserDefaults.standard.data(forKey: snapshotKey),
            let snap = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.items = snap.items.map { s in
            let url: URL? = s.fileName != nil
                ? docs.appendingPathComponent(s.fileName!)
                : (s.fileURL.flatMap(URL.init(string:)))
            return RecordListModel(
                title: s.title,
                artist: s.artist,
                duration: s.duration,
                fileURL: url,
                uploadedAt: s.uploadedAt
            )
        }
        self.currentIndex = snap.currentIndex
    }
}
