//
//  NCLoginWeb.swift
//  Nextcloud
//
//  Created by Marino Faggiana on 21/08/2019.
//  Copyright © 2019 Marino Faggiana. All rights reserved.
//
//  Author Marino Faggiana <marino.faggiana@nextcloud.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation

@objc protocol NCLoginWebDelegate: class {
    func loginSuccess(_: NSInteger)
    @objc optional func webDismiss()
}

class NCLoginWeb: UIViewController {
    
    var webView: WKWebView?
    let appDelegate = UIApplication.shared.delegate as! AppDelegate

    @objc var urlBase = ""
    @objc var loginType: Int = 0
    @objc weak var delegate: NCLoginWebDelegate?

    @IBOutlet weak var buttonExit: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        webView = WKWebView(frame: CGRect.zero, configuration: config)
        webView!.navigationDelegate = self
        view.addSubview(webView!)
        webView!.translatesAutoresizingMaskIntoConstraints = false
        webView!.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0).isActive = true
        webView!.rightAnchor.constraint(equalTo: view.rightAnchor, constant: 0).isActive = true
        webView!.topAnchor.constraint(equalTo: view.topAnchor, constant: 0).isActive = true
        webView!.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0).isActive = true
        
        // ADD k_flowEndpoint for Web Flow
        if NCBrandOptions.sharedInstance.use_login_web_personalized == false && urlBase != NCBrandOptions.sharedInstance.linkloginPreferredProviders {
            urlBase =  urlBase + k_flowEndpoint
        }
        
        // button exit
        if loginType == k_login_Add_Forced {
            buttonExit.isHidden = true
        } else {
            self.view.bringSubviewToFront(buttonExit)
        }
        
        loadWebPage(webView: webView!, url: URL(string: urlBase)!)
    }
    
    func loadWebPage(webView: WKWebView, url: URL)  {
        
        let language = NSLocale.preferredLanguages[0] as String
        var request = URLRequest(url: url)
        
        request.setValue(CCUtility.getUserAgent(), forHTTPHeaderField: "User-Agent")
        request.addValue("true", forHTTPHeaderField: "OCS-APIRequest")
        request.addValue(language, forHTTPHeaderField: "Accept-Language")
        
        webView.load(request)
    }
    
    @IBAction func touchUpInsideButtonExit(_ sender: UIButton) {
        self.dismiss(animated: true) {
            self.delegate?.webDismiss?()
        }
    }
}

extension NCLoginWeb: WKNavigationDelegate {
    
    public func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        
        guard let url = webView.url else { return }
        
        let urlString: String = url.absoluteString.lowercased()
        
        if (urlString.hasPrefix(NCBrandOptions.sharedInstance.webLoginAutenticationProtocol) == true && urlString.contains("login") == true) {
            
            let keyValue = url.path.components(separatedBy: "&")
            if (keyValue.count >= 3) {
                
                if (keyValue[0].contains("server:") && keyValue[1].contains("user:") && keyValue[2].contains("password:")) {
                    
                    var serverUrl : String = keyValue[0].replacingOccurrences(of: "/server:", with: "")
                    
                    // Login Flow NC 12
                    if (NCBrandOptions.sharedInstance.use_login_web_personalized == false && serverUrl.hasPrefix("http://") == false && serverUrl.hasPrefix("https://") == false) {
                        serverUrl = urlBase
                    }
                    
                    if (serverUrl.last == "/") {
                        serverUrl = String(serverUrl.dropLast())
                    }
                    
                    let username : String = keyValue[1].replacingOccurrences(of: "user:", with: "").replacingOccurrences(of: "+", with: " ")
                    let password : String = keyValue[2].replacingOccurrences(of: "password:", with: "")
                    
                    let account : String = "\(username) \(serverUrl)"
                    
                    // Login Flow
                    if (loginType == k_login_Modify_Password && NCBrandOptions.sharedInstance.use_login_web_personalized == false) {
                        
                        // Verify if change the active account
                        guard let activeAccount = NCManageDatabase.sharedInstance.getAccountActive() else {
                            self.dismiss(animated: true, completion: nil)
                            return
                        }
                        if (activeAccount.account != account) {
                            self.dismiss(animated: true, completion: nil)
                            return
                        }
                        
                        // Change Password & setting active account
                        CCUtility.setPassword(account, password: password)
                        appDelegate.settingActiveAccount(account, activeUrl: serverUrl, activeUser: username, activeUserID: appDelegate.activeUserID, activePassword: password)
                        
                        self.dismiss(animated: true) {
                            self.delegate?.loginSuccess(NSInteger(self.loginType))
                            self.delegate?.webDismiss?()
                        }
                    }
                    
                    if (loginType == k_login_Add || loginType == k_login_Add_Forced) {
                        
                        // NO account found, clear
                        if NCManageDatabase.sharedInstance.getAccounts() == nil {
                            NCUtility.sharedInstance.removeAllSettings()
                        }
                        
                        // STOP Intro
                        CCUtility.setIntro(true)
                        
                        // Add new account
                        NCManageDatabase.sharedInstance.deleteAccount(account)
                        NCManageDatabase.sharedInstance.addAccount(account, url: serverUrl, user: username, password: password, loginFlow: true)
                        
                        guard let tableAccount = NCManageDatabase.sharedInstance.setAccountActive(account) else {
                            self.dismiss(animated: true, completion: nil)
                            return
                        }
                        
                        appDelegate.settingActiveAccount(account, activeUrl: serverUrl, activeUser: username, activeUserID: tableAccount.userID, activePassword: password)
                        
                        self.dismiss(animated: true) {
                            self.delegate?.loginSuccess(NSInteger(self.loginType))
                            self.delegate?.webDismiss?()
                        }
                    }
                }
            }
        }
    }
    
    public func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(Foundation.URLSession.AuthChallengeDisposition.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(URLSession.AuthChallengeDisposition.useCredential, nil);
        }
    }
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        
        decisionHandler(.allow)

        /*
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        
        if String(describing: url).hasPrefix(NCBrandOptions.sharedInstance.webLoginAutenticationProtocol) {
            decisionHandler(.allow)
            return
        } else if navigationAction.request.httpMethod != "GET" || navigationAction.request.value(forHTTPHeaderField: "OCS-APIRequest") != nil {
            decisionHandler(.allow)
            return
        }
        
        decisionHandler(.cancel)
        
        let language = NSLocale.preferredLanguages[0] as String
        var request = URLRequest(url: url)
        
        request.setValue(CCUtility.getUserAgent(), forHTTPHeaderField: "User-Agent")
        request.addValue("true", forHTTPHeaderField: "OCS-APIRequest")
        request.addValue(language, forHTTPHeaderField: "Accept-Language")
        
        webView.load(request)
        */
    }
    
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        print("didStartProvisionalNavigation");
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("didFinishProvisionalNavigation");
    }
}