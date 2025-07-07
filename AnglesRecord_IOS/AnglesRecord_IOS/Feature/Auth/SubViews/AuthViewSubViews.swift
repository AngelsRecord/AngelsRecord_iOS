//
//  AuthViewSubViews.swift
//  AnglesRecord_IOS
//
//  Created by 성현 on 6/22/25.
//

import SwiftUI

struct SecureLimitedTextField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool
    
    var isActive: Bool {
        isFocused || !text.isEmpty
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 라벨
            Text("인증 코드 입력")
                .font(.system(size: 15))
                .foregroundColor(isActive ? Color("mainBlue") : Color.gray)
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
                    .foregroundColor(.black)
                    .padding(.bottom, 6)
                    .onChange(of: text) { newValue in
                        if newValue.count > 10 {
                            text = String(newValue.prefix(10))
                        }
                    }
                
                if !text.isEmpty {
                    Button(action: {
                        text = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color("subText"))
                    }
                    .padding(.trailing, 4)
                }
            }
            
            // 밑줄
            Rectangle()
                .frame(height: 2)
                .foregroundColor(isActive ? Color("mainBlue") : Color.gray)
                .animation(.easeInOut(duration: 0.2), value: isActive)
        }
        .padding(.horizontal, 24)
    }
}

