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
        let script = "typeof sendToChatGPT === 'function' && sendToChatGPT(\(escaped));"
        webView?.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("❌ Error sending message to ChatGPT: \(error)")
            }
        }
    }

    func getChatGPTResponse(completion: @escaping (String) -> Void) {
        let script = "typeof getChatGPTResponse === 'function' ? getChatGPTResponse() : '';"
        webView?.evaluateJavaScript(script) { result, _ in
            DispatchQueue.main.async {
                completion((result as? String) ?? "")
            }
        }
    }

    func inspectDOM() {
        let script = "typeof inspectChatGPTDOM === 'function' && inspectChatGPTDOM();"
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
        let script = "typeof duckAudio === 'function' && duckAudio(0.1);"
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    func restoreAudio() {
        let script = "typeof restoreAudio === 'function' && restoreAudio();"
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Clicks the "Stop streaming" button in ChatGPT (same as aria-label="Stop streaming"). Use when Shift is pressed in webview.
    func stopStreamingInWebView() {
        let script = """
        (function() {
            var stopSelectors = [
                'button[aria-label="Stop streaming"]',
                'button[aria-label="Stop generating"]',
                '[data-testid="stop-generating"]',
                'button:has(svg[data-icon="stop"])'
            ];
            for (var i = 0; i < stopSelectors.length; i++) {
                try {
                    var btn = document.querySelector(stopSelectors[i]);
                    if (btn && btn.offsetParent !== null && !btn.disabled) {
                        btn.click();
                        return true;
                    }
                } catch (e) {}
            }
            return false;
        })();
        """
        webView?.evaluateJavaScript(script) { _, _ in }
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
            const fileInputs = document.querySelectorAll('input[type="file"]');
            if (fileInputs.length > 0) {
                const fileInput = fileInputs[0];
                const dataTransfer = new DataTransfer();
                dataTransfer.items.add(file);
                fileInput.files = dataTransfer.files;
                fileInput.dispatchEvent(new Event('change', { bubbles: true }));
                console.log('✅ Screenshot uploaded to ChatGPT');
                return true;
            }
            const attachButtons = document.querySelectorAll('button[aria-label*="Attach"], button[data-testid*="attach"], button[title*="Attach"]');
            if (attachButtons.length > 0) {
                attachButtons[0].click();
                console.log('📎 Attach button clicked, waiting for file input...');
                setTimeout(function() {
                    const newFileInputs = document.querySelectorAll('input[type="file"]');
                    if (newFileInputs.length > 0) {
                        const fileInput = newFileInputs[newFileInputs.length - 1];
                        const dataTransfer = new DataTransfer();
                        dataTransfer.items.add(file);
                        fileInput.files = dataTransfer.files;
                        fileInput.dispatchEvent(new Event('change', { bubbles: true }));
                        console.log('✅ Screenshot uploaded after clicking attach');
                        return true;
                    }
                }, 500);
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
