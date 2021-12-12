//
//  objView.swift
//  visual
//
//  Created by Chi-Ping Su on 2021/10/29.
//

import SwiftUI

struct objView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    func makeUIViewController(context: Context) -> UIViewController {
        return objViewController()
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        
    }
}

struct objView_Previews: PreviewProvider {
    static var previews: some View {
        objView()
    }
}
