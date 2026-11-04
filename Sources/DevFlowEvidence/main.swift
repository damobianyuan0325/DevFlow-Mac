import Foundation
import DevFlowCore

// Read-only bridge for skill-produced evidence. No command from an import is executed.
let args = CommandLine.arguments
func fail(_ message: String) -> Never { FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1) }
guard (args.count == 3 && ["contracts", "inspect"].contains(args[1])) ||
      (args.count == 4 && args[1] == "inspect-execution") else {
    fail("Usage: DevFlowEvidence contracts|inspect /path/to/devflow-supervision.json\n       DevFlowEvidence inspect-execution /path/to/devflow-supervision.json EXECUTION_ID")
}
do {
    let result = try ProjectImporter.load(url: URL(fileURLWithPath: args[2]))
    guard let plan = result.supervision else { fail("The selected package has no supervision plan.") }
    let object: [String: Any]
    if args[1] == "contracts" {
        object = try Dictionary(uniqueKeysWithValues: plan.testCases.map { ($0.id, try SupervisionEvaluator.contractDigest(plan: plan, testCaseID: $0.id)) })
    } else if args[1] == "inspect-execution" {
        let execution = try SupervisionEvaluator.inspectExecution(plan: plan, root: result.sourceRoot, records: result.records, executionID: args[3])
        object = ["project": result.name, "scope": "singleExecution", "planVersion": plan.version,
                  "execution": ["id": execution.id, "state": execution.state.rawValue, "validPass": execution.isValidPass, "reasons": execution.reasons],
                  "warnings": result.warnings,
                  "limitations": ["仅核验该执行相对所选计划与当前来源的证据；不代表最新执行、需求验收或问题已关闭。", "历史源码或合同已变化时保留过期状态；不得重写旧摘要来消除过期。"]]
    } else {
        let assessment = SupervisionEvaluator.evaluate(plan: plan, root: result.sourceRoot, records: result.records)
        func rows(_ items: [SupervisionItemAssessment]) -> [[String: Any]] { items.map { ["id":$0.id,"state":$0.state.rawValue,"reasons":$0.reasons,"evidenceIDs":$0.evidenceIDs] } }
        object = ["project":result.name,"records":result.records.count,"requirements":rows(assessment.requirements),"criteria":rows(assessment.criteria),"artifacts":rows(assessment.artifacts),"executions":assessment.executions.map { ["id":$0.id,"state":$0.state.rawValue,"validPass":$0.isValidPass,"reasons":$0.reasons] as [String:Any] },"issues":assessment.issues.map { ["id":$0.id,"state":$0.state.rawValue,"reasons":$0.reasons] as [String:Any] },"briefing":assessment.briefing,"validationErrors":assessment.validationErrors,"warnings":result.warnings]
    }
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
} catch { fail(error.localizedDescription) }
