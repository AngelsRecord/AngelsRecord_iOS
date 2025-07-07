import SwiftUI
import FirebaseFirestore
import FirebaseFunctions

extension View {
    func endTextEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct AuthView: View {
    @State private var code: String = ""
    @State private var isAuthenticated = false
    @State private var errorMessage: String?
    
    
    var body: some View {
        VStack {
            Text("인증 코드를\n입력해주세요.")
                .font(.title)
                .bold()
                .padding(.trailing, 220)
                .padding(.top, 73)
            
            SecureLimitedTextField(text: $code)
                .frame(height: 64)
                .padding(.top, 54)


            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            }
            
            Spacer()
            ZStack{
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { self.endTextEditing() }
            }
            
            
            Button("시작하기") {
                verifyCode(code)
            }
            .frame(width:353, height: 64)
            .background((code.isEmpty ? Color("subText") : Color("mainBlue")))
            .foregroundColor(.buttonText)
            .cornerRadius(8)
            .padding(.bottom, 20)
        }
        .onTapGesture {
            self.endTextEditing()
        }
        .fullScreenCover(isPresented: $isAuthenticated) {
            MainView()
        }
    }
    
    func verifyCode(_ input: String) {
        let functions = Functions.functions()

        functions.httpsCallable("verifyAccessCode").call(["code": input]) { result, error in
            if let error = error {
                print("❌ 인증 실패: \(error.localizedDescription)")
//                errorMessage = "잘못된 코드입니다."
            } else if let data = result?.data as? [String: Any],
                      let channelId = data["channelId"] as? String {
                print("✅ 인증 성공: \(channelId)")
                isAuthenticated = true

                // 🔐 Keychain에 저장 (String → String)
                let status = KeychainHelper.save("verifiedAccessCode", value: channelId)
                print("🔐 키체인 저장 결과: \(status == errSecSuccess ? "성공" : "실패(\(status))")")
            } else {
                errorMessage = "응답 형식 오류"
            }
        }
    }
}



