import CreatorMCP
import Foundation

var socketPath = SocketPath.default()
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    if argument == "--socket", let path = arguments.popFirst() {
        socketPath = URL(fileURLWithPath: path)
    }
}
exit(MCPBridge(socketPath: socketPath).run(input: .standardInput, output: .standardOutput))
