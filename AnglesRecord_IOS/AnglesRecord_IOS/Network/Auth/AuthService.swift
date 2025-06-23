import FirebaseAuth
import FirebaseFunctions

struct AuthService {
    static func signInAnonymouslyIfNeeded() {
        if Auth.auth().currentUser == nil {
            Auth.auth().signInAnonymously { result, error in
                if let error = error {
                    print("❌ 로그인 실패: \(error)")
                } else {
                    print("✅ 로그인 성공: \(result?.user.uid ?? "")")
                }
            }
        }
    }
}


let functions = Functions.functions()

func verifyAccessCode(_ input: String, completion: @escaping (String?) -> Void) {
    functions.httpsCallable("verifyAccessCode").call(["code": input]) { result, error in
        if let error = error {
            print("❌ 인증 실패: \(error.localizedDescription)")
            completion(nil)
        } else if let data = result?.data as? [String: Any],
                  let channelId = data["channelId"] as? String {
            print("✅ 인증 성공: \(channelId)")
            completion(channelId)
        } else {
            completion(nil)
        }
    }
}
