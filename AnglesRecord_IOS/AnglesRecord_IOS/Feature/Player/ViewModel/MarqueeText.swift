//
//  MarqueeText.swift
//  AnglesRecord_IOS
//
//
//

import SwiftUI

public struct MarqueeText: View {
    public var text: String                    // 표시할 텍스트
    public var font: UIFont                    // 텍스트에 사용할 UIFont
    public var leftFade: CGFloat               // 왼쪽 페이드 아웃 영역 너비
    public var rightFade: CGFloat              // 오른쪽 페이드 아웃 영역 너비
    public var startDelay: Double              // 애니메이션 시작 지연 시간
    public var alignment: Alignment            // 텍스트 정렬 방식
    
    @State private var animate = false         // 애니메이션 활성화 여부
    var isCompact = false                      // 콘텐츠 너비에 딱 맞게 표시할지 여부

    public var body: some View {
        // 텍스트의 실제 너비와 높이를 계산
        let stringWidth = text.widthOfString(usingFont: font)
        let stringHeight = text.heightOfString(usingFont: font)

        // 텍스트의 너비에 따라 속도가 결정되는 선형 애니메이션
        // startDelay만큼 지연 후 시작되며, 무한 반복하고 되돌아오지 않음
        let animation = Animation
            .linear(duration: Double(stringWidth) / 30)
            .delay(startDelay)
            .repeatForever(autoreverses: false)

        // 애니메이션이 없는 경우 사용할 설정
        let nullAnimation = Animation.linear(duration: 0)

        GeometryReader { geo in
            let needsScrolling = (stringWidth > geo.size.width) // 텍스트가 넘치는지 판단

            ZStack {
                if needsScrolling {
                    // 스크롤이 필요한 경우 마퀴 텍스트 생성
                    makeMarqueeTexts(
                        stringWidth: stringWidth,
                        stringHeight: stringHeight,
                        geoWidth: geo.size.width,
                        animation: animation,
                        nullAnimation: nullAnimation
                    )
                    .frame(
                        minWidth: 0,
                        maxWidth: .infinity,
                        minHeight: 0,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                    .offset(x: leftFade)
                    // 페이드 효과 마스크 적용
                    .mask(
                        fadeMask(
                            leftFade: leftFade,
                            rightFade: rightFade
                        )
                    )
                    .frame(width: geo.size.width + leftFade)
                    .offset(x: -leftFade)
                } else {
                    // 텍스트가 넘치지 않으면 일반적으로 표시
                    Text(text)
                        .font(.init(font))
                        .onChange(of: text) { _ in
                            self.animate = false
                        }
                        .frame(
                            minWidth: 0,
                            maxWidth: .infinity,
                            minHeight: 0,
                            maxHeight: .infinity,
                            alignment: alignment
                        )
                }
            }
            .onAppear {
                self.animate = needsScrolling // 화면에 나타나면 애니메이션 시작 여부 결정
            }
            .onChange(of: text) { newValue in
                // 텍스트가 바뀌면 새로 계산하여 애니메이션 재시작 여부 판단
                let newStringWidth = newValue.widthOfString(usingFont: font)
                if newStringWidth > geo.size.width {
                    self.animate = false
                    DispatchQueue.main.async {
                        self.animate = true
                    }
                } else {
                    self.animate = false
                }
            }
        }
        // 텍스트의 높이를 기준으로 프레임 고정
        .frame(height: stringHeight)
        // compact 모드일 경우 텍스트 길이에 맞춰 프레임 지정
        .frame(maxWidth: isCompact ? stringWidth : nil)
        .onDisappear {
            self.animate = false // 뷰가 사라지면 애니메이션 중단
        }
    }

    // 두 개의 텍스트를 이어붙여 무한 스크롤처럼 보이게 만듦
    @ViewBuilder
    private func makeMarqueeTexts(
        stringWidth: CGFloat,
        stringHeight: CGFloat,
        geoWidth: CGFloat,
        animation: Animation,
        nullAnimation: Animation
    ) -> some View {
        Group {
            // 첫 번째 텍스트: 왼쪽으로 이동
            Text(text)
                .lineLimit(1)
                .font(.init(font))
                .offset(x: animate ? -stringWidth - stringHeight * 2 : 0)
                .animation(animate ? animation : nullAnimation, value: animate)
                .fixedSize(horizontal: true, vertical: false)

            // 두 번째 텍스트: 뒤에서 따라오며 반복 효과 생성
            Text(text)
                .lineLimit(1)
                .font(.init(font))
                .offset(x: animate ? 0 : stringWidth + stringHeight * 2)
                .animation(animate ? animation : nullAnimation, value: animate)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    // 좌우에 그라데이션 마스크를 적용해 자연스러운 페이드 효과 구현
    @ViewBuilder
    private func fadeMask(leftFade: CGFloat, rightFade: CGFloat) -> some View {
        HStack(spacing: 0) {
            Rectangle().frame(width: 2).opacity(0)

            // 왼쪽 그라데이션
            LinearGradient(
                gradient: Gradient(colors: [Color.black.opacity(0), Color.black]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: leftFade)

            // 중앙은 불투명하게 유지
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color.black]),
                startPoint: .leading,
                endPoint: .trailing
            )

            // 오른쪽 그라데이션
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: rightFade)

            Rectangle().frame(width: 2).opacity(0)
        }
    }

    // 생성자: 기본 정렬값은 topLeading
    public init(
        text: String,
        font: UIFont,
        leftFade: CGFloat,
        rightFade: CGFloat,
        startDelay: Double,
        alignment: Alignment? = nil
    ) {
        self.text = text
        self.font = font
        self.leftFade = leftFade
        self.rightFade = rightFade
        self.startDelay = startDelay
        self.alignment = alignment ?? .topLeading
    }
}

// 텍스트가 프레임에 맞춰 딱 붙게 표시되도록 compact 모드 설정
extension MarqueeText {
    public func makeCompact(_ compact: Bool = true) -> Self {
        var view = self
        view.isCompact = compact
        return view
    }
}

// 텍스트 크기 측정을 위한 확장: UIFont 기준
extension String {
    func widthOfString(usingFont font: UIFont) -> CGFloat {
        let fontAttributes = [NSAttributedString.Key.font: font]
        let size = self.size(withAttributes: fontAttributes)
        return size.width
    }

    func heightOfString(usingFont font: UIFont) -> CGFloat {
        let fontAttributes = [NSAttributedString.Key.font: font]
        let size = self.size(withAttributes: fontAttributes)
        return size.height
    }
}
