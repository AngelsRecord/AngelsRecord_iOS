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

    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }
    
    class BottomPaddedTextField: UITextField {
        override func textRect(forBounds bounds: CGRect) -> CGRect {
            return bounds.inset(by: UIEdgeInsets(top: 0, left: 0, bottom: 28, right: 0))
        }

        override func editingRect(forBounds bounds: CGRect) -> CGRect {
            return bounds.inset(by: UIEdgeInsets(top: 0, left: 0, bottom: 28, right: 0))
        }

        override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
            return bounds.inset(by: UIEdgeInsets(top: 0, left: 0, bottom: 28, right: 0))
        }
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = BottomPaddedTextField()
        textField.delegate = context.coordinator
        textField.placeholder = "인증 코드 입력"
        textField.borderStyle = .none
        let bottomLine = CALayer()
        bottomLine.frame = CGRect(x: 0.0, y: 43.0, width: UIScreen.main.bounds.width - 60, height: 1.0)
        bottomLine.backgroundColor = UIColor(named: "subText")?.cgColor
        textField.layer.addSublayer(bottomLine)
        textField.keyboardType = .asciiCapable
        textField.autocorrectionType = .no
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        uiView.text = text
    }
}
