//
//  MermaidView.swift
//  musicplayer
//
//  Renders Mermaid diagram code in a WKWebView using Mermaid.js (CDN).
//  Handles streaming: incomplete/invalid code shows as raw <pre> until valid.
//

import SwiftUI
import WebKit

// MARK: - Zoomable diagram block (use this in message bubbles)
// Uses WKWebView's native magnification so zoom is sharp and scrolling works.

struct MermaidDiagramBlockView: View {
    let mermaidCode: String
    
    private static let minZoom: CGFloat = 0.5
    private static let maxZoom: CGFloat = 2.5
    private static let zoomStep: CGFloat = 0.25
    
    @State private var magnification: CGFloat = 1.0
    
    private static let diagramWidth: CGFloat = 900
    private static let diagramHeight: CGFloat = 500
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            zoomToolbar
            MermaidView(
                mermaidCode: mermaidCode.trimmingCharacters(in: .whitespacesAndNewlines),
                magnification: magnification
            )
            .frame(width: Self.diagramWidth, height: Self.diagramHeight)
        }
    }
    
    private var zoomToolbar: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Button(action: zoomOut) {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: DesignSystem.FontSize.sm))
            }
            .buttonStyle(.plain)
            .foregroundColor(DesignSystem.Colors.textSecondary)
            .disabled(magnification <= Self.minZoom)
            
            Button(action: resetZoom) {
                Text("\(Int(magnification * 100))%")
                    .font(.system(size: DesignSystem.FontSize.xs, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            
            Button(action: zoomIn) {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: DesignSystem.FontSize.sm))
            }
            .buttonStyle(.plain)
            .foregroundColor(DesignSystem.Colors.textSecondary)
            .disabled(magnification >= Self.maxZoom)
        }
    }
    
    private func zoomIn() {
        magnification = min(Self.maxZoom, magnification + Self.zoomStep)
    }
    
    private func zoomOut() {
        magnification = max(Self.minZoom, magnification - Self.zoomStep)
    }
    
    private func resetZoom() {
        magnification = 1.0
    }
}

// MARK: - Raw Mermaid WebView (zoom via JS on macOS; WKWebView has no scrollView on AppKit)

struct MermaidView: NSViewRepresentable {
    let mermaidCode: String
    var magnification: CGFloat = 1.0
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // Apply zoom via JavaScript (macOS WKWebView does not expose scrollView)
        let zoomJs = "document.body.style.zoom = \(magnification);"
        webView.evaluateJavaScript(zoomJs, completionHandler: nil)
        
        let trimmed = mermaidCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != context.coordinator.lastLoadedCode else { return }
        context.coordinator.lastLoadedCode = trimmed
        let escaped = Self.htmlEscape(trimmed)
        let zoom = magnification
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <style>
                body { margin: 0; background-color: transparent; }
                #target { display: flex; justify-content: center; align-items: center; min-height: 400px; min-width: 820px; background-color: #ffffff; padding: 16px; border-radius: 8px; }
                #target pre { margin: 0; white-space: pre-wrap; font-family: monospace; font-size: 12px; }
            </style>
        </head>
        <body style="zoom: \(zoom);">
            <div id="src" style="display:none">\(escaped)</div>
            <div id="target"></div>
            <script>
                (function() {
                    var src = document.getElementById('src');
                    var target = document.getElementById('target');
                    var code = (src && src.textContent) ? src.textContent : '';
                    function escapeHtml(s) {
                        return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
                    }
                    function render() {
                        if (!code.trim()) {
                            target.innerHTML = '';
                            return;
                        }
                        target.textContent = code;
                        target.id = 'target';
                        if (typeof mermaid === 'undefined') {
                            target.innerHTML = '<pre>' + escapeHtml(code) + '</pre>';
                            return;
                        }
                        mermaid.run({ nodes: [target] }).catch(function() {
                            target.innerHTML = '<pre>' + escapeHtml(code) + '</pre>';
                        });
                    }
                    if (typeof mermaid !== 'undefined') {
                        mermaid.initialize({ startOnLoad: false, theme: 'default' });
                        render();
                    } else {
                        var s = document.createElement('script');
                        s.src = 'https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js';
                        s.onload = function() {
                            mermaid.initialize({ startOnLoad: false, theme: 'default' });
                            render();
                        };
                        s.onerror = function() {
                            target.innerHTML = '<pre>' + escapeHtml(code) + '</pre>';
                        };
                        document.head.appendChild(s);
                    }
                })();
            </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://cdn.jsdelivr.net"))
    }
    
    final class Coordinator {
        var lastLoadedCode: String = ""
    }
    
    private static func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
