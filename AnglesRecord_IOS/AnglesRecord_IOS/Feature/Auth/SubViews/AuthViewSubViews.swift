//
//  AuthViewSubViews.swift
//  AnglesRecord_IOS
//
//  Created by 성현 on 6/22/25.
//

import SwiftUI

struct SecureLimitedTextField: View {
    @Binding var text: String
    @Binding var isDisabled: Bool  // 새로운 바인딩 추가: 입력 비활성화 여부
    @FocusState private var isFocused: Bool
    
    var isActive: Bool {
        isFocused || !text.isEmpty
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 라벨
            Text("인증 코드 입력")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(isDisabled ? Color("subText") : (isActive ? Color("mainBlue") : Color("subText")))  // 비활성화 시 subText로 변경
                .offset(y: isActive ? 0 : 20)
                .scaleEffect(isActive ? 0.8 : 1.2, anchor: .leading)
                .animation(.easeInOut(duration: 0.2), value: isActive)
            
            // 텍스트 필드
            HStack{
                TextField("", text: $text)
                    .focused($isFocused)
                    .keyboardType(.asciiCapable)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .foregroundColor(.mainText)
                    .padding(.bottom, 6)
                    .onChange(of: text) { newValue in
                        if newValue.count > 10 {
                            text = String(newValue.prefix(10))
                        }
                    }
                    .disabled(isDisabled)  // 비활성화 바인딩 적용
                
                if !text.isEmpty {
                    Button(action: {
                        text = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color("subText"))
                    }
                    .padding(.trailing, 4)
                    .disabled(isDisabled)  // 클리어 버튼도 비활성화
                }
            }
            
            // 밑줄
            Rectangle()
                .frame(height: 2)
                .foregroundColor(isDisabled ? Color("subText") : (isActive ? Color("mainBlue") : Color("subText")))  // 비활성화 시 subText로 변경
                .animation(.easeInOut(duration: 0.2), value: isActive)
        }
    }
}

#Preview {
    SecureLimitedTextFieldPreviewWrapper()
}

private struct SecureLimitedTextFieldPreviewWrapper: View {
    @State private var inputText: String = ""
    @State private var isDisabled: Bool = false  // 프리뷰용 더미 바인딩

    var body: some View {
        SecureLimitedTextField(text: $inputText, isDisabled: $isDisabled)
    }
}
