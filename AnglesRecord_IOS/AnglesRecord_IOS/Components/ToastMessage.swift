//
//  ToastMessage.swift
//  AnglesRecord_IOS
//
//  Created by Seungeun Park on 8/12/25.
//
import SwiftUI

struct ToastMessage: View {
    
    var body: some View {
        HStack(spacing: 8) {
                Circle()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(.toastBlack)
                    .overlay {
                        Image(systemName: "exclamationmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.toastRed)
                            .frame(width: 12, height: 12)
                    }

            Text("인증코드를 확인해 주세요")
                .font(.system(size:14, weight: .semibold))
                .foregroundColor(.buttonText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.toastBlack)
        .cornerRadius(20)
//        .overlay(
//            RoundedRectangle(cornerRadius: 28)
//                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
//        )
//        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
    }
}

#Preview {
    ToastMessage()
}
