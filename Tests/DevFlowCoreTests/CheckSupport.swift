import Foundation

// Explicit dependency-free assertions for Command Line Tools installations without XCTest.
// Every failed assertion is accumulated and causes the executable to exit nonzero.
class CheckCase {
    func setUpWithError() throws {}
    func tearDownWithError() throws {}
}
enum CheckResults {
    static var failures = [String]()
    static func fail(_ message: String, file: StaticString, line: UInt) {
        let detail = "\(file):\(line): \(message)"
        failures.append(detail); print(detail); fflush(stdout)
    }
}
func checkEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { let lhs = try a(), rhs = try b(); if lhs != rhs { CheckResults.fail("Expected equal: \(lhs) / \(rhs). \(message)", file: file, line: line) } }
    catch { CheckResults.fail("Unexpected error: \(error)", file: file, line: line) }
}
func checkNotEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try a() == b() { CheckResults.fail("Expected unequal. \(message)", file: file, line: line) } }
    catch { CheckResults.fail("Unexpected error: \(error)", file: file, line: line) }
}
func checkTrue(_ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try !value() { CheckResults.fail("Expected true. \(message)", file: file, line: line) } }
    catch { CheckResults.fail("Unexpected error: \(error)", file: file, line: line) }
}
func checkFalse(_ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() { CheckResults.fail("Expected false. \(message)", file: file, line: line) } }
    catch { CheckResults.fail("Unexpected error: \(error)", file: file, line: line) }
}
func checkNil<T>(_ value: @autoclosure () throws -> T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() != nil { CheckResults.fail("Expected nil. \(message)", file: file, line: line) } }
    catch { CheckResults.fail("Unexpected error: \(error)", file: file, line: line) }
}
func checkThrows<T>(_ value: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try value(); CheckResults.fail("Expected error. \(message)", file: file, line: line) } catch {}
}
