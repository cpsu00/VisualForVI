//
//  UserSettings.swift
//  visual
//
//  Created by Chi-Ping Su on 2021/6/12.
//

import Foundation
import Combine

class UserSettings: ObservableObject {
    @Published var user_name: String {
        didSet {
            UserDefaults.standard.set(user_name, forKey: "user_name")
        }
    }
    
    @Published var user_id: String {
        didSet {
            UserDefaults.standard.set(user_id, forKey: "user_id")
        }
    }
    
    @Published var user_dist: Float {
        didSet {
            UserDefaults.standard.set(user_dist, forKey: "user_dist")
        }
    }
    
    @Published var user_lr: Float {
        didSet {
            UserDefaults.standard.set(user_lr, forKey: "user_lr")
        }
    }
    
    init() {
        self.user_name = UserDefaults.standard.object(forKey: "user_name") as? String ?? ""
        self.user_id = UserDefaults.standard.object(forKey: "user_id") as? String ?? ""
        self.user_dist = UserDefaults.standard.object(forKey: "user_dist") as? Float ?? 1.5
        self.user_lr = UserDefaults.standard.object(forKey: "user_lr") as? Float ?? 60.0
    }
}
