import ApexGaugeCore
import BackgroundTasks
import Foundation

enum RefreshScheduler {
    static let identifier = ApexGaugeDefaults.backgroundRefreshTaskIdentifier

    @discardableResult
    static func register(handler: @escaping @Sendable () async -> Void) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            let completion = CompletionGate()
            let taskBox = RefreshTaskBox(refreshTask)
            let operation = Task {
                await handler()
                completion.finish(taskBox.task, success: !Task.isCancelled)
            }

            taskBox.task.expirationHandler = {
                operation.cancel()
                completion.finish(taskBox.task, success: false)
            }
        }
    }

    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(
            timeIntervalSinceNow: ApexGaugeDefaults.backgroundRefreshInterval
        )

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            NSLog("Unable to schedule ApexGauge background refresh: %@", error.localizedDescription)
        }
    }

    /// BGTask is not Sendable, but the system owns its lifetime and permits
    /// completion from the asynchronous operation launched for its handler.
    private final class RefreshTaskBox: @unchecked Sendable {
        let task: BGAppRefreshTask

        init(_ task: BGAppRefreshTask) {
            self.task = task
        }
    }

    private final class CompletionGate: @unchecked Sendable {
        private let lock = NSLock()
        private var isFinished = false

        func finish(_ task: BGAppRefreshTask, success: Bool) {
            lock.lock()
            guard !isFinished else {
                lock.unlock()
                return
            }
            isFinished = true
            lock.unlock()

            RefreshScheduler.scheduleNext()
            task.setTaskCompleted(success: success)
        }
    }
}
