import ApplicationServices
import Testing
@testable import PromptPalette

@Test func electronActivationDoesNotEnableScreenReaderMode() {
    let activation = AccessibilityActivation()
    var calls: [String] = []
    for now in [0.0, 10.0] {
        activation.enable(pid: 1, now: now) { calls.append($0); return .success }
    }
    #expect(calls == ["AXManualAccessibility"])
}

@Test func chromiumFallsBackOnceWhenElectronAttributeIsUnsupported() {
    // Chromium may activate its tree and still return notImplemented from super.
    for fallbackResult in [AXError.success, .notImplemented] {
        let activation = AccessibilityActivation()
        var calls: [String] = []
        for now in [0.0, 1.0, 10.0] {
            activation.enable(pid: 1, now: now) {
                calls.append($0)
                return $0 == "AXManualAccessibility" ? .attributeUnsupported : fallbackResult
            }
        }
        #expect(calls == ["AXManualAccessibility", "AXEnhancedUserInterface"])
    }
}

@Test func unsupportedAppsAreNotProbedContinuously() {
    let activation = AccessibilityActivation()
    var calls = 0
    for now in [0.0, 10.0] {
        activation.enable(pid: 1, now: now) { _ in calls += 1; return .attributeUnsupported }
    }
    #expect(calls == 2)
}

@Test func transientFailureRetriesAfterBackoffAndNewProcessesActivateIndependently() {
    let activation = AccessibilityActivation()
    var attempts = 0
    activation.enable(pid: 1, now: 0) { _ in attempts += 1; return .cannotComplete }
    activation.enable(pid: 1, now: 1) { _ in attempts += 1; return .success }
    #expect(attempts == 1)
    activation.enable(pid: 2, now: 1) { _ in attempts += 1; return .success }
    activation.enable(pid: 1, now: 5) { _ in attempts += 1; return .success }
    activation.enable(pid: 1, now: 10) { _ in attempts += 1; return .success }
    #expect(attempts == 3)
}
