//
//  ScreenshotService.swift
//  musicplayer
//
//  Screenshot capture service for analyzing screen content.
//
//  Screen Recording permission: If the app keeps asking for permission after restart,
//  ensure the app is signed with a Development team (not "Sign to Run Locally") in
//  Xcode → Signing & Capabilities, so macOS recognizes the app across builds.
//

import Foundation
import Combine
import AppKit
import ScreenCaptureKit

@MainActor
final class ScreenshotService: ObservableObject {
    @Published var capturedScreenshots: [ScreenshotData] = []
    @Published var isCapturing: Bool = false
    
    /// Capture a screenshot of the entire screen.
    /// Uses ScreenCaptureKit directly first; only falls back to CGPreflightScreenCaptureAccess()
    /// when content is empty, because the preflight check is known to return false even after
    /// permission is granted (e.g. after restart or with development builds).
    func captureScreenshot() async throws {
        isCapturing = true
        defer { isCapturing = false }
        
        // Try ScreenCaptureKit first — don't rely on CGPreflightScreenCaptureAccess() for success,
        // but only open System Settings when preflight says no permission (avoids opening Settings
        // when permission is already granted but API failed or returned empty).
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
            }
            throw ScreenshotError.permissionDenied
        }
        
        guard let display = content.displays.first else {
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
                throw ScreenshotError.permissionDenied
            }
            throw ScreenshotError.noDisplayFound
        }
        
        // Create filter for the display
        let filter = SCContentFilter(display: display, excludingWindows: [])
        
        // Configure screenshot
        let config = SCStreamConfiguration()
        config.width = Int(display.width)
        config.height = Int(display.height)
        config.capturesAudio = false
        config.showsCursor = true
        
        // Capture the screenshot
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        
        // Convert CGImage to PNG data
        guard let pngData = convertCGImageToPNG(image) else {
            throw ScreenshotError.conversionFailed
        }
        
        // Create screenshot data
        let screenshot = ScreenshotData(
            id: UUID(),
            imageData: pngData,
            timestamp: Date()
        )
        
        capturedScreenshots.append(screenshot)
    }
    
    /// Remove a screenshot from the collection
    func removeScreenshot(_ screenshot: ScreenshotData) {
        capturedScreenshots.removeAll { $0.id == screenshot.id }
    }
    
    /// Clear all screenshots
    func clearAllScreenshots() {
        capturedScreenshots.removeAll()
    }
    
    /// Convert CGImage to PNG Data
    private func convertCGImageToPNG(_ cgImage: CGImage) -> Data? {
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmapImage.representation(using: .png, properties: [:])
    }
}

// MARK: - Models

struct ScreenshotData: Identifiable, Equatable {
    let id: UUID
    let imageData: Data
    let timestamp: Date
}

// MARK: - Errors

enum ScreenshotError: Error, LocalizedError {
    case permissionDenied
    case noDisplayFound
    case conversionFailed
    case captureFailed
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen recording permission is required to capture screenshots"
        case .noDisplayFound:
            return "No display found for screenshot capture"
        case .conversionFailed:
            return "Failed to convert screenshot to image data"
        case .captureFailed:
            return "Failed to capture screenshot"
        }
    }
}
