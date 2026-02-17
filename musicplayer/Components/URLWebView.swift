//
//  URLWebView.swift
//  musicplayer
//
//  Wraps WKWebView to display a URL (e.g. https://chatgpt.com/) in the app body.
//

import SwiftUI
import WebKit

struct URLWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}
