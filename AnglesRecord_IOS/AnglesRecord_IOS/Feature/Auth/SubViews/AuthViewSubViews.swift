//
//  AuthViewSubViews.swift
//  AnglesRecord_IOS
//
//  Created by 성현 on 6/22/25.
//

import SwiftUI
import UIKit

struct SecureLimitedTextField: UIViewRepresentable {
    @Binding var text: String

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SecureLimitedTextField

        init(_ parent: SecureLimitedTextField) {
            self.parent = parent
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            // 새로운 문자열 계산
            let currentText = textField.text ?? ""
            guard let stringRange = Range(range, in: currentText) else { return false }
            let updatedText = currentText.replacingCharacters(in: stringRange, with: string)

            // 10자 이내로 제한
            if updatedText.count <= 10 {
                parent.text = updatedText
                return true
            } else {
                return false
            }
        }

        // 붙여넣기 비활성화
        override func responds(to aSelector: Selector!) -> Bool {
            if aSelector == #selector(UIResponderStandardEditActions.paste(_:)) {
                return false
            }
            return super.responds(to: aSelector)
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.placeholder = "접근 코드 (최대 10자)"
        textField.borderStyle = .roundedRect
        textField.keyboardType = .asciiCapable
        textField.autocorrectionType = .no
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        uiView.text = text
    }
}

