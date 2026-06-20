//
//  RunLoopExecutor.swift
//
//  Copyright © 2017-2026 Doug Russell. All rights reserved.
//

import Foundation
import Synchronization

/// A `SerialExecutor` that runs jobs on a dedicated `Thread`, woken whenever jobs are enqueued.
///
/// Supported lifecycles for a ``RunLoopExecutor``:
///
/// 1. `unstarted` -> ``start()`` -> `running` -> ``stop()`` -> `terminating`
///     - `start()` must be called exactly once before any job is enqueued.
///     - `stop()` must be called exactly once, from a thread other than the executor's own, and drains already-enqueued jobs before returning.
///     - Enqueuing after `stop()` is a **programmer error and traps**. Once the run loop has stopped there is no venue to run a job, and silently dropping it would suspend the awaiting task forever. Callers must quiesce every actor on this executor before calling `stop()`.
/// 2. `unstarted -> terminating`
///
/// ---
///
/// Enqueued jobs are coalesced by accumulating them with at most one wake ever in flight, regardless of enqueue rate. The wake drains all accumulated jobs.
@available(macOS 15, iOS 18, *)
public final class RunLoopExecutor: SerialExecutor, Sendable {
    private enum Phase {
        case unstarted
        case running
        case terminating
    }

    private struct State {
        var phase: Phase = .unstarted
        /// Pending jobs, drained FIFO on the run-loop thread.
        var jobs: [UnownedJob] = []
        /// True while a wake is in flight. Coalescing so at most one wake is ever enqueued regardless of enqueue rate.
        var signaled = false
        /// `pthread_threadid_np` of the run-loop thread, used to reject self-stop.
        var threadID: UInt64 = 0
    }

    /// Above this many pending jobs, a drain releases the queue's backing
    /// buffer instead of retaining it, so a one-time burst doesn't pin
    /// capacity for the executor's lifetime. At or below it, the buffer is
    /// kept for steady-state reuse.
    private static let drainCapacityLimit = 1024

    private let state = Mutex(State())
    private nonisolated(unsafe) let thread: RunLoopThread
    private let didStopSignal = DispatchSemaphore(value: 0)

    public init(
        name: String? = nil,
        qualityOfService: QualityOfService? = nil
    ) {
        thread = .init(
            name: name ?? "RunLoopExecutor",
            qualityOfService: qualityOfService ?? .default
        )
        thread.eventHandler = { [unowned self] event in
            switch event {
            case let .threadID(threadID):
                self.state.withLock { $0.threadID = threadID }
            case .wake:
                self.drainJobs()
            case .didStop:
                self.didStopSignal.signal()
            }
        }
    }

    deinit {
        state.withLock { state in
            if state.phase == .unstarted {
                state.phase = .terminating
            } else {
                precondition(state.phase == .terminating, "RunLoopExecutor should never deinit while running.")
            }
        }
    }

    /// Spawns the run-loop thread.
    /// 
    /// - Must be called exactly once, before any job is enqueued on this executor.
    /// - Must be balanced with matching call to ``stop()``
    public func start() {
        state.withLock { state in
            precondition(state.phase == .unstarted, "start() called more than once")
            state.phase = .running
        }
        thread.start()
    }

    /// Stops the run-loop thread after draining already-enqueued jobs, then returns.
    ///
    /// - Must be called exactly once.
    /// - Must never be called from the executor's own thread (deadlock).
    /// - Must never be called without first calling ``start()``.
    public func stop() {
        var current: UInt64 = 0
        pthread_threadid_np(nil, &current)
        let needsWake = state.withLock { state -> Bool in
            switch state.phase {
            case .unstarted:
                preconditionFailure("stop() called before start()")
            case .terminating:
                preconditionFailure("stop() called more than once")
            case .running:
                precondition(
                    state.threadID != current,
                    "stop() must not be called from the executor's own thread"
                )
                state.phase = .terminating
                // Ensure exactly one wake reaches the loop so a drain observes
                // `terminating` and stops it. If a wake is already in flight, that
                // drain will see the flag we just set — no second wake needed.
                if state.signaled { return false }
                state.signaled = true
                return true
            }
        }
        if needsWake {
            wake()
        }
        didStopSignal.wait()
    }

    // MARK: SerialExecutor

    public func enqueue(_ job: UnownedJob) {
        let needsWake = state.withLock { state -> Bool in
            switch state.phase {
            case .unstarted:
                preconditionFailure("job enqueued before start()")
            case .terminating:
                // The run loop is gone (or going) — there is no venue to run
                // this job, and silently dropping it would suspend the awaiting
                // task forever. Enqueuing after stop() is a caller error:
                // quiesce every actor on this executor before stopping.
                preconditionFailure("job enqueued after stop()")
            case .running:
                state.jobs.append(job)
                if state.signaled { // a wake is already in flight
                    return false
                }
                state.signaled = true
                return true
            }
        }
        if needsWake {
            wake()
        }
    }

    private func wake() {
        thread.perform(
            #selector(RunLoopThread.wake),
            on: thread,
            with: nil,
            waitUntilDone: false,
            modes: [RunLoop.Mode.default.rawValue]
        )
    }

    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }

    // MARK: Drain

    /// Drains and runs all pending jobs, then stops the loop if terminating.
    ///
    /// Runs on the run loop thread. Re-arms `signaled` so the next enqueue wakes again.
    ///
    /// `CFRunLoopStop` here is what makes ``stop()`` synchronous.
    ///
    /// The terminating drain tears the loop down on its own thread, the thread then signals `didStopSignal`, and `stop()` returns.
    private func drainJobs() {
        let unownedExecutor = asUnownedSerialExecutor()
        let (jobs, terminating) = state.withLock { state -> ([UnownedJob], Bool) in
            let jobs = state.jobs
            // Keep the buffer for steady-state reuse, but drop it after an
            // outlier burst so a one-time spike doesn't pin capacity forever.
            state.jobs.removeAll(keepingCapacity: state.jobs.capacity <= Self.drainCapacityLimit)
            state.signaled = false
            return (jobs, state.phase == .terminating)
        }
        for job in jobs {
            job.runSynchronously(on: unownedExecutor)
        }
        if terminating {
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
    }
}
