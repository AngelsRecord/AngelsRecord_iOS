//
//  PlayListPanelView.swift
//  A'Cast
//
//  Created by 성현 on 8/25/25.
//

import SwiftUI

// MARK: - Playlist Panel
struct PlaylistPanelView: View {
    @EnvironmentObject private var playQueue: PlayQueueManager
    @Binding var editMode: EditMode
    let currentId: UUID?
    let items: [RecordListModel]
    let onMove: (IndexSet, Int) -> Void
    let onTap: (RecordListModel) -> Void
    let autoAlignToken: Int

    @State private var didInitialScroll = false
    @State private var userHasScrolled = false
    @State private var tapTargetId: UUID?

    private let panelHeight: CGFloat = 380
    private let rowHeight: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("다음 재생")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 6)

            ScrollViewReader { proxy in
                List {
                    ForEach(items) { item in
                        Button {
                            onTap(item)
                            tapTargetId = item.id
                            userHasScrolled = false
                            // 탭 직후에도 보장 스크롤
                            scrollToNextTop(proxy, animated: true)
                        } label: {
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
                            // 현재 재생 하이라이트(선택)
                            .background(
                                (item.id == currentId ? Color.primary.opacity(0.06) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .id(item.id)
                    }
                    .onMove(perform: onMove)

                    // 말미 빈공간(다음 항목이 꼭대기에 붙도록)
                    if let baseIndex = baseIndexForSpacer() {
                        Color.clear
                            .frame(height: bottomSpacerHeight(fromBase: baseIndex))
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: panelHeight)
                .background(Color.clear)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
                        .frame(height: 28)
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, -20)
                // ⚠️ 강제 리빌드 ID로 레이아웃 타이밍 안정화(현재 곡/아이템 수 변동 시)
                .id("plist-\(items.count)-\(currentId?.uuidString ?? "nil")")

                // 1) 최초 진입: '다음 곡'을 맨 위로
                .onAppear {
                    guard !didInitialScroll else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        scrollToNextTop(proxy, animated: true)
                        didInitialScroll = true
                    }
                }

                // 2) 현재 곡 변경(자동/수동) → 사용자가 스크롤하지 않았다면 정렬
                .onChange(of: currentId) { _ in
                    guard !userHasScrolled else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        scrollToNextTop(proxy, animated: true)
                    }
                }

                // 3) 자동 정렬 토큰(수동 트리거) → 정렬
                .onChange(of: autoAlignToken) { _ in
                    userHasScrolled = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        scrollToNextTop(proxy, animated: true)
                    }
                }

                // 4) 전역 큐 인덱스 변경(가장 확실한 신호)
                .onReceive(playQueue.$currentIndex) { _ in
                    guard !userHasScrolled else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        scrollToNextTop(proxy, animated: true)
                    }
                }

                // 사용자가 스와이프하면 자동정렬 중지
                .gesture(DragGesture().onChanged { _ in userHasScrolled = true })
            }
        }
        .padding(.horizontal, 8)
        .background(Color.clear)
        .environment(\.editMode, $editMode)
    }

    // MARK: - Scroll helpers

    /// 현재 기준 '다음 항목'의 ID (없으면 마지막 or 첫 항목)
    private func nextIdFromCurrentIndex() -> UUID? {
        guard let idx = playQueue.currentIndex else { return items.first?.id }
        let next = idx + 1
        return (next < items.count) ? items[next].id : items.last?.id
    }

    private func nextItemId(from currentId: UUID?) -> UUID? {
        guard let currentId,
              let idx = items.firstIndex(where: { $0.id == currentId }) else {
            return items.first?.id
        }
        let nextIdx = idx + 1
        return (nextIdx < items.count) ? items[nextIdx].id : items.last?.id
    }

    /// 말미 빈공간 계산(현재/탭 기준)
    private func baseIndexForSpacer() -> Int? {
        if let tapId = tapTargetId,
           let idx = items.firstIndex(where: { $0.id == tapId }) {
            return idx
        }
        if let currentId,
           let idx = items.firstIndex(where: { $0.id == currentId }) {
            return idx
        }
        return nil
    }

    private func bottomSpacerHeight(fromBase baseIndex: Int) -> CGFloat {
        let remain = max(0, items.count - (baseIndex + 1))
        let remainHeight = CGFloat(remain) * rowHeight
        let extra = panelHeight - remainHeight
        return max(0, extra)
    }

    /// 🔑 한 곳에서만 스크롤 실행(항상 1틱 지연 후 호출)
    private func scrollToNextTop(_ proxy: ScrollViewProxy, animated: Bool) {
        // currentIndex 우선, 실패 시 currentId 기반
        let target = nextIdFromCurrentIndex() ?? nextItemId(from: currentId)
        guard let id = target else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .top) }
        } else {
            proxy.scrollTo(id, anchor: .top)
        }
    }
}
