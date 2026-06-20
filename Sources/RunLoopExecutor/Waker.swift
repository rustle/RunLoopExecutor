//
//  Waker.swift
//
//  Copyright © 2026 Doug Russell. All rights reserved.
//

import Darwin
import Foundation
import Synchronization

/// Wakes the run loop by signaling a version-0 `CFRunLoopSource`.
///
/// The loop owns the source. `wake()` signals/wakes the source.
@available(macOS 15, iOS 18, *)
final class Waker: Sendable {
    enum Event {
        case threadID(UInt64)
        case wake
        case didStop
    }

    /// Carries the drain callback to the C source-0 `perform` callback, which only
    /// gets an opaque `info` pointer. Handed to the source context as a retained
    /// `Unmanaged` and released by the context's `release` callback on teardown.
    private final class Doorbell {
        let onWake: () -> Void
        init(_ onWake: @escaping () -> Void) {
            self.onWake = onWake
        }
    }

    /// The run loop and its doorbell source, published by the run-loop thread once
    /// the source is installed and cleared when the loop tears down. `wake()` reads
    /// it to know where to signal; `nil` means "not yet started, or already stopped,"
    /// in which case a wake is a no-op. The executor's phase gating guarantees no
    /// legitimate wake lands in that window.
    // `@unchecked Sendable`: these CF refs are touched on the run-loop thread and,
    // via `wake()`, from arbitrary enqueue threads. That is sound because the only
    // cross-thread operations are `CFRunLoopSourceSignal` and `CFRunLoopWakeUp`,
    // both documented safe to call from any thread.
    private struct Installed: @unchecked Sendable {
        let runLoop: CFRunLoop
        let source: CFRunLoopSource
    }

    private let name: String
    private let qualityOfService: QualityOfService
    /// Read by the `sourceIsValid` test hook to assert teardown.
    private let installed = Mutex<Installed?>(nil)

    init(
        name: String,
        qualityOfService: QualityOfService
    ) {
        self.name = name
        self.qualityOfService = qualityOfService
    }

    /// Spawns the run-loop thread and blocks until its doorbell source is installed.
    ///
    /// The synchronous handshake is what allows `wake()` to stay simple. By the time
    /// `start()` returns, `installed` is populated, so the first enqueue's wake
    /// always finds a live source.
    func start(_ eventHandler: @escaping @Sendable (Event) -> Void) {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            runLoop(eventHandler, ready: ready)
        }
        thread.name = name
        thread.qualityOfService = qualityOfService
        thread.start()
        ready.wait()
    }

    /// Signals/wakes the run loop
    func wake() {
        installed.withLock { installed in
            guard let installed else { return }
            // `CFRunLoopSourceSignal` & `CFRunLoopWakeUp`` calls are documented safe from any thread.
            // In practice the executor's `signaled` coalescing flag means at most one `wake()` is in flight between drains, so the `installed` lock is effectively uncontended.
            CFRunLoopSourceSignal(installed.source)
            CFRunLoopWakeUp(installed.runLoop)
        }
    }

    // MARK: Run-loop thread

    private static let perform: @convention(c) (UnsafeMutableRawPointer?) -> Void = { info in
        guard let info else { return }
        Unmanaged<Doorbell>.fromOpaque(info).takeUnretainedValue().onWake()
    }

    private func runLoop(
        _ eventHandler: @escaping (Event) -> Void,
        ready: DispatchSemaphore
    ) {
        var threadID: UInt64 = 0
        if pthread_threadid_np(nil, &threadID) == 0 {
            eventHandler(.threadID(threadID))
        }

        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()!
            let doorbell = Doorbell {
                eventHandler(.wake)
            }
            // Hand the doorbell to the source as a retained reference.
            // The context `release` callback balances it when the source is deallocated.
            let info = Unmanaged.passRetained(doorbell)
            var context = CFRunLoopSourceContext(
                version: 0,
                info: info.toOpaque(),
                retain: nil,
                release: { pointer in
                    guard let pointer else { return }
                    Unmanaged<Doorbell>.fromOpaque(pointer).release()
                },
                copyDescription: nil,
                equal: nil,
                hash: nil,
                schedule: nil,
                cancel: nil,
                perform: Self.perform
            )
            guard let source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context) else {
                // No source installed, so the release callback won't fire — balance
                // the passRetained by hand, then unblock start() (wake() no-ops with
                // `installed` left nil, and the loop below is never entered).
                info.release()
                ready.signal()
                return
            }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            installed.withLock {
                $0 = Installed(
                    runLoop: runLoop,
                    source: source
                )
            }
            ready.signal()

            CFRunLoopRun()

            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFRunLoopSourceInvalidate(source)
            installed.withLock { $0 = nil }
            // `source` is now the last reference.
            // ARC dropping it at scope end deallocates it, firing the context `release` that frees the doorbell.
        }

        eventHandler(.didStop)
    }

    // MARK: Test hooks

    /// `internal` so the test suite can assert the doorbell source is live while the executor runs and invalidated afterward. There is no task-global named resource for source-0, so source validity is the teardown invariant worth asserting.
    var sourceIsValid: Bool {
        installed.withLock { installed in
            guard let installed else { return false }
            return CFRunLoopSourceIsValid(installed.source)
        }
    }
}
