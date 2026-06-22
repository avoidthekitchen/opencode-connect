import Foundation
import Testing
@testable import OpenCodeConnectCore

@Test("a command that exceeds its deadline is terminated")
func commandTimeoutIsBounded() async {
    let runner = ProcessCommandRunner()
    let started = ContinuousClock.now

    let result = await runner.run(CommandRequest(
        executablePath: "/bin/sh",
        arguments: ["-c", "sleep 2"],
        timeout: .milliseconds(100)
    ))

    #expect(result.timedOut)
    #expect(started.duration(to: .now) < .seconds(1))
}

@Test("a verbose command is drained while running without deadlocking")
func verboseCommandDoesNotDeadlock() async {
    let runner = ProcessCommandRunner()

    let result = await runner.run(CommandRequest(
        executablePath: "/bin/sh",
        arguments: ["-c", "head -c 1048576 /dev/zero"],
        timeout: .seconds(2)
    ))

    #expect(!result.timedOut)
    #expect(result.exitCode == 0)
    #expect(result.standardOutput.utf8.count == 64 * 1024)
}

@Test("simultaneous verbose stdout and stderr are both drained without deadlocking")
func verboseOutputStreamsDoNotDeadlock() async {
    let runner = ProcessCommandRunner()

    let result = await runner.run(CommandRequest(
        executablePath: "/bin/sh",
        arguments: ["-c", "head -c 1048576 /dev/zero & head -c 1048576 /dev/zero >&2 & wait"],
        timeout: .seconds(2)
    ))

    #expect(!result.timedOut)
    #expect(result.exitCode == 0)
    #expect(result.standardOutput.utf8.count == 64 * 1024)
    #expect(result.standardError.utf8.count == 64 * 1024)
}
