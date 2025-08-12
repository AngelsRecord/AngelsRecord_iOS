//
//  ToastMessage.swift
//  AnglesRecord_IOS
//
//  Created by Seungeun Park on 8/12/25.
//
import SwiftUI

struct EKOToastMessage: View {
    
    var body: some View {
        HStack(spacing: 8) {
                Circle()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(.mainWhite)
                    .overlay {
                        Image(systemName: "exclamationmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle()
                            .frame(width: 12, height: 12)
                    }

            Text("인증코드를 확인해 주세요.")
                .font(.textSemiBold02)
                .foregroundColor(.neutrals2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .setupGradientBackground(colors: [
            .mainWhite.opacity(0.8), .mainWhite.opacity(0.5)
        ])
        .cornerRadius(28)
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
    }
}
