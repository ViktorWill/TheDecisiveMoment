import Foundation
import SpotForgeKit

/// The CLI. Everything it does lives in `SpotForgeKit`, which is what the test
/// suite exercises — an executable target cannot be imported by tests.
@main
struct SpotForgeCLI {
    static func main() async {
        do {
            switch try CommandLineInterface.parse(CommandLine.arguments.dropFirst()) {
            case .build(let request):
                request.prepareCacheDirectory()
                let outcome = try await BuildCommand(request: request).run()
                if request.strict, outcome.hasWarnings {
                    fail("a source returned nothing or failed, or the bundle missed its size budget; see the warnings above.", code: 1)
                }
            case .validate(let directory):
                let result = BundleValidator(directory: URL(fileURLWithPath: directory)).validate()
                print(result.summary)
                if !result.isValid { exit(1) }
            }
        } catch let error as ArgumentError {
            if case .helpRequested = error {
                print(CommandLineInterface.usage)
                exit(0)
            }
            fail("\(error.description)\n\n\(CommandLineInterface.usage)", code: 2)
        } catch {
            fail(String(describing: error), code: 1)
        }
    }

    static func fail(_ message: String, code: Int32) -> Never {
        FileHandle.standardError.write(Data("spotforge: \(message)\n".utf8))
        exit(code)
    }
}
