import Foundation

public struct ProcessResult {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
}

public protocol ProcessRunner {
    func run(_ launchPath: String, _ args: [String]) throws -> ProcessResult
}

public struct RealProcessRunner: ProcessRunner {
    public init() {}
    public func run(_ launchPath: String, _ args: [String]) throws -> ProcessResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        try p.run()
        // Drain both pipes concurrently before waitUntilExit to avoid a two-pipe deadlock
        // (child blocking on a full stderr buffer while parent blocks reading stdout).
        var errData = Data()
        let drain = DispatchQueue(label: "keymapper.stderr-drain")
        drain.async { errData = errPipe.fileHandleForReading.readDataToEndOfFile() }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        drain.sync {}   // ensure the stderr read has completed
        p.waitUntilExit()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        return ProcessResult(stdout: out, stderr: err, exitCode: p.terminationStatus)
    }
}
