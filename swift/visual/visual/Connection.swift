//
//  Connection.swift
//  visual
//
//  Created by Chi-Ping Su on 2021/6/13.
//

import Foundation

class Connection: NSObject, ObservableObject {
    @Published var responseStatus = ""
    @Published var conStatus = false
    let url = URL(string: "https://visualzzz.herokuapp.com/sos")
    
    func SendMsg(user_id: String, user_name: String, lat: String, long: String)
    {
        if user_id != "" && user_name != ""{
            guard let requestUrl = url else { fatalError() }
            var request = URLRequest(url: requestUrl)
            request.httpMethod = "POST"
            
            let currentDate = Date()
            let dataFormatter = DateFormatter()
            dataFormatter.locale = Locale(identifier: "zh_Hant_TW")
            dataFormatter.dateFormat = "YYYY-MM-dd HH:mm:ss"
            let stringDate = dataFormatter.string(from: currentDate)
            
            let postString = "user_id="+user_id+"&name="+user_name+"&lat="+lat+"&long="+long+"&dtime="+stringDate;
            
            // Set HTTP Request Body
            request.httpBody = postString.data(using: String.Encoding.utf8);
            
            // Perform HTTP Request
            let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                if error != nil {
                    self.responseStatus = "Server Error!"
                }
                if let data = data, let dataString = String(data: data, encoding: .utf8) {
                    self.responseStatus = dataString
                }
                self.conStatus=true
            }
            task.resume()
        }
    }
}
