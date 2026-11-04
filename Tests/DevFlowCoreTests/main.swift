import Foundation
import DevFlowCore

let cases: [(String, () throws -> Void)] = [
    ("PaginationAndSaveQueue", {
        var seen: [Int] = []
        for page in 0..<129 {
            let window = PageWindow(count: 1281, requestedPage: page)
            checkTrue(window.range.count <= 10)
            seen += Array(window.range)
        }
        checkEqual(seen, Array(0..<1281))
        checkEqual(PageWindow(count: 3, requestedPage: 128).range, 0..<3)
        checkEqual(PageWindow(count: 0, requestedPage: -1).range, 0..<0)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("paging-save-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = WorkspaceStorage(url: root.appendingPathComponent("workspace.json"))
        let writer = WorkspaceSaveQueue(storage: storage)
        var state = WorkspaceState()
        let first = UUID(), last = UUID()
        state.selectedProjectID = first; writer.save(state) { _ in }
        state.selectedProjectID = last; writer.save(state) { _ in }
        writer.flush()
        checkEqual(try storage.load().selectedProjectID, last)
    }),
    ("ImporterTests.testJSONCapacityBoundaryHasActionableWarning", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testJSONCapacityBoundaryHasActionableWarning() }),
    ("ImporterTests.testBundledTeachingSampleHasResolvableSyntheticHistory", { try ImporterTests().testBundledTeachingSampleHasResolvableSyntheticHistory() }),
    ("ProjectSourcesTests.testTwoExplicitSourcesDeduplicateAndPersist", { let suite = ProjectSourcesTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testTwoExplicitSourcesDeduplicateAndPersist() }),
    ("ProjectSourcesTests.testDisabledSourceKeepsHistoryAndResumeReadsNewData", { let suite = ProjectSourcesTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testDisabledSourceKeepsHistoryAndResumeReadsNewData() }),
    ("ProjectSourcesTests.testUnavailableSourceRetainsEvidenceAndPrimaryStillRefreshes", { let suite = ProjectSourcesTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testUnavailableSourceRetainsEvidenceAndPrimaryStillRefreshes() }),
    ("ProjectSourcesTests.testPlanRevisionsArePreservedWithoutDuplicateSnapshots", { let suite = ProjectSourcesTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testPlanRevisionsArePreservedWithoutDuplicateSnapshots() }),
    ("ProjectSourcesTests.testSchemaTwoRoundTripAndLegacyWorkspaceRemainReadable", { let suite = ProjectSourcesTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testSchemaTwoRoundTripAndLegacyWorkspaceRemainReadable() }),
    ("ProjectSourcesTests.testFeedbackCarriesRequirementAndDoesNotClaimDelivery", { let suite = ProjectSourcesTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testFeedbackCarriesRequirementAndDoesNotClaimDelivery() }),
    ("SupervisionTests.testIssueExplainsExactRequiredLayerMismatch", { let suite = SupervisionTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testIssueExplainsExactRequiredLayerMismatch() }),
    ("SupervisionTests.testLatestEvidenceGetsBudgetBeforeHistoricalSnapshots", { let suite = SupervisionTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testLatestEvidenceGetsBudgetBeforeHistoricalSnapshots() }),
    ("SupervisionTests.testLargeLedgerRefreshPersistsCompleteHistory", { let suite = SupervisionTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testLargeLedgerRefreshPersistsCompleteHistory() }),
    ("SupervisionTests.testCompleteEvidenceChainIsSatisfied", { let suite = SupervisionTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testCompleteEvidenceChainIsSatisfied() }),
    ("SupervisionTests.testLowerLayerCannotSatisfyNativeCriterion", { let suite = SupervisionTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testLowerLayerCannotSatisfyNativeCriterion() }),
    ("SupervisionTests.testChangedSourceMakesOldPassStale", { let suite = SupervisionTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testChangedSourceMakesOldPassStale() }),
    ("SupervisionTests.testMissingOrChangedLogDoesNotPass", { let suite = SupervisionTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testMissingOrChangedLogDoesNotPass() }),
    ("SupervisionTests.testLatestFailureWinsAndHistoryRemains", { let suite = SupervisionTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testLatestFailureWinsAndHistoryRemains() }),
    ("SupervisionTests.testDeclaredClosureRequiresFixAndValidRetest", { let suite = SupervisionTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testDeclaredClosureRequiresFixAndValidRetest() }),
    ("SupervisionTests.testInvalidGraphAndDuplicateIDsRejected", { let suite = SupervisionTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testInvalidGraphAndDuplicateIDsRejected() }),
    ("SupervisionTests.testUnsafeAndSymlinkPathsRejected", { let suite = SupervisionTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testUnsafeAndSymlinkPathsRejected() }),
    ("SupervisionTests.testUnknownCountsAreNotZero", { let suite = SupervisionTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testUnknownCountsAreNotZero() }),
    ("SupervisionTests.testMissingRecordsAndBlockedTasksRemainVisible", { let suite = SupervisionTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testMissingRecordsAndBlockedTasksRemainVisible() }),
    ("SessionImporterTests.testPublicMessagesAndInternalContentAreSeparated", { let suite = SessionImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testPublicMessagesAndInternalContentAreSeparated() }),
    ("SessionImporterTests.testToolCallsOutputsStayStableAcrossAppendAndOutOfOrder", { let suite = SessionImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testToolCallsOutputsStayStableAcrossAppendAndOutOfOrder() }),
    ("SessionImporterTests.testCallsWithoutResultsDoNotClaimCompletion", { let suite = SessionImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testCallsWithoutResultsDoNotClaimCompletion() }),
    ("SessionImporterTests.testDuplicateIdentityConflictsRetainBothResults", { let suite = SessionImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testDuplicateIdentityConflictsRetainBothResults() }),
    ("SessionImporterTests.testStructuredInnerActionsAndMirrorsAreNotDoubleCounted", { let suite = SessionImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testStructuredInnerActionsAndMirrorsAreNotDoubleCounted() }),
    ("SessionImporterTests.testPartialUnknownAndInvalidLinesHaveCoverage", { let suite = SessionImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testPartialUnknownAndInvalidLinesHaveCoverage() }),
    ("SessionImporterTests.testSensitiveFieldsBinaryAndHomePathsAreRedacted", { let suite = SessionImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testSensitiveFieldsBinaryAndHomePathsAreRedacted() }),
    ("SessionImporterTests.testRequestContextDoesNotCrossTurns", { let suite = SessionImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testRequestContextDoesNotCrossTurns() }),
    ("SessionImporterTests.testByteAndEventLimitsReportIncompleteCoverage", { let suite = SessionImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testByteAndEventLimitsReportIncompleteCoverage() }),
    ("SessionImporterTests.testSymlinkAndNonRegularInputsRejected", { let suite = SessionImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testSymlinkAndNonRegularInputsRejected() }),
    ("ImporterTests.testRequirementIDsStayRecordedWithoutExplicitStatusColumns", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testRequirementIDsStayRecordedWithoutExplicitStatusColumns() }),
    ("ImporterTests.testCommandOpenIsNotAnOpenFinding", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testCommandOpenIsNotAnOpenFinding() }),
    ("ImporterTests.testNestedAcceptanceHeadingsRetainTestKindWithoutInheritingDates", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testNestedAcceptanceHeadingsRetainTestKindWithoutInheritingDates() }),
    ("ImporterTests.testExplicitLocalAcceptanceStatusDoesNotPromotePlannedProse", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testExplicitLocalAcceptanceStatusDoesNotPromotePlannedProse() }),
    ("WorkspaceTests.testFeedbackIncludesLimitsAndRelatedEvidence", { let suite = WorkspaceTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; suite.testFeedbackIncludesLimitsAndRelatedEvidence() }),
    ("ImporterTests.testChineseIdentifiersRemainStableWhenAnEarlierItemIsInserted", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testChineseIdentifiersRemainStableWhenAnEarlierItemIsInserted() }),
    ("ImporterTests.testJSONRetainsHistoryRelationsAndDeclaredOrigin", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testJSONRetainsHistoryRelationsAndDeclaredOrigin() }),
    ("ImporterTests.testMalformedJSONAndUnsupportedSchemaAreRejected", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testMalformedJSONAndUnsupportedSchemaAreRejected() }),
    ("ImporterTests.testDuplicateIDsDanglingAndSelfRelationsAreRejected", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testDuplicateIDsDanglingAndSelfRelationsAreRejected() }),
    ("ImporterTests.testJSONTraversalAbsoluteAndSensitiveReferencesAreRejected", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testJSONTraversalAbsoluteAndSensitiveReferencesAreRejected() }),
    ("ImporterTests.testResolveRejectsFileAndDirectorySymlinksIncludingInsideRoot", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testResolveRejectsFileAndDirectorySymlinksIncludingInsideRoot() }),
    ("ImporterTests.testMissingSourcePreservesRecordWithExplicitWarning", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testMissingSourcePreservesRecordWithExplicitWarning() }),
    ("ImporterTests.testExecutableAndWebSourceTypesCannotBeOpened", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testExecutableAndWebSourceTypesCannotBeOpened() }),
    ("ImporterTests.testDateNeverComesFromFilenameDirectoryOrModificationTime", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testDateNeverComesFromFilenameDirectoryOrModificationTime() }),
    ("ImporterTests.testExplicitBodyDatesAreRetainedAndAmbiguityIsNotInvented", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testExplicitBodyDatesAreRetainedAndAmbiguityIsNotInvented() }),
    ("ImporterTests.testChineseNotPassedAndUnknownAreNotMisclassified", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testChineseNotPassedAndUnknownAreNotMisclassified() }),
    ("ImporterTests.testExpectationsAndMixedScopesDoNotBecomeBroadSuccess", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testExpectationsAndMixedScopesDoNotBecomeBroadSuccess() }),
    ("ImporterTests.testStableIDsExactSourceLineAndChangedDigest", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testStableIDsExactSourceLineAndChangedDigest() }),
    ("ImporterTests.testSeparateFailureAndSuccessEntriesRemainSeparate", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testSeparateFailureAndSuccessEntriesRemainSeparate() }),
    ("ImporterTests.testJSONChangedSourceWarnsWithoutReplacingHistoricalClaim", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testJSONChangedSourceWarnsWithoutReplacingHistoricalClaim() }),
    ("ImporterTests.testDirectorySkipsEvidenceSecretsDependenciesAndCodeFences", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testDirectorySkipsEvidenceSecretsDependenciesAndCodeFences() }),
    ("ImporterTests.testOversizeDocumentAndFileCountHaveVisibleWarnings", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testOversizeDocumentAndFileCountHaveVisibleWarnings() }),
    ("ImporterTests.testInvalidDatesLinesAndDigestsAreRejectedInJSON", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testInvalidDatesLinesAndDigestsAreRejectedInJSON() }),
    ("ImporterTests.testAttachedSourceRootRevalidatesDigest", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testAttachedSourceRootRevalidatesDigest() }),
    ("ImporterTests.testSHA256UsesFileBytes", { let suite = ImporterTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; suite.testSHA256UsesFileBytes() }),
    ("WorkspaceTests.testWorkspaceRoundTripIncludesFeedback", { let suite = WorkspaceTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testWorkspaceRoundTripIncludesFeedback() }),
    ("WorkspaceTests.testCorruptWorkspaceIsNeverOverwritten", { let suite = WorkspaceTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testCorruptWorkspaceIsNeverOverwritten() }),
    ("WorkspaceTests.testNewFailurePreservesOldSuccessWithoutReplacingIt", { let suite = WorkspaceTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; suite.testNewFailurePreservesOldSuccessWithoutReplacingIt() }),
    ("WorkspaceTests.testDisappearedFailureRemainsVisible", { let suite = WorkspaceTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; suite.testDisappearedFailureRemainsVisible() }),
    ("WorkspaceTests.testFeedbackDoesNotClaimSentOrFixed", { let suite = WorkspaceTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; suite.testFeedbackDoesNotClaimSentOrFixed() }),
    ("WorkspaceTests.testEvidenceOnlyCorrectionPreservesPreviousClaim", { let suite = WorkspaceTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; suite.testEvidenceOnlyCorrectionPreservesPreviousClaim() })
]
let filter = CommandLine.arguments.firstIndex(of: "--filter").flatMap { CommandLine.arguments.indices.contains($0 + 1) ? CommandLine.arguments[$0 + 1] : nil }
let selectedCases = cases.filter { filter == nil || $0.0.contains(filter!) }
if selectedCases.isEmpty { print("No matching checks; refusing empty success"); exit(2) }
var passed = 0
for (name, run) in selectedCases {
    print("RUN \(name)"); fflush(stdout)
    let before = CheckResults.failures.count
    do { try run() } catch { CheckResults.failures.append("\(name): unexpected error: \(error)") }
    if CheckResults.failures.count == before { passed += 1; print("PASS \(name)") }
    else { print("FAIL \(name)") }
}
if CommandLine.arguments.contains("--verify-failure-exit") { checkTrue(false, "deliberate runner failure control") }
for failure in CheckResults.failures { print(failure) }
print("Checks: \(passed)/\(selectedCases.count) passed; assertion errors: \(CheckResults.failures.count)")
exit(CheckResults.failures.isEmpty ? 0 : 1)
