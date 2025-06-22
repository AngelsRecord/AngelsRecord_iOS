//
//  ContentView.swift
//  AnglesRecord
//
//  Created by 광로 on 5/25/25.
//

import SwiftUI

struct ContentView: View {
    @State private var showSplash = true
    @AppStorage("accessGranted") private var accessGranted = false

    var body: some View {
        ZStack {
            if showSplash {
                SplashView()
                    .transition(.opacity)
            } else {
                if accessGranted {
                    MainView()
                        .transition(.opacity)
                } else {
                    AuthView()
                        .transition(.opacity)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    showSplash = false
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
