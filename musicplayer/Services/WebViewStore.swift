//
//  WebViewStore.swift
//  musicplayer
//
//  Holds WKWebView reference and exposes methods to inject into the page (e.g. ChatGPT):
//  sendMessageToChatGPT, sendImageToChatGPT, duckAudio, restoreAudio, etc.
//

import Foundation
import Combine
import WebKit
import AppKit

final class WebViewStore: ObservableObject {
    var webView: WKWebView?
    @Published var isChatGPTReady = false

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        webView?.reload()
    }

    func loadURL(_ url: URL) {
        webView?.load(URLRequest(url: url))
    }

    /// Sends text to the page using the injected sendToChatGPT(message) JavaScript.
    /// Uses JSON escaping so the message is safe for injection.
    func sendMessageToChatGPT(_ message: String) {
        guard !message.isEmpty else { return }
        let escaped: String
        if let data = try? JSONSerialization.data(withJSONObject: [message]),
           let str = String(data: data, encoding: .utf8),
           str.count >= 2 {
            escaped = String(str.dropFirst().dropLast())
        } else {
            escaped = "\"\""
        }
        let script = """
        (function() {
            var cache = (window.__fnCache = window.__fnCache || {});
            if (!cache.sendToChatGPT) {
                if (typeof sendToChatGPT !== 'function') return;
                cache.sendToChatGPT = true;
            }
            sendToChatGPT(\(escaped));
        })();
        """
        webView?.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("❌ Error sending message to ChatGPT: \(error)")
            }
        }
    }

    func getChatGPTResponse(completion: @escaping (String) -> Void) {
        let script = """
        (function() {
            var cache = (window.__fnCache = window.__fnCache || {});
            if (!cache.getChatGPTResponse) {
                if (typeof getChatGPTResponse !== 'function') return '';
                cache.getChatGPTResponse = true;
            }
            return getChatGPTResponse();
        })();
        """
        webView?.evaluateJavaScript(script) { result, _ in
            DispatchQueue.main.async {
                completion((result as? String) ?? "")
            }
        }
    }

    func inspectDOM() {
        let script = """
        (function() {
            var cache = (window.__fnCache = window.__fnCache || {});
            if (!cache.inspectChatGPTDOM) {
                if (typeof inspectChatGPTDOM !== 'function') return;
                cache.inspectChatGPTDOM = true;
            }
            inspectChatGPTDOM();
        })();
        """
        webView?.evaluateJavaScript(script) { _, error in
            if let error = error { print("❌ Inspect DOM error: \(error)") }
        }
    }

    func clearAllData() {
        let dataStore = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0)) { }
    }

    func duckAudio() {
        let script = """
        (function() {
            var cache = (window.__fnCache = window.__fnCache || {});
            if (!cache.duckAudio) {
                if (typeof duckAudio !== 'function') return;
                cache.duckAudio = true;
            }
            duckAudio(0.1);
        })();
        """
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    func restoreAudio() {
        let script = """
        (function() {
            var cache = (window.__fnCache = window.__fnCache || {});
            if (!cache.restoreAudio) {
                if (typeof restoreAudio !== 'function') return;
                cache.restoreAudio = true;
            }
            restoreAudio();
        })();
        """
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Clicks the "Send prompt" button in ChatGPT. Use when Command is pressed in the webview.
    func triggerSendButton() {
        let script = """
        (function() {
            // Reuse cached reference if still in the DOM.
            if (window.__cachedSendBtn && document.contains(window.__cachedSendBtn)) {
                window.__cachedSendBtn.click();
                console.log('✅ Prompt sent via cache');
                return true;
            }

            var selectors = [
                '#composer-submit-button',
                'button[aria-label="Send prompt"]',
                'button[data-testid="send-button"]',
                'button[aria-label*="Send"]'
            ];

            for (var i = 0; i < selectors.length; i++) {
                try {
                    var btn = document.querySelector(selectors[i]);
                    if (btn && btn.offsetParent !== null && !btn.disabled) {
                        window.__cachedSendBtn = btn;
                        btn.click();
                        console.log('✅ Prompt sent');
                        return true;
                    }
                } catch (e) {}
            }

            window.__cachedSendBtn = null;
            console.log('❌ Send button not found');
            return false;
        })();
        """
        webView?.evaluateJavaScript(script) { _, _ in }
    }

    /// Toggles dictation in ChatGPT when Option is pressed in the webview.
    /// - First press: clicks "Dictate button" to start dictation.
    /// - Second press: clicks "Submit dictation" to submit it.
    /// Detection is DOM-driven — whichever button is currently visible wins.
    func triggerDictateButton() {
        let script = """
        (function() {
            function findVisible(sel) {
                try {
                    var el = document.querySelector(sel);
                    return (el && el.offsetParent !== null && !el.disabled) ? el : null;
                } catch (e) { return null; }
            }

            // If "Submit dictation" is present, dictation is already active — submit it.
            var submitBtn = findVisible('button[aria-label="Submit dictation"]');
            if (submitBtn) {
                window.__cachedDictateBtn = null;
                submitBtn.click();
                console.log('✅ Dictation submitted');
                return 'submitted';
            }

            // Reuse cached "Dictate button" reference if still in the DOM.
            if (window.__cachedDictateBtn && document.contains(window.__cachedDictateBtn)) {
                window.__cachedDictateBtn.click();
                console.log('✅ Dictation started via cache');
                return 'started';
            }

            // Fresh search for the dictate button.
            var dictateSelectors = [
                'button[aria-label="Dictate button"]',
                'button[aria-label*="Dictate"]',
                'button.composer-btn[aria-label*="ictate"]'
            ];
            for (var i = 0; i < dictateSelectors.length; i++) {
                var btn = findVisible(dictateSelectors[i]);
                if (btn) {
                    window.__cachedDictateBtn = btn;
                    btn.click();
                    console.log('✅ Dictation started');
                    return 'started';
                }
            }

            window.__cachedDictateBtn = null;
            console.log('❌ Neither Dictate nor Submit dictation button found');
            return false;
        })();
        """
        webView?.evaluateJavaScript(script) { _, _ in }
    }

    /// Handles Shift press in the webview — priority order:
    /// 1. Stop dictation  (aria-label="Stop dictation")  if dictation is active
    /// 2. Stop streaming  (aria-label="Stop streaming" / "Stop generating" / etc.)
    func stopStreamingInWebView() {
        let script = """
        (function() {
            function findVisible(sel) {
                try {
                    var el = document.querySelector(sel);
                    return (el && el.offsetParent !== null && !el.disabled) ? el : null;
                } catch (e) { return null; }
            }

            // Dictation takes priority — stop it first if it's active.
            var stopDictation = findVisible('button[aria-label="Stop dictation"]');
            if (stopDictation) {
                window.__cachedDictateBtn = null;
                stopDictation.click();
                console.log('✅ Dictation stopped');
                return 'dictation_stopped';
            }

            // Otherwise stop a running ChatGPT stream.
            var stopSelectors = [
                'button[aria-label="Stop streaming"]',
                'button[aria-label="Stop generating"]',
                '[data-testid="stop-generating"]',
                'button:has(svg[data-icon="stop"])'
            ];

            function trySelector(sel) {
                try {
                    var btn = document.querySelector(sel);
                    if (btn && btn.offsetParent !== null && !btn.disabled) {
                        btn.click();
                        window.__cachedStopSelector = sel;
                        return true;
                    }
                } catch (e) {}
                return false;
            }

            // Try the last-known working selector first to avoid iterating every time.
            if (window.__cachedStopSelector && trySelector(window.__cachedStopSelector)) {
                return 'stream_stopped';
            }

            // Full scan — update the cache with whichever selector succeeds.
            for (var i = 0; i < stopSelectors.length; i++) {
                if (trySelector(stopSelectors[i])) return 'stream_stopped';
            }

            window.__cachedStopSelector = null;
            return false;
        })();
        """
        webView?.evaluateJavaScript(script) { _, _ in }
    }

    /// Fills the ChatGPT text area with the given prompt (no auto-submit), then clicks the
    /// send button after a short delay so any already-attached files (screenshots) are included.
    /// Use this when Command is pressed to send a structured prompt alongside an attached image.
    func sendPromptWithAttachment(_ prompt: String) {
        guard !prompt.isEmpty else { return }
        let escaped: String
        if let data = try? JSONSerialization.data(withJSONObject: [prompt]),
           let str = String(data: data, encoding: .utf8),
           str.count >= 2 {
            escaped = String(str.dropFirst().dropLast())
        } else {
            escaped = "\"\""
        }
        let script = """
        (function() {
            function fillInput(message) {
                var editor = document.getElementById('prompt-textarea');
                if (editor) {
                    try {
                        editor.focus();
                        editor.innerHTML = '<p>' + message.replace(/</g, '&lt;').replace(/>/g, '&gt;') + '</p>';
                        editor.dispatchEvent(new Event('input', { bubbles: true }));
                        editor.dispatchEvent(new Event('change', { bubbles: true }));
                        return true;
                    } catch (e) {}
                }
                var textareas = document.querySelectorAll('textarea');
                for (var i = 0; i < textareas.length; i++) {
                    var ta = textareas[i];
                    if (ta.offsetParent !== null && !ta.disabled) {
                        try {
                            ta.focus();
                            ta.value = message;
                            ta.dispatchEvent(new Event('input', { bubbles: true }));
                            return true;
                        } catch (e) {}
                    }
                }
                return false;
            }

            if (!fillInput(\(escaped))) {
                console.log('❌ Could not fill prompt text');
                return;
            }

            setTimeout(function() {
                var selectors = [
                    '#composer-submit-button',
                    'button[aria-label="Send prompt"]',
                    'button[data-testid="send-button"]',
                    'button[aria-label*="Send"]'
                ];
                for (var i = 0; i < selectors.length; i++) {
                    try {
                        var btn = document.querySelector(selectors[i]);
                        if (btn && btn.offsetParent !== null && !btn.disabled) {
                            window.__cachedSendBtn = btn;
                            btn.click();
                            console.log('✅ Prompt with attachment sent');
                            return;
                        }
                    } catch (e) {}
                }
                console.log('❌ Send button not found after filling prompt');
            }, 500);
        })();
        """
        webView?.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("❌ Error sending prompt with attachment: \(error)")
            }
        }
    }

    /// When the screen capture button is clicked in webview mode, capture is done by the caller
    /// and the resulting image is passed here. This injects the image into ChatGPT (file input
    /// or attach button) so it appears in the chat — same behavior as the reference WebViewStore.
    func sendImageToChatGPT(_ image: NSImage) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            print("❌ Failed to convert image to PNG data")
            return
        }
        let base64String = pngData.base64EncodedString()
        let script = """
        (function() {
            const base64Data = '\(base64String)';
            const byteCharacters = atob(base64Data);
            const byteNumbers = new Array(byteCharacters.length);
            for (let i = 0; i < byteCharacters.length; i++) {
                byteNumbers[i] = byteCharacters.charCodeAt(i);
            }
            const byteArray = new Uint8Array(byteNumbers);
            const blob = new Blob([byteArray], {type: 'image/png'});
            const file = new File([blob], 'screenshot.png', {type: 'image/png'});

            function injectFile(input) {
                const dt = new DataTransfer();
                dt.items.add(file);
                input.files = dt.files;
                input.dispatchEvent(new Event('change', { bubbles: true }));
            }

            // Reuse the cached reference if it's still attached to the DOM.
            if (window.__cachedFileInput && document.contains(window.__cachedFileInput)) {
                injectFile(window.__cachedFileInput);
                console.log('✅ Screenshot uploaded via cached input');
                return true;
            }

            // No valid cache — do a fresh DOM search and store the result.
            const fileInputs = document.querySelectorAll('input[type="file"]');
            if (fileInputs.length > 0) {
                window.__cachedFileInput = fileInputs[0];
                injectFile(window.__cachedFileInput);
                console.log('✅ Screenshot uploaded to ChatGPT');
                return true;
            }

            // File input not yet present — click the attach button and retry once.
            const attachButtons = document.querySelectorAll('button[aria-label*="Attach"], button[data-testid*="attach"], button[title*="Attach"]');
            if (attachButtons.length > 0) {
                attachButtons[0].click();
                console.log('📎 Attach button clicked, waiting for file input...');
                setTimeout(function() {
                    const newFileInputs = document.querySelectorAll('input[type="file"]');
                    if (newFileInputs.length > 0) {
                        window.__cachedFileInput = newFileInputs[newFileInputs.length - 1];
                        injectFile(window.__cachedFileInput);
                        console.log('✅ Screenshot uploaded after clicking attach');
                    }
                }, 500);
                return true;
            }

            console.log('❌ Could not find way to upload image');
            return false;
        })();
        """
        webView?.evaluateJavaScript(script) { result, error in
            if let error = error {
                print("❌ Error uploading image: \(error)")
            } else if let success = result as? Bool, success {
                print("✅ Image uploaded successfully to ChatGPT")
            } else {
                print("⚠️ Image upload result unclear")
            }
        }
    }
}
