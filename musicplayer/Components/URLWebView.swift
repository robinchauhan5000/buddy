//
//  URLWebView.swift
//  musicplayer
//
//  Wraps WKWebView to display a URL (e.g. https://chatgpt.com/) in the app body.
//  When injectText is set, runs JavaScript to find an input/textarea and set its value.
//

import SwiftUI
import WebKit

struct URLWebView: NSViewRepresentable {
    let url: URL
    @Binding var injectText: String?

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
        if let text = injectText, !text.isEmpty {
            // JSONSerialization requires top-level Array or Dictionary; wrap in array then extract quoted string
            let escaped: String
            if let data = try? JSONSerialization.data(withJSONObject: [text]),
               let str = String(data: data, encoding: .utf8),
               str.count >= 2 {
                escaped = String(str.dropFirst().dropLast()) // "[\"x\"]" -> "\"x\""
            } else {
                escaped = "\"\""
            }
            // Try multiple selectors (ChatGPT uses #prompt-textarea or contenteditable)
            let script = """
            (function(){
              var text = \(escaped);
              var selectors = ['#prompt-textarea', 'textarea', 'input[type="text"]', 'input:not([type])', 'input', '[contenteditable="true"]', '[data-placeholder]'];
              var el = null;
              for (var i = 0; i < selectors.length; i++) {
                el = document.querySelector(selectors[i]);
                if (el && (el.offsetParent !== null || el.tagName === 'TEXTAREA' || el.tagName === 'INPUT')) break;
              }
              if (!el) return;
              el.focus();
              if (el.contentEditable === 'true' || el.getAttribute('contenteditable') === 'true') {
                el.innerText = text;
                el.textContent = text;
                el.dispatchEvent(new InputEvent('input', { bubbles: true, data: text }));
                el.dispatchEvent(new Event('change', { bubbles: true }));
              } else {
                try {
                  var desc = (el.tagName === 'TEXTAREA')
                    ? Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value')
                    : Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
                  if (desc && desc.set) { desc.set.call(el, text); } else { el.value = text; }
                } catch (e) {
                  el.value = text;
                }
                el.dispatchEvent(new Event('input', { bubbles: true }));
                el.dispatchEvent(new Event('change', { bubbles: true }));
              }
            })();
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
            // Defer clearing to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                injectText = nil
            }
        }
    }
}
