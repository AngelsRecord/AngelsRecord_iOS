import SwiftUI
import FirebaseFirestore
import FirebaseFunctions

struct AuthView: View {
    @State private var code: String = ""
    @State private var isAuthenticated = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("접근 코드 입력")
                .font(.title)
            
            SecureLimitedTextField(text: $code)
                .frame(height: 44)
                .padding()

            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            }
            
            Button("확인") {
                verifyCode(code)
            }
            .padding()
        }
        .padding()
        .fullScreenCover(isPresented: $isAuthenticated) {
            MainView()
        }
    }
    
    func verifyCode(_ input: String) {
        let functions = Functions.functions()

        functions.httpsCallable("verifyAccessCode").call(["code": input]) { result, error in
            if let error = error {
                print("❌ 인증 실패: \(error.localizedDescription)")
                errorMessage = "잘못된 코드입니다."
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
