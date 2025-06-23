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
            
            TextField("예: secret123", text: $code)
                .textFieldStyle(RoundedBorderTextFieldStyle())
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
                // UserDefaults.standard.set(channelId, forKey: "userChannelId") 등 저장 가능
            } else {
                errorMessage = "응답 형식 오류"
            }
        }
    }
}
