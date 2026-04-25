# RunLoopExecutor

Swift Concurrency `SerialExecutor` backed by a dedicated `CFRunLoop`+`Thread`, with pool types and a `suspendAwaitingThrow` utility function on `Actor` to stand in where a Cocoa app might call `CFRunLoopRun()`.

## Products

| Product | Description |
|---|---|
| `RunLoopExecutor` | Core executor and `suspendAwaitingThrow` utility |
| `RunLoopExecutorPool` | `RunLoopExecutorFixedPool` and `RunLoopExecutorDynamicPool` |

## Usage

### RunLoopExecutor

Create and start an executor, then give it to any actor that should run on that thread:

```swift
import RunLoopExecutor

let executor = RunLoopExecutor(
    name: "my-thread", 
    qualityOfService: .userInitiated
)
executor.start()

actor MyActor {
    nonisolated let executor: RunLoopExecutor
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }
    init(executor: RunLoopExecutor) { self.executor = executor }

    func doWork() {
        // always runs on executor's CFRunLoop thread
    }
}

let actor = MyActor(executor: executor)
await actor.doWork()
```

Multiple actors can share one executor. Because they occupy the same isolation context, hops between them involve no thread switch, and work issued from any of them is automatically serialised.

```swift
let executor = RunLoopExecutor(name: "shared-thread")
executor.start()

let a = ActorA(executor: executor)
let b = ActorB(executor: executor)

// From within ActorA, calling b.someMethod() does not hop threads.
// assumeIsolated works because both actors run on the same executor.
```

### Why a dedicated CFRunLoop thread

Swift's cooperative executor pool spreads work across a pool of threads with no thread affinity guarantees. Some APIs require a specific thread:

- `CFRunLoopSource` and `CFRunLoopTimer` — scheduled on a `CFRunLoop` and deliver callbacks on that loop's thread.
- `AXObserver` — a `CFRunLoopSource` that delivers accessibility events; must be scheduled and serviced on the same thread.
- Any API that calls `CFRunLoopGetCurrent()` to bind to a thread.

A `RunLoopExecutor` gives those APIs a stable home. All actors that adopt the same executor share one thread, so callbacks and IPC calls to the same remote process are automatically serialised without additional locking.

### suspendAwaitingThrow

The following simplified example shows using `suspendAwaitingThrow()` to wait for a signal to make it's way through a run loop source to trigger a call that cancels the `Task` where `suspendAwaitingThrow` is waiting.

[SignalSource.swift](/Tests/RunLoopExecutorTests/Helpers/SignalSource.swift)

```swift
import RunLoopExecutor

final class SignalSource: Sendable {
    ...

    func schedule() {
        ...
        CFRunLoopAddSource(
            runLoop,
            source,
            .defaultMode
        )
    }

    func signal() {
        ...
        CFRunLoopSourceSignal(source)
        CFRunLoopWakeUp(runLoop)
    }

    func remove() {
        ...
        CFRunLoopRemoveSource(
            runLoop,
            source,
            .defaultMode
        )
    }
}
```

[SignalSource.swift](/Tests/RunLoopExecutorTests/Helpers/SourceActor.swift)

```
actor SourceActor {
    nonisolated let executor: RunLoopExecutor
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }
    private(set) var fired = false
    
    ...

    // Schedules the source from the RunLoop thread, then suspends.
    // The source callback cancels this task, waking us here.
    func installAndWait(source: SignalSource) async {
        source.schedule()
        performOnCurrentRunLoop {
            source.signal()
        }
        do {
            try await Self.suspendAwaitingThrow()
        } catch is CancellationError {
            fired = true
        } catch {}
    }
    
    ...
}
```

The `SignalSource` callback cancels the task:

```swift
let actor = SourceActor(executor: executor)
let source = SignalSource {
    let task = ...
    // Fired on the RunLoopExecutor's thread. Task.cancel() is safe
    // to call from any context.
    task?.cancel()
}
let task = Task {
    await actor.installAndWait(source: source)
    return await actor.fired
}
... = task
await task.value == true
```

### RunLoopExecutorFixedPool

A fixed-width pool that allocates executors round-robin. All executors are started at init.

```swift
import RunLoopExecutorPool

// One executor per active CPU core (default)
let pool = RunLoopExecutorFixedPool()

// Or a specific count
let pool = RunLoopExecutorFixedPool(count: 4, qualityOfService: .userInitiated)

// Assign executors to actors at creation time
let actor = MyActor(executor: pool.next())
```

`next()` is safe to call from any context. The executor is returned directly — no async acquisition, no waiting.

### RunLoopExecutorDynamicPool

A pool that grows on demand up to a maximum width. Executors are acquired for the lifetime of a closure and returned automatically. Idle executors are reused before new threads are spawned; at maximum width, work is distributed to the least-loaded active executor.

```swift
import RunLoopExecutorPool

let pool = RunLoopExecutorDynamicPool(maximumWidth: 4)

let result = await pool.withRunLoopExecutor { executor in
    await MyActor(executor: executor).doWork()
}
```

`withRunLoopExecutor` supports `rethrows` to allow

```swift
let result = try await pool.withRunLoopExecutor { executor in
    try await MyActor(executor: executor).doWork()
}
```

Parking your actor to await work with `suspendAwaitingThrow()` from inside `withRunLoopExecutor` is supported.

In this example configuration `MyActor` would register for events/notifications/observers, await observed events, and when it's done observing it would call `Task.cancel()`.

```swift
actor MyActor {
    ...
    func scheduleObservers() {
        ...
    }
    func removeObservers() {
        ...
    }
    ...
}

await pool.withRunLoopExecutor { executor in
    // 
    // 
    let actor = MyActor(executor: executor)
    await actor.scheduleObservers()
    await MyActor.suspendAwaitingThrow()
    await actor.removeObservers()
}
```

## Miscellaneous

`RunLoopExecutor` code started out as part of the `Observer` implementation in [AccessibilityElement](https://github.com/rustle/AccessibilityElement). The pool implementations are more recent, in support of [ScreenReader](https://github.com/rustle/screenreader) `Controller`. This verions of the code is the first time I've worked on letting executors/threads be retired. I'm happy with where it's at, but I also assume that will be where I find out I missed something.

To a near certaintly, but who knows when, I'll have another pass at this same idea but instead of giving each executor a `Thread`, I'll give each executor a `CFRunLoopSource`. I'd love to see how it compares in real world usage in `ScreenReader`. 

## Requirements

- macOS 15 / iOS 13
- Swift 6

## License

RunLoopExecutor is released under an Apache license. See the LICENSE file for more information.
