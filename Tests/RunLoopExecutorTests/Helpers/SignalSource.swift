import Foundation
import os
import RunLoopExecutor

final class SignalSource: Sendable {
    private final class Handler {
        let handler: @Sendable () -> Void
        init(_ fn: @escaping @Sendable () -> Void) {
            self.handler = fn
        }
    }
    private struct State {
        var source: CFRunLoopSource?
        var runLoop: CFRunLoop? = nil
    }

    private let state: OSAllocatedUnfairLock<State>

    init(perform: @escaping @Sendable () -> Void) {
        let handler = Unmanaged.passRetained(Handler(perform))
        var context = CFRunLoopSourceContext()
        context.info = handler.toOpaque()
        context.perform = { info in
            guard let info else {
                return
            }
            Unmanaged<Handler>.fromOpaque(info).takeRetainedValue().handler()
        }
        let source = CFRunLoopSourceCreate(
            kCFAllocatorDefault,
            0,
            &context
        )!
        state = .init(uncheckedState: State(source: source))
    }

    func schedule() {
        guard let (source, runLoop) = state.withLockUnchecked({
            guard let source = $0.source, $0.runLoop == nil else {
                return nil as (CFRunLoopSource, CFRunLoop)?
            }
            let runLoop = CFRunLoopGetCurrent()!
            $0.runLoop = runLoop
            return (source, runLoop)
        }) else {
            return
        }
        CFRunLoopAddSource(
            runLoop,
            source,
            .defaultMode
        )
    }

    func signal() {
        guard let (source, runLoop) = state.withLockUnchecked({
            guard let source = $0.source, let runLoop = $0.runLoop else {
                return nil as (CFRunLoopSource, CFRunLoop)?
            }
            return (source, runLoop)
        }) else {
            return
        }
        CFRunLoopSourceSignal(source)
        CFRunLoopWakeUp(runLoop)
    }

    func remove() {
        guard let (source, runLoop) = state.withLockUnchecked({
            guard let source = $0.source, let runLoop = $0.runLoop else {
                return nil as (CFRunLoopSource, CFRunLoop)?
            }
            $0.source = nil
            $0.runLoop = nil
            return (source, runLoop)
        }) else {
            return
        }
        CFRunLoopRemoveSource(
            runLoop,
            source,
            .defaultMode
        )
    }
}
