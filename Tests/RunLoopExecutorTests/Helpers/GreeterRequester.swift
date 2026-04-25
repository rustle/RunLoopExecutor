//
//  GreeterRequester.swift
//
//  Copyright © 2026 Doug Russell. All rights reserved.
//

import Foundation
import RunLoopExecutor

actor Greeter {
    nonisolated let executor: RunLoopExecutor
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }
    init(executor: RunLoopExecutor) {
        self.executor = executor
    }
    func greeting(for name: String) -> String {
        "hello, \(name)"
    }
}

actor Requester {
    nonisolated let executor: RunLoopExecutor
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }
    init(executor: RunLoopExecutor) {
        self.executor = executor
    }
    func requestGreeting(with greeter: Greeter) -> String {
        greeter.assumeIsolated { greeter in
            greeter.greeting(for: "world.")
        }
    }
    func threadNameViaBoth(with greeter: Greeter) -> (String?, String?) {
        (
            Thread.current.name,
            greeter.assumeIsolated { _ in
                Thread.current.name
            }
        )
    }
}
