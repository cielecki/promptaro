import ApplicationServices
import Testing
@testable import PromptPalette

@Test func electronActivationUsesTheDedicatedManualAttribute() {
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

@Test func electronRecoversAfterItsAccessibilityStateIsDisabled() {
    let activation = AccessibilityActivation()
    var enabled = false
    var writes = 0
    var reads = 0
    func check(_ now: TimeInterval) {
        activation.enable(pid: 1, now: now, manualState: {
            reads += 1
            return enabled
        }) { attribute in
            #expect(attribute == "AXManualAccessibility")
            writes += 1
            enabled = true
            return .success
        }
    }
    check(0)
    check(5)
    #expect(writes == 1 && reads == 1)
    enabled = false
    check(6)
    #expect(writes == 1)
    check(10)
    #expect(writes == 2 && enabled)
    check(15)
    #expect(writes == 2 && reads == 3)
}

@Test func unreadableStateDoesNotResetSuccessfulActivation() {
    let activation = AccessibilityActivation()
    var writes = 0
    for now in [0.0, 5.0, 10.0] {
        activation.enable(pid: 1, now: now, manualState: { nil }) { _ in
            writes += 1
            return .success
        }
    }
    #expect(writes == 1)
}

@Test func failedRecoveryIsThrottledAndDoesNotAffectOtherProcesses() {
    let activation = AccessibilityActivation()
    var writes: [pid_t] = []
    func check(_ pid: pid_t, _ now: TimeInterval, _ result: AXError) {
        activation.enable(pid: pid, now: now, manualState: { false }) { _ in
            writes.append(pid)
            return result
        }
    }
    check(1, 0, .success)
    check(1, 5, .cannotComplete)
    check(1, 6, .success)
    check(2, 6, .success)
    check(1, 10, .success)
    #expect(writes == [1, 1, 2, 1])
}

@Test func readableFocusDoesNotResetElectronEvenWhenManualStateReportsFalse() {
    let activation = AccessibilityActivation()
    var reads = 0
    var writes = 0
    for now in [0.0, 5.0, 10.0] {
        activation.enable(pid: 1, now: now, hasFocusedElement: true, manualState: {
            reads += 1
            return false
        }) { _ in writes += 1; return .success }
    }
    #expect(writes == 1 && reads == 0)
    activation.enable(pid: 1, now: 15, hasFocusedElement: false, manualState: { false }) { _ in
        writes += 1
        return .success
    }
    #expect(writes == 2)
}

@Test func failedRecoveryRechecksFocusAndStateBeforeEveryRetry() {
    let activation = AccessibilityActivation()
    var writes = 0
    activation.enable(pid: 1, now: 0) { _ in writes += 1; return .success }
    activation.enable(pid: 1, now: 5, manualState: { false }) { _ in
        writes += 1
        return .cannotComplete
    }
    activation.enable(pid: 1, now: 10, hasFocusedElement: true, manualState: { false }) { _ in
        writes += 1
        return .success
    }
    for (now, state) in [(15.0, Optional(true)), (20.0, nil)] {
        activation.enable(pid: 1, now: now, manualState: { state }) { _ in
            writes += 1
            return .success
        }
    }
    #expect(writes == 2)
    activation.enable(pid: 1, now: 25, manualState: { false }) { _ in
        writes += 1
        return .success
    }
    #expect(writes == 3)
}

@Test func transientFallbackFailureDuringRecoveryCanRetry() {
    let activation = AccessibilityActivation()
    activation.enable(pid: 1, now: 0) { _ in .success }
    var calls: [String] = []
    activation.enable(pid: 1, now: 5, manualState: { false }) {
        calls.append($0)
        return $0 == "AXManualAccessibility" ? .attributeUnsupported : .cannotComplete
    }
    activation.enable(pid: 1, now: 6, manualState: { false }) { _ in
        Issue.record("Fallback retry must respect backoff")
        return .success
    }
    activation.enable(pid: 1, now: 10, manualState: { false }) {
        calls.append($0)
        return $0 == "AXManualAccessibility" ? .attributeUnsupported : .success
    }
    activation.enable(pid: 1, now: 15, manualState: { false }) { _ in
        Issue.record("Successful fallback must not be repeated")
        return .success
    }
    #expect(calls == ["AXManualAccessibility", "AXEnhancedUserInterface",
                      "AXManualAccessibility", "AXEnhancedUserInterface"])
}
