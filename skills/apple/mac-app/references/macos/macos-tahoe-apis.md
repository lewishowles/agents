# macOS Tahoe APIs

<a id="source-macos-macos-tahoe-apis-skill-md"></a>
## Source: `macos/macos-tahoe-apis/SKILL.md`

# macOS Tahoe APIs

You are a macOS 26 (Tahoe) API expert specializing in the latest platform features, Apple Intelligence, and modern development tools.

## When This Skill Activates

- User wants to implement macOS 26 (Tahoe)-specific features
- User asks about Apple Intelligence on macOS or Foundation Models
- User wants to use the MLX framework (M5 chip optimization)
- User asks about Continuity features or cross-device integration
- User asks "what's new in macOS Tahoe" or targets macOS 26

## Your Role

Guide developers in using macOS 26 (Tahoe) specific features and APIs effectively.

## Core Focus Areas

1. **Tahoe Features** - macOS 26 specific features (Spotlight, Control Center, Phone app, etc.)
2. **Apple Intelligence** - Foundation Models, on-device AI, MCP support
3. **MLX Framework** - Machine learning with M5 chip optimization
4. **Continuity** - Cross-device features and integration
5. **Xcode 16** - Modern development tools and optimizations

## Module References

1. **Tahoe Features**: `skills/macos-tahoe-apis/tahoe-features.md`
2. **Apple Intelligence**: `skills/macos-tahoe-apis/apple-intelligence.md`
3. **MLX Framework**: `skills/macos-tahoe-apis/mlx-framework.md`
4. **Continuity**: `skills/macos-tahoe-apis/continuity.md`
5. **Xcode 16**: `skills/macos-tahoe-apis/xcode16.md`

## Review Approach

1. Identify which macOS 26 features are relevant to the project
2. Suggest modern API usage over deprecated approaches
3. Provide code examples with best practices
4. Reference official Apple documentation
5. Consider backwards compatibility when needed

Begin by asking about the project's requirements and target macOS version.

<a id="source-macos-macos-tahoe-apis-apple-intelligence-md"></a>
## Source: `macos/macos-tahoe-apis/apple-intelligence.md`

# Apple Intelligence Integration

Foundation Models, on-device AI, and MCP (Model Context Protocol) support in macOS 26.

## Foundation Models API

```swift
import AppleIntelligence  // Hypothetical framework

// ✅ Text generation
func generateText(prompt: String) async throws -> String {
    let model = try await AIFoundationModel.load(.textGeneration)
    let response = try await model.generate(prompt: prompt)
    return response.text
}

// ✅ Text summarization
func summarize(_ text: String) async throws -> String {
    let model = try await AIFoundationModel.load(.summarization)
    return try await model.summarize(text)
}

// ✅ On-device processing (privacy-preserving)
func analyzeOnDevice(_ data: String) async throws -> Analysis {
    let model = try await AIFoundationModel.load(.analysis)
    model.processingLocation = .onDevice  // Ensures privacy
    return try await model.analyze(data)
}
```

## Model Context Protocol (MCP)

```swift
// ✅ MCP integration for AI context
struct MCPContext {
    let tools: [MCPTool]
    let resources: [MCPResource]
}

protocol MCPTool {
    var name: String { get }
    var description: String { get }
    func execute(parameters: [String: Any]) async throws -> Any
}

// Example MCP tool
struct FileSearchTool: MCPTool {
    let name = "file_search"
    let description = "Search for files in the system"

    func execute(parameters: [String: Any]) async throws -> Any {
        guard let query = parameters["query"] as? String else {
            throw MCPError.invalidParameters
        }
        // Perform file search
        return searchFiles(query: query)
    }

    private func searchFiles(query: String) -> [URL] {
        // Implementation
        return []
    }
}
```

## Privacy-Preserving AI

```swift
// ✅ On-device model inference
func processPrivately(_ input: String) async throws -> Result {
    // All processing happens on-device
    let model = try await LocalAIModel.load()
    return try await model.process(input)
}

// ✅ Check processing location
func verifyPrivacy() async -> Bool {
    let model = try? await AIFoundationModel.load(.textGeneration)
    return model?.processingLocation == .onDevice
}
```

## Resources

- [Apple Intelligence Documentation](https://developer.apple.com/documentation/apple-intelligence)
- [MCP Specification](https://modelcontextprotocol.io/)
- [WWDC 2025: Apple Intelligence](https://developer.apple.com/videos/)

<a id="source-macos-macos-tahoe-apis-continuity-md"></a>
## Source: `macos/macos-tahoe-apis/continuity.md`

# Continuity Features

Cross-device integration between macOS, iOS, and iPadOS.

## Universal Clipboard

```swift
// ✅ Copy to universal clipboard
NSPasteboard.general.clearContents()
NSPasteboard.general.setString(text, forType: .string)
// Automatically syncs to other devices

// ✅ Monitor clipboard changes
NotificationCenter.default.addObserver(
    forName: NSPasteboard.didChangeNotification,
    object: nil,
    queue: .main
) { _ in
    handleClipboardChange()
}
```

## Handoff

```swift
// ✅ Enable Handoff
func setupHandoff() {
    let activity = NSUserActivity(activityType: "com.app.editing")
    activity.title = "Editing Document"
    activity.userInfo = ["documentID": document.id.uuidString]
    activity.isEligibleForHandoff = true
    activity.becomeCurrent()
}

// ✅ Continue activity from another device
func application(
    _ application: NSApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
) -> Bool {
    if userActivity.activityType == "com.app.editing",
       let documentID = userActivity.userInfo?["documentID"] as? String {
        openDocument(id: documentID)
        return true
    }
    return false
}
```

## AirDrop Integration

```swift
import AppKit

// ✅ Share via AirDrop
let sharingService = NSSharingService(named: .sendViaAirDrop)
sharingService?.perform(withItems: [url])

// ✅ Receive AirDrop files
func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
        handleReceivedFile(url)
    }
}
```

## Resources

- [Continuity Documentation](https://developer.apple.com/documentation/foundation/nsuseractivity)

<a id="source-macos-macos-tahoe-apis-mlx-framework-md"></a>
## Source: `macos/macos-tahoe-apis/mlx-framework.md`

# MLX Framework

Apple's machine learning framework with M5 chip neural accelerator support.

## MLX Basics

```swift
import MLX

// ✅ Load and run ML model with MLX
func runMLXModel() async throws {
    let model = try await MLXModel.load(from: modelURL)

    // Leverages M5 neural accelerators automatically
    let input = MLXArray(data: inputData)
    let output = try await model.predict(input)

    print("Prediction: \(output)")
}
```

## Neural Accelerator Access (M5)

```swift
// ✅ Optimize for M5 chip
func configureForM5() {
    MLX.configuration.useNeuralAccelerators = true
    MLX.configuration.preferredDevice = .neuralEngine
}

// ✅ Check hardware capabilities
func checkMLXCapabilities() -> Bool {
    MLX.neuralAcceleratorsAvailable
}
```

## Training on Device

```swift
// ✅ On-device model training
func trainModel() async throws {
    let trainer = MLXTrainer(model: model)
    trainer.configuration.device = .neuralEngine

    for epoch in 0..<numEpochs {
        let loss = try await trainer.train(epoch: epoch, data: trainingData)
        print("Epoch \(epoch): Loss = \(loss)")
    }

    try await trainer.save(to: modelURL)
}
```

## Resources

- [MLX Documentation](https://ml-explore.github.io/mlx/)
- [M5 Neural Engine Guide](https://developer.apple.com/documentation/coreml)

<a id="source-macos-macos-tahoe-apis-tahoe-features-md"></a>
## Source: `macos/macos-tahoe-apis/tahoe-features.md`

# macOS Tahoe Features

New and enhanced features in macOS 26 (Tahoe).

## Redesigned Spotlight Search

### Quick Actions API

```swift
import AppKit

// ✅ Register Spotlight quick actions
extension AppDelegate {
    func registerSpotlightActions() {
        let action = NSUserActivity(activityType: "com.app.createDocument")
        action.title = "Create New Document"
        action.isEligibleForSearch = true
        action.isEligibleForPrediction = true

        // Add to Spotlight
        action.becomeCurrent()
    }
}

// Handle quick action
func application(
    _ application: NSApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
) -> Bool {
    if userActivity.activityType == "com.app.createDocument" {
        createNewDocument()
        return true
    }
    return false
}
```

### Third-Party Spotlight Integration

```swift
import CoreSpotlight

// ✅ Index content for Spotlight
func indexArticle(_ article: Article) {
    let attributeSet = CSSearchableItemAttributeSet(contentType: .content)
    attributeSet.title = article.title
    attributeSet.contentDescription = article.content
    attributeSet.keywords = article.tags
    attributeSet.thumbnailData = article.thumbnail

    let item = CSSearchableItem(
        uniqueIdentifier: article.id.uuidString,
        domainIdentifier: "com.app.articles",
        attributeSet: attributeSet
    )

    CSSearchableIndex.default().indexSearchableItems([item]) { error in
        if let error = error {
            print("Indexing error: \(error)")
        }
    }
}

// ✅ Handle Spotlight selection
func handleSpotlightSelection(_ uniqueIdentifier: String) {
    guard let articleID = UUID(uuidString: uniqueIdentifier) else { return }
    openArticle(id: articleID)
}
```

## Phone App on Mac (Continuity)

### Making Calls from Mac

```swift
// ✅ Tel links automatically open in Phone app
Link("Call Support", destination: URL(string: "tel:1-800-555-0123")!)

// ✅ FaceTime links
Link("FaceTime", destination: URL(string: "facetime:user@example.com")!)

// Check if calling is available
if let url = URL(string: "tel:1-800-555-0123"),
   NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
    // Phone app available
}
```

## Control Center Integration

### Custom Control Center Widgets

```swift
// Note: Control Center customization is system-level
// Apps can provide widgets through WidgetKit

import WidgetKit
import SwiftUI

struct ControlWidget: Widget {
    let kind: String = "ControlWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ControlWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Control")
        .description("Quick access control")
        .supportedFamilies([.systemSmall])
    }
}

struct ControlWidgetView: View {
    let entry: Provider.Entry

    var body: some View {
        VStack {
            Image(systemName: "power")
                .font(.largeTitle)
            Text("Toggle")
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}
```

## Custom Folder Icons and Emblems

### Programmatic Icon Customization

```swift
import AppKit

// ✅ Set custom folder icon
func setCustomFolderIcon(for url: URL, icon: NSImage) {
    NSWorkspace.shared.setIcon(icon, forFile: url.path, options: [])
}

// ✅ Get folder icon
func getFolderIcon(for url: URL) -> NSImage? {
    NSWorkspace.shared.icon(forFile: url.path)
}

// ✅ Support accent color in icons
let icon = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
icon?.isTemplate = true  // Respects accent color
```

## Edge Light for Video Calls

### Detecting Low Light Conditions

```swift
import AVFoundation

// ✅ Monitor camera light conditions
class CameraMonitor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Analyze brightness
        let brightness = calculateBrightness(imageBuffer)

        if brightness < 0.3 {
            // Low light - Edge Light will activate automatically
            print("Low light detected")
        }
    }

    private func calculateBrightness(_ imageBuffer: CVImageBuffer) -> Double {
        // Implementation
        return 0.0
    }
}

// Note: Edge Light is automatic in system video call apps
// Third-party apps can detect conditions but system handles the feature
```

## Thunderbolt 5 Multi-Mac Support

### Detecting Multi-Mac Cluster

```swift
import IOKit

// ✅ Check for Thunderbolt 5 connections
func detectThunderbolt5() -> Bool {
    // Query IOKit for Thunderbolt 5 controllers
    // This is a low-level API check
    return false  // Placeholder
}

// ✅ Distributed computing setup
// Use distributed actor frameworks for multi-Mac processing
```

## Urgent Reminders

### Creating Urgent Reminders

```swift
import EventKit

// ✅ Create urgent reminder
func createUrgentReminder() {
    let eventStore = EKEventStore()

    eventStore.requestAccess(to: .reminder) { granted, error in
        guard granted else { return }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = "Important Task"
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        // Set due date
        let dueDate = Calendar.current.date(byAdding: .hour, value: 2, to: Date())
        reminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: dueDate!
        )

        // Mark as urgent (macOS 26+)
        reminder.priority = 1  // High priority triggers urgent flag

        try? eventStore.save(reminder, commit: true)
    }
}
```

## macOS Tahoe Checklist

- [ ] Integrate with redesigned Spotlight (quick actions, indexing)
- [ ] Support Phone app links (tel:, facetime:)
- [ ] Consider Control Center widgets (WidgetKit)
- [ ] Support custom folder icons and accent colors
- [ ] Detect low light for video features (if applicable)
- [ ] Consider Thunderbolt 5 for distributed computing
- [ ] Use urgent reminders API correctly

## Resources

- [macOS 26 Release Notes](https://developer.apple.com/documentation/macos-release-notes/macos-26-release-notes)
- [Core Spotlight Framework](https://developer.apple.com/documentation/corespotlight)
- [WidgetKit Documentation](https://developer.apple.com/documentation/widgetkit)

<a id="source-macos-macos-tahoe-apis-xcode16-md"></a>
## Source: `macos/macos-tahoe-apis/xcode16.md`

# Xcode 16 Features

Modern development tools and optimizations for macOS 26 development.

## Swift 6 Support

```swift
// ✅ Enable strict concurrency checking
// Build Settings > Swift Compiler > Strict Concurrency Checking: Complete

// ✅ Use Swift 6 language mode
// Build Settings > Swift Language Version: Swift 6
```

## Apple Silicon Optimization

```swift
// ✅ Build for Apple Silicon
// Architecture: arm64 (for M-series chips)

// ✅ Optimize for M5
// Build Settings > Deployment > Architectures: arm64

// Performance improvements automatically applied for M5
```

## Previews and Testing

```swift
import SwiftUI

// ✅ Xcode Previews
#Preview {
    ContentView()
}

// ✅ Multiple preview configurations
#Preview("Light Mode") {
    ContentView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    ContentView()
        .preferredColorScheme(.dark)
}
```

## Debugging Tools

- Instruments improvements for macOS 26
- Memory Graph Debugger enhancements
- Network debugging tools
- SwiftData debugging support

## Resources

- [Xcode 16 Release Notes](https://developer.apple.com/documentation/xcode-release-notes)
- [Swift 6 Migration Guide](https://www.swift.org/migration/)
