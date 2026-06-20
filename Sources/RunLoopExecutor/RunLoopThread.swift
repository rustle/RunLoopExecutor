//
//  RunLoopThread.swift
//
//  Copyright © 2017-2026 Doug Russell. All rights reserved.
//

import Foundation

final class RunLoopThread: Thread {
    enum Event {
        case threadID(UInt64)
        case wake
        case didStop
    }

    var eventHandler: (Event) -> Void = { _ in }

    init(
        name: String,
        qualityOfService: QualityOfService
    ) {
        super.init()
        self.name = name
        self.qualityOfService = qualityOfService
    }

    override func main() {
        var threadID: UInt64 = 0
        if pthread_threadid_np(nil, &threadID) == 0 {
            eventHandler(.threadID(threadID))
        }
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            var context = CFRunLoopSourceContext()
            guard let source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context) else {
                return
            }
            CFRunLoopAddSource(runLoop, source, .defaultMode)
            CFRunLoopRun()
            CFRunLoopRemoveSource(runLoop, source, .defaultMode)
        }
        eventHandler(.didStop)
    }

    @objc func wake() {
        eventHandler(.wake)
    }
}
