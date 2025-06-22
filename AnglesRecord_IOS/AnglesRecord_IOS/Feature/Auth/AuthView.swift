import SwiftUI
import FirebaseFirestore

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
        let db = Firestore.firestore()
        db.collection("accessCodes")
            .whereField("code", isEqualTo: input)
            .getDocuments { snapshot, error in
                if let docs = snapshot?.documents, !docs.isEmpty {
                    isAuthenticated = true
                    // 필요 시 UserDefaults 등에 인증 상태 저장
                } else {
                    errorMessage = "잘못된 코드입니다."
                }
            }
    }
}
