//
//  WebViewWrapper.swift
//  musicplayer
//
//  Wraps WKWebView with ChatGPT bridge script: find input/send button, sendToChatGPT(message),
//  getChatGPTResponse(), duckAudio/restoreAudio. Uses WebViewStore for sendMessageToChatGPT etc.
//

import SwiftUI
import WebKit
import AppKit

struct WebViewWrapper: NSViewRepresentable {
    @Binding var url: URL?
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    var webViewStore: WebViewStore?
    var onChatGPTReady: (() -> Void)?

    init(
        url: Binding<URL?>,
        isLoading: Binding<Bool>,
        canGoBack: Binding<Bool>,
        canGoForward: Binding<Bool>,
        webViewStore: WebViewStore? = nil,
        onChatGPTReady: (() -> Void)? = nil
    ) {
        _url = url
        _isLoading = isLoading
        _canGoBack = canGoBack
        _canGoForward = canGoForward
        self.webViewStore = webViewStore
        self.onChatGPTReady = onChatGPTReady
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        if #available(macOS 11.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
            config.preferences.isTextInteractionEnabled = true
        }
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.applicationNameForUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "chatGPTBridge")

        let chatGPTScript = Self.chatGPTBridgeScript
        let userScript = WKUserScript(source: chatGPTScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        contentController.addUserScript(userScript)
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webViewStore?.webView = webView

        if let u = url {
            webView.load(URLRequest(url: u))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private static var chatGPTBridgeScript: String {
        """
        (function() {
        function findChatGPTElements() {
            var inputSelectors = [
                'textarea[data-id="root"]', 'textarea[placeholder*="Message"]', 'textarea[placeholder*="ChatGPT"]',
                '#prompt-textarea', 'textarea[rows="1"]', 'div[contenteditable="true"]', 'textarea'
            ];
            var sendButtonSelectors = [
                'button[data-testid="send-button"]', 'button[aria-label*="Send"]', 'button[type="submit"]',
                'button svg[data-icon="send"]', '[data-testid="fruitjuice-send-button"]'
            ];
            var input = null, sendButton = null;
            for (var i = 0; i < inputSelectors.length; i++) {
                try {
                    var el = document.querySelector(inputSelectors[i]);
                    if (el && (el.offsetWidth > 0 || el.offsetHeight > 0)) { input = el; break; }
                } catch (e) {}
            }
            for (var j = 0; j < sendButtonSelectors.length; j++) {
                try {
                    var btn = document.querySelector(sendButtonSelectors[j]);
                    if (btn && (btn.offsetWidth > 0 || btn.offsetHeight > 0)) { sendButton = btn; break; }
                } catch (e) {}
            }
            return { input: input, sendButton: sendButton };
        }
        function waitForChatGPT() {
            var elements = findChatGPTElements();
            if (elements.input) {
                window.webkit.messageHandlers.chatGPTBridge.postMessage({
                    type: 'ready',
                    inputFound: !!elements.input,
                    sendButtonFound: !!elements.sendButton
                });
                return true;
            }
            return false;
        }
        function sendToChatGPT(message) {
            var proseMirrorEditor = document.getElementById('prompt-textarea');
            if (proseMirrorEditor) {
                try {
                    proseMirrorEditor.focus();
                    proseMirrorEditor.innerHTML = '<p><br></p>';
                    setTimeout(function() {
                        proseMirrorEditor.innerHTML = '<p>' + message.replace(/</g, '&lt;').replace(/>/g, '&gt;') + '</p>';
                        proseMirrorEditor.dispatchEvent(new Event('input', { bubbles: true }));
                        proseMirrorEditor.dispatchEvent(new Event('change', { bubbles: true }));
                        setTimeout(function() {
                            var enterKeyDown = new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true, cancelable: true });
                            var enterKeyUp = new KeyboardEvent('keyup', { key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true });
                            proseMirrorEditor.dispatchEvent(enterKeyDown);
                            proseMirrorEditor.dispatchEvent(enterKeyUp);
                            setTimeout(function() { proseMirrorEditor.innerHTML = '<p><br></p>'; }, 1000);
                        }, 300);
                    }, 100);
                    return true;
                } catch (e) { return false; }
            }
            var textareas = document.querySelectorAll('textarea');
            for (var i = 0; i < textareas.length; i++) {
                var ta = textareas[i];
                if (ta.offsetParent !== null && !ta.disabled) {
                    try {
                        ta.focus();
                        ta.value = message;
                        ta.dispatchEvent(new Event('input', { bubbles: true }));
                        ta.dispatchEvent(new Event('change', { bubbles: true }));
                        var sendBtn = document.querySelector('button[data-testid*="send"], button[aria-label*="Send"], button[type="submit"]');
                        if (sendBtn && sendBtn.offsetParent !== null) {
                            setTimeout(function() { sendBtn.click(); }, 200);
                            return true;
                        }
                        setTimeout(function() {
                            ta.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true }));
                        }, 200);
                        return true;
                    } catch (e) {}
                }
            }
            var editables = document.querySelectorAll('[contenteditable="true"]');
            for (var k = 0; k < editables.length; k++) {
                var el = editables[k];
                if (el.offsetParent !== null) {
                    try {
                        el.focus();
                        el.textContent = message;
                        el.dispatchEvent(new Event('input', { bubbles: true }));
                        setTimeout(function() {
                            el.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true }));
                        }, 200);
                        return true;
                    } catch (e) {}
                }
            }
            return false;
        }
        function getChatGPTResponse() {
            var selectors = ['[data-message-author-role="assistant"]', '.markdown', '[data-testid="conversation-turn-3"]', '.prose'];
            for (var i = 0; i < selectors.length; i++) {
                try {
                    var nodes = document.querySelectorAll(selectors[i]);
                    if (nodes.length > 0) return (nodes[nodes.length - 1].textContent || nodes[nodes.length - 1].innerText || '').trim();
                } catch (e) {}
            }
            return '';
        }
        function inspectChatGPTDOM() {
            var report = { textareas: [], buttons: [] };
            document.querySelectorAll('textarea').forEach(function(ta, i) {
                report.textareas.push({ index: i, id: ta.id || '', placeholder: ta.placeholder || '', visible: ta.offsetParent !== null });
            });
            document.querySelectorAll('button').forEach(function(btn, i) {
                if (i < 20) report.buttons.push({ index: i, ariaLabel: btn.getAttribute('aria-label') || '', dataTestId: btn.getAttribute('data-testid') || '', visible: btn.offsetParent !== null });
            });
            return report;
        }
        var observer = new MutationObserver(function() {
            if (!window.chatGPTReady) waitForChatGPT();
        });
        observer.observe(document.body, { childList: true, subtree: true });
        setTimeout(function() { if (waitForChatGPT()) window.chatGPTReady = true; }, 1000);
        var checkInterval = setInterval(function() {
            if (!window.chatGPTReady && waitForChatGPT()) { window.chatGPTReady = true; clearInterval(checkInterval); }
        }, 2000);
        window.sendToChatGPT = sendToChatGPT;
        window.getChatGPTResponse = getChatGPTResponse;
        window.findChatGPTElements = findChatGPTElements;
        window.inspectChatGPTDOM = inspectChatGPTDOM;
        window.duckAudio = function(vol) {
            vol = vol || 0.1;
            document.querySelectorAll('video').forEach(function(v) {
                if (v.volume !== undefined) { v.dataset.originalVolume = v.volume; v.volume = vol; }
            });
            if (window.ytplayer && window.ytplayer.setVolume) {
                window.ytplayer.dataset.originalVolume = window.ytplayer.getVolume();
                window.ytplayer.setVolume(vol * 100);
            }
        };
        window.restoreAudio = function() {
            document.querySelectorAll('video').forEach(function(v) {
                if (v.dataset.originalVolume !== undefined) { v.volume = parseFloat(v.dataset.originalVolume); delete v.dataset.originalVolume; }
            });
            if (window.ytplayer && window.ytplayer.setVolume && window.ytplayer.dataset.originalVolume) {
                window.ytplayer.setVolume(parseFloat(window.ytplayer.dataset.originalVolume));
                delete window.ytplayer.dataset.originalVolume;
            }
        };
        })();
        """
    }
}

extension WebViewWrapper {
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: WebViewWrapper

        init(_ parent: WebViewWrapper) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = NSAlert()
            alert.messageText = "Website Alert"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
            completionHandler()
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = NSAlert()
            alert.messageText = "Confirm"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "chatGPTBridge",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String, type == "ready" else { return }
            DispatchQueue.main.async {
                self.parent.webViewStore?.isChatGPTReady = true
                self.parent.onChatGPTReady?()
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
                self.parent.webViewStore?.isChatGPTReady = false
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }
    }
}
