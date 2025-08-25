//
//  PlayListPanelView.swift
//  A'Cast
//
//  Created by 성현 on 8/25/25.
//

import SwiftUI

// MARK: - Playlist Panel (경량/안정판)
struct PlaylistPanelView: View {
    @EnvironmentObject private var playQueue: PlayQueueManager

    @Binding var editMode: EditMode
    let currentId: UUID?
    let items: [RecordListModel]
    let onMove: (IndexSet, Int) -> Void
    let onTap: (RecordListModel) -> Void
    let autoAlignToken: Int

    // States
    @State private var didInitialScroll = false
    @State private var userHasScrolled = false
    @State private var tapTargetId: UUID?

    // 스페이서 기준/마지막 처리
    @State private var overrideBaseIndex: Int? = nil
    @State private var showPhantomNext: Bool = false

    // Layout
    private let panelHeight: CGFloat = 380
    private let rowHeight: CGFloat = 64

    init(
        editMode: Binding<EditMode>,
        currentId: UUID?,
        items: [RecordListModel],
        onMove: @escaping (IndexSet, Int) -> Void,
        onTap: @escaping (RecordListModel) -> Void,
        autoAlignToken: Int
    ) {
        self._editMode = editMode
        self.currentId = currentId
        self.items = items
        self.onMove = onMove
        self.onTap = onTap
        self.autoAlignToken = autoAlignToken
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollViewReader { proxy in
                List {
                    // 아이템 섹션
                    ItemsSection(
                        items: items,
                        currentId: currentId,
                        rowHeight: rowHeight,
                        onMove: onMove,
                        onTapButton: { item in
                            // 탭 처리
                            onTap(item)
                            tapTargetId = item.id
                            userHasScrolled = false

                            // 스페이서 기준을 "탭한 항목"으로 고정
                            if let b = items.firstIndex(where: { $0.id == item.id }) {
                                overrideBaseIndex = b
                            }

                            // 다음 타깃 계산
                            if let target = targetNextId() {
                                showPhantomNext = false
                                stickTopAnimated(proxy: proxy, targetId: target)
                            } else {
                                // 마지막이면 마지막을 꼭대기 + 한 칸 빈칸
                                showPhantomNext = true
                                if let lastId = items.last?.id {
                                    stickTopAnimated(proxy: proxy, targetId: lastId)
                                }
                            }
                        }
                    )

                    // 말미 스페이서 섹션
                    BottomSpacerSection(
                        height: spacerHeight(baseIndex: effectiveBaseIndex()),
                        rowHeight: rowHeight
                    )
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, 0/*, for: .listRow*/)   // 좌우 기본 마진 제거
                .frame(height: panelHeight)
                .gesture(DragGesture().onChanged { _ in userHasScrolled = true })

                // 초기 정렬
                .onAppear { initialAlign(proxy: proxy) }

                // 현재곡 바뀜 → 사용자 스크롤 중이 아니면 정렬
                .onChange(of: currentId) { _ in alignIfAllowed(proxy: proxy) }

                // 전역 큐 인덱스 변경 → 사용자 스크롤 중이 아니면 정렬
                .onReceive(playQueue.$currentIndex) { _ in alignIfAllowed(proxy: proxy) }

                // 외부 강제 정렬 토큰
                .onChange(of: autoAlignToken) { _ in
                    userHasScrolled = false
                    alignIfAllowed(proxy: proxy)
                }

                // 탭 기준 '다음'으로
                .onChange(of: tapTargetId) { base in
                    guard let base else { return }
                    scrollNext(fromBaseId: base, proxy: proxy)
                }
            }
        }
        .environment(\.editMode, $editMode)
    }

    // MARK: - Header (분리)
    private var header: some View {
        HStack {
            Text("다음 재생")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Scroll helpers (경량)

    /// 살짝 아래로 스윽: (무애니메이션) 이전행 top → (애니메이션) 타깃 top
    private func stickTopAnimated(proxy: ScrollViewProxy, targetId: UUID) {
        if let tIdx = items.firstIndex(where: { $0.id == targetId }), tIdx > 0 {
            let prevId = items[tIdx - 1].id
            proxy.scrollTo(prevId, anchor: .top)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(targetId, anchor: .top)
                }
            }
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(targetId, anchor: .top)
            }
        }
    }

    private func initialAlign(proxy: ScrollViewProxy) {
        guard !didInitialScroll else { return }
        // currentId를 스페이서 기준으로
        if let c = currentId, let base = items.firstIndex(where: { $0.id == c }) {
            overrideBaseIndex = base
        } else {
            overrideBaseIndex = nil
        }
        showPhantomNext = (targetNextId() == nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            if let target = targetNextId() {
                stickTopAnimated(proxy: proxy, targetId: target)
            } else if let lastId = items.last?.id {
                stickTopAnimated(proxy: proxy, targetId: lastId)
            }
            didInitialScroll = true
        }
    }

    private func alignIfAllowed(proxy: ScrollViewProxy) {
        guard !userHasScrolled else { return }
        if let c = currentId, let base = items.firstIndex(where: { $0.id == c }) {
            overrideBaseIndex = base
        } else {
            overrideBaseIndex = nil
        }
        showPhantomNext = (targetNextId() == nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            if let target = targetNextId() {
                stickTopAnimated(proxy: proxy, targetId: target)
            } else if let lastId = items.last?.id {
                stickTopAnimated(proxy: proxy, targetId: lastId)
            }
        }
    }

    private func scrollNext(fromBaseId baseId: UUID, proxy: ScrollViewProxy) {
        guard let baseIdx = items.firstIndex(where: { $0.id == baseId }) else { return }
        overrideBaseIndex = baseIdx
        let nextId = (baseIdx + 1 < items.count) ? items[baseIdx + 1].id : nil
        showPhantomNext = (nextId == nil)

        if let target = nextId {
            stickTopAnimated(proxy: proxy, targetId: target)
        } else if let lastId = items.last?.id {
            stickTopAnimated(proxy: proxy, targetId: lastId)
        }
    }

    /// 전역 큐 인덱스 우선 → 실패 시 currentId 기준. '다음 없음'이면 nil
    private func targetNextId() -> UUID? {
        if let idx = playQueue.currentIndex {
            let n = idx + 1
            guard n < items.count else { return nil }
            return items[n].id
        }
        return nextId(from: currentId)
    }

    /// currentId 기준 '다음'. '다음 없음'이면 nil
    private func nextId(from currentId: UUID?) -> UUID? {
        guard
            let currentId,
            let idx = items.firstIndex(where: { $0.id == currentId })
        else { return nil }
        let n = idx + 1
        guard n < items.count else { return nil }
        return items[n].id
    }

    // MARK: - Spacer math

    private func effectiveBaseIndex() -> Int? {
        if let o = overrideBaseIndex { return o }
        if let tap = tapTargetId, let idx = items.firstIndex(where: { $0.id == tap }) { return idx }
        if let c = currentId, let idx = items.firstIndex(where: { $0.id == c }) { return idx }
        return nil
    }

    private func spacerHeight(baseIndex: Int?) -> CGFloat {
        guard let baseIndex else { return 0 }
        // base 다음부터 남은 개수
        let remain = max(0, items.count - (baseIndex + 1))
        let remainHeight = CGFloat(remain) * rowHeight

        var extra = panelHeight - remainHeight
        if showPhantomNext {
            // 마지막이면 "빈 한 칸"만 (rowHeight) 보이도록 제한
            extra = min(max(0, extra), rowHeight)
        }
        return max(0, extra)
    }
}

// MARK: - Items Section (분리: 타입체커 부담 ↓)
private struct ItemsSection: View {
    let items: [RecordListModel]
    let currentId: UUID?
    let rowHeight: CGFloat
    let onMove: (IndexSet, Int) -> Void
    let onTapButton: (RecordListModel) -> Void

    var body: some View {
        ForEach(items, id: \.id) { item in
            let isCurrent = (item.id == currentId)
            Button { onTapButton(item) } label: {
                PlaylistRow(item: item, isCurrent: isCurrent)
                    .frame(height: rowHeight)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .id(item.id)
        }
        .onMove(perform: onMove)
    }
}

// MARK: - Bottom Spacer Section (분리)
private struct BottomSpacerSection: View {
    let height: CGFloat
    let rowHeight: CGFloat

    var body: some View {
        if height > 0.0 {
            Color.clear
                .frame(height: height)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .id(UUID()) // 안정화를 위해 고유 id
        }
    }
}

// MARK: - Row (아주 단순하게)
private struct PlaylistRow: View {
    let item: RecordListModel
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image("mainimage_yet")
                .resizable()
                .frame(width: 44, height: 44)
                .cornerRadius(6)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(item.formattedDate)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(
            (isCurrent ? Color.primary.opacity(0.06) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        )
    }
}
