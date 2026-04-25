//
//  RunLoopExecutor.swift
//
//  Copyright © 2017-2026 Doug Russell. All rights reserved.
//

import Foundation

@available(macOS 15, iOS 13.0, *)
public final class RunLoopExecutor: SerialExecutor, Sendable {
    fileprivate final class RunLoopThread: Thread {
        init(
            name: String,
            qualityOfService: QualityOfService
        ) {
            super.init()
            self.name = name
            self.qualityOfService = qualityOfService
        }
        override func main() {
            autoreleasepool {
                // Put a source that doesn't do anything on the
                // runloop so it won't return from run
                // until something makes the balancing call to
                // CFRunLoopStop()
                let runLoop = CFRunLoopGetCurrent()
                var context = CFRunLoopSourceContext()
                guard let source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context) else {
                    return
                }
                CFRunLoopAddSource(runLoop, source, .defaultMode)
                CFRunLoopRun()
                CFRunLoopRemoveSource(runLoop, source, .defaultMode)
            }
        }
        @objc func stop() {
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        @objc func enqueueOnRunLoop(_ job: RunLoopExecutor.RunLoopJob) {
            autoreleasepool {
                job.run()
            }
        }
    }
    // Stick UnownedJob inside a reference type for the hop onto the runloop thread.
    fileprivate class RunLoopJob: NSObject {
        private let unownedJob: UnownedJob
        private let unownedExecutor: UnownedSerialExecutor
        init(
            unownedJob: UnownedJob,
            unownedExecutor: UnownedSerialExecutor
        ) {
            self.unownedJob = unownedJob
            self.unownedExecutor = unownedExecutor
        }
        func run() {
            unownedJob.runSynchronously(on: unownedExecutor)
        }
    }
    private nonisolated(unsafe) let thread: RunLoopThread
    public init(
        name: String? = nil,
        qualityOfService: QualityOfService? = nil
    ) {
        thread = .init(
            name: name ?? "RunLoopExecutor",
            qualityOfService: qualityOfService ?? .default
        )
    }
    public func enqueue(_ job: UnownedJob) {
        autoreleasepool {
            thread.perform(
                #selector(RunLoopThread.enqueueOnRunLoop),
                on: thread,
                with: RunLoopJob(
                    unownedJob: job,
                    unownedExecutor: asUnownedSerialExecutor()
                ),
                waitUntilDone: false,
                modes: [RunLoop.Mode.default.rawValue]
            )
        }
    }
    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
    public func start() {
        thread.start()
    }
    public func stop() {
        thread.perform(
            #selector(thread.stop),
            on: thread,
            with: nil,
            waitUntilDone: true,
            modes: [RunLoop.Mode.default.rawValue]
        )
    }
}
