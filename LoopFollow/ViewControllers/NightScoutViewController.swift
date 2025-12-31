//
// NightscoutViewController.swift
//  LoopFollow
//
//  Created by Jon Fawcett on 6/1/20.
//  Copyright © 2020 Jon Fawcett. All rights reserved.
//

import UIKit
import WebKit



class NightscoutViewController: ThemedViewController {

    @IBOutlet weak var webView: WKWebView!
    
    var appStateController: AppStateController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if UserDefaultsRepository.forceDarkMode.value {
            overrideUserInterfaceStyle = .dark
        }
        // Re-apply theme after potential style override
        updateBackgroundForCurrentMode()
        
        var url = ObservableUserDefaults.shared.url.value
        let token = UserDefaultsRepository.token.value
        
        if token != "" {
            url = url + "?token=" + token
        }
        
        guard let myUrl = URL(string: url) else { return  }

        //webView.configuration.preferences.javaScriptEnabled = true
        let webpagePreferences = WKWebpagePreferences()
        webpagePreferences.allowsContentJavaScript = true
        webView.configuration.defaultWebpagePreferences = webpagePreferences
        
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: myUrl))
        
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(reloadWebView(_:)), for: .valueChanged)
        webView.scrollView.addSubview(refreshControl)
        
        //self.webView.uiDelegate = self
    }
    
    @objc func reloadWebView(_ sender: UIRefreshControl) {
        self.clearWebCache()
        self.webView.reload()
        sender.endRefreshing()
    }
    
    // New code to clear web cache
    func clearWebCache() {
        let dataStore = WKWebsiteDataStore.default()
        let cacheTypes = Set([WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache])
        let date = Date(timeIntervalSince1970: 0)
        dataStore.removeData(ofTypes: cacheTypes, modifiedSince: date) {
            LogManager.shared.log(category: .nightscout, message: "Web cache cleared.", isDebug: true)
        }
      }
    
    // this handles target=_blank links by opening them in the same view
    func webView(webView: WKWebView!, createWebViewWithConfiguration configuration: WKWebViewConfiguration!, forNavigationAction navigationAction: WKNavigationAction!, windowFeatures: WKWindowFeatures!) -> WKWebView! {
        if let frame = navigationAction.targetFrame,
            frame.isMainFrame {
            return nil
        }
        // for _blank target or non-mainFrame target
        webView.load(navigationAction.request)
        return nil    }
}

// MARK:- WKUIDelegate implementation
extension NightscoutViewController: WKNavigationDelegate, WKUIDelegate {
    
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        
        let alertCtrl = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        
        alertCtrl.addAction(UIAlertAction(title: "OK", style: .default) { action in
            completionHandler(true)
        })

        alertCtrl.addAction(UIAlertAction(title: "Cancel", style: .cancel) { action in
            completionHandler(false)
        })
        
        present(alertCtrl, animated: true)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        
        guard let _ = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
     
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, shouldStartLoadWith request: URLRequest) -> Bool {
        
        guard let url = request.url else {
            return false
        }
        
        LogManager.shared.log(category: .nightscout, message: "Should start: \(url.absoluteString)")
        return true
    }
    
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        
        return nil
    }
    
    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            let javascript = """
            var meta = document.querySelector('meta[name="viewport"]');
            if (meta) {
                meta.setAttribute('content', 'width=device-width, initial-scale=0.9, maximum-scale=5.0, user-scalable=yes');
            }
            """

            webView.evaluateJavaScript(javascript)
        }
    

 
}
