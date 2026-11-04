import Foundation
import AppKit
import Combine
import DevFlowCore

// AppStore uses this only for its optional bundled teaching sample. These checks
// import their own temporary fixture; production AppStore is compiled unchanged.
enum AppResources { static var bundle: Bundle? { nil } }

@MainActor final class ReadGate {
    var calls = 0
    var pending: CheckedContinuation<ProjectRefresh, Never>?
    func read(_ project: Project) async -> ProjectRefresh {
        calls += 1
        return await withCheckedContinuation { pending = $0 }
    }
    func finish(_ project: Project, error: String? = nil) {
        pending?.resume(returning: ProjectRefresh(project: project, primaryError: error))
        pending = nil
    }
}

@main struct RefreshChecks {
    @MainActor static func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<500 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw NSError(domain: "RefreshChecks timed out", code: 1)
    }
    static func require(_ passed: Bool, _ message: String) throws {
        if !passed { throw NSError(domain: message, code: 1) }
    }
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DevFlow-refresh-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let example = URL(fileURLWithPath: "skills/devflow-record/assets/example/devflow-supervision.json")
        var package = try JSONDecoder().decode(ImportPackage.self, from: Data(contentsOf: example))
        let input = root.appendingPathComponent("plan.json")
        try JSONEncoder().encode(package).write(to: input)
        let gate = ReadGate()
        let store = AppStore(workspaceURL: root.appendingPathComponent("workspace.json"), automaticRefresh: false,
                             readProject: { await gate.read($0) })
        defer { store.flushPersistence() }
        await store.importURL(input)
        try await wait { store.supervisionAssessment != nil && !store.isAssessing }
        let snapshot = store.selectedProject!
        let assessment = store.supervisionAssessment!
        var publications = 0
        var cleared = false
        let subscription = store.$supervisionAssessment.dropFirst().sink { value in publications += 1; if value == nil { cleared = true } }
        store.selectRecord(snapshot.records[0].id)
        store.refreshSelected()
        store.refreshSelected()
        try await wait { gate.pending != nil }
        try require(gate.calls == 1 && !store.isImporting, "Refresh must neither overlap nor block import controls")
        try require(store.supervisionAssessment == assessment, "Existing assessment vanished while reading")
        store.saveSupervisionFeedback("unfinished user feedback", targetID: "R-demo")
        store.toggleRefreshPause()
        var refreshed = snapshot; refreshed.refreshedAt = Date()
        gate.finish(refreshed)
        try await wait { store.refreshingProjectID == nil && !store.isAssessing }
        try require(!cleared && publications == 0, "Unchanged assessment must not clear or republish")
        try require(store.selectedRecordID == snapshot.records[0].id && store.isRefreshPaused, "Refresh lost selection or pause")
        try require(store.supervisionFeedbackText(targetID: "R-demo") == "unfinished user feedback", "Refresh overwrote feedback")
        print("PASS repeated refresh preserves assessment, selection, draft and pause; import controls remain available")

        store.refreshSelected()
        try await wait { gate.pending != nil }
        package.name = "Newer explicit import"
        try JSONEncoder().encode(package).write(to: input)
        await store.importURL(input)
        gate.finish(snapshot)
        try await wait { store.refreshingProjectID == nil && !store.isAssessing }
        try require(store.selectedProject?.name == package.name, "Late refresh overwrote a newer explicit import")
        print("PASS newer import wins over an outstanding refresh")

        store.refreshSelected()
        try await wait { gate.pending != nil }
        let ordinary = root.appendingPathComponent("ordinary.json")
        try JSONEncoder().encode(ImportPackage(name: "Ordinary history", records: [])).write(to: ordinary)
        await store.importURL(ordinary)
        gate.finish(snapshot)
        try await wait { store.refreshingProjectID == nil }
        try require(store.selectedProject?.name == "Ordinary history" && store.supervisionAssessment == nil && !store.isAssessing,
                    "Assessment from previous project leaked into ordinary history")
        print("PASS switching projects rejects cross-project assessment")

        store.selectProject(snapshot.id)
        try await wait { store.supervisionAssessment != nil && !store.isAssessing }
        let beforeFailure = store.supervisionAssessment
        store.refreshSelected()
        try await wait { gate.pending != nil }
        gate.finish(store.selectedProject!, error: "Fixture temporarily unavailable")
        try await wait { store.refreshingProjectID == nil && !store.isAssessing }
        try require(store.lastRefreshError == "Fixture temporarily unavailable" && store.supervisionAssessment == beforeFailure,
                    "Failure must preserve content and disclose read error")
        print("PASS read failure retains content with an explicit error")
        // Only an evidence file changes; neither the plan nor imported records do.
        // A no-op refresh still has to invalidate the old pass.
        let code = Data("fixture original source".utf8), log = Data("3 fixture checks passed".utf8)
        try code.write(to: root.appendingPathComponent("feature.py"))
        try code.write(to: root.appendingPathComponent("checks.py"))
        try log.write(to: root.appendingPathComponent("check.log"))
        var plan = package.supervision!
        plan.executions = [VerificationExecution(id: "E-fixture", testCaseID: "T-demo", occurredAt: "2026-01-01T00:00:00Z",
            command: "fixture observation", environment: "isolated test fixture", result: .passed, level: .unit,
            counts: ExecutionCounts(total: 3, passed: 3, failed: 0, skipped: 0),
            sourceFiles: [SourceFileIdentity(path: "feature.py", sha256: ProjectImporter.digest(code)),
                          SourceFileIdentity(path: "checks.py", sha256: ProjectImporter.digest(code))],
            log: SourceReference(path: "check.log", digest: ProjectImporter.digest(log)), exitCode: 0, candidateVersion: plan.version)]
        plan.executions[0].contractDigest = try SupervisionEvaluator.contractDigest(plan: plan, testCaseID: "T-demo")
        package.supervision = plan
        try JSONEncoder().encode(package).write(to: input)
        await store.importURL(input)
        try await wait { !store.isAssessing }
        try require(store.supervisionAssessment?.executions.first?.isValidPass == true, "Fixture must start with an applicable pass: \(String(describing: store.supervisionAssessment?.executions.first))")
        try Data("fixture changed source".utf8).write(to: root.appendingPathComponent("feature.py"))
        let identicalProject = store.selectedProject!
        store.refreshSelected()
        try await wait { gate.pending != nil }
        gate.finish(identicalProject)
        try await wait { store.refreshingProjectID == nil && !store.isAssessing }
        try require(store.supervisionAssessment?.executions.first?.state == .stale,
                    "Unchanged project data must still recheck the referenced source files")
        print("PASS source-only change invalidates a pass even when refreshed project data is identical")
        withExtendedLifetime(subscription) {}
        print("5 AppStore integration checks passed")
    }
}
