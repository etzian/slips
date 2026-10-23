import Foundation
import SlipsCore
import UIKit

/// PUT uploads through a background `URLSession`, from the file on disk, so they finish while the app
/// is suspended. If the app is gone when one finishes, nobody awaits it: the next drain finds the file
/// with `exists` and records it, so nothing is uploaded twice.
final class BackgroundUploads: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    // @unchecked: `waiting`, `bodies` and `finishEvents` are only touched under `lock`.
    static let shared = BackgroundUploads()
    static let identifier = "com.etzian.slips.uploads"

    private let lock = NSLock()
    private var waiting: [Int: CheckedContinuation<HTTPResponse, any Error>] = [:]
    private var bodies: [Int: Data] = [:]
    private var finishEvents: (() -> Void)?

    private var session: URLSession!

    override private init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    /// Re-attaches to the session at launch so finished tasks are delivered (creating `shared` does it).
    func activate() {}

    func upload(_ request: URLRequest, fromFile file: URL) async throws -> HTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.uploadTask(with: request, fromFile: file)
            lock.withLock { waiting[task.taskIdentifier] = continuation }
            task.resume()
        }
    }

    /// From the app delegate when iOS wakes the app for this session.
    func handleEvents(completion: @escaping () -> Void) {
        lock.withLock { finishEvents = completion }
        activate()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.withLock { bodies[dataTask.taskIdentifier, default: Data()].append(data) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let (continuation, body) = lock.withLock {
            (waiting.removeValue(forKey: task.taskIdentifier), bodies.removeValue(forKey: task.taskIdentifier) ?? Data())
        }
        if let error {
            continuation?.resume(throwing: error)
        } else {
            let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
            continuation?.resume(returning: HTTPResponse(status: status, body: body))
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let finish = lock.withLock { () -> (() -> Void)? in
            defer { finishEvents = nil }
            return finishEvents
        }
        DispatchQueue.main.async { finish?() }
    }
}

/// Foreground requests through `URLSessionTransport`; PUTs through the background session.
struct AppHTTPTransport: HTTPTransport {
    let foreground = URLSessionTransport(session: URLSession(configuration: .ephemeral))

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await foreground.send(request)
    }

    func upload(_ request: HTTPRequest, fromFile file: URL) async throws -> HTTPResponse {
        try await BackgroundUploads.shared.upload(foreground.urlRequest(request), fromFile: file)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundUploads.shared.activate()
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == BackgroundUploads.identifier else { return completionHandler() }
        BackgroundUploads.shared.handleEvents(completion: completionHandler)
    }
}
