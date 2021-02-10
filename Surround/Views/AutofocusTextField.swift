//
//  AutofocusTextField.swift
//  Surround
//
//  Created by Anh Khoa Hong on 07/02/2021.
//

import SwiftUI

struct AutofocusTextField: UIViewRepresentable {
    typealias UIViewType = UITextField
    
    @Binding var text: String
    @Binding var isEditing: Bool
    var placeholder: String?
    var textStyle = UIFont.TextStyle.body
    var onEditingDone: () -> () = {}
    
    class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        @Binding var isEditing: Bool
        var onEditingDone: () -> ()
        
        init(text: Binding<String>, isEditing: Binding<Bool>, onEditingDone: @escaping () -> ()) {
            self._text = text
            self._isEditing = isEditing
            self.onEditingDone = onEditingDone
        }
        
        func textFieldDidChangeSelection(_ textField: UITextField) {
            self.text = textField.text ?? ""
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            self.isEditing = false
            textField.resignFirstResponder()
            self.onEditingDone()
            return true
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(text: $text, isEditing: $isEditing, onEditingDone: onEditingDone)
    }
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.returnKeyType = .done
        textField.font = UIFont.preferredFont(forTextStyle: textStyle)
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        uiView.text = text
        if !uiView.isFirstResponder && isEditing {
            uiView.becomeFirstResponder()
        }
    }
}

