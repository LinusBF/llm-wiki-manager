import CoreServices
import Foundation

public enum RawFolderWatcherError: LocalizedError {
    case streamCreationFailed

    public var errorDescription: String? {
        switch self {
        case .streamCreationFailed:
            "Could not create the FSEvents stream."
        }
    }
}

public final class RawFolderWatcher {
    private var stream: FSEventStreamRef?
    private var onChange: (() -> Void)?
    private var debounceWorkItem: DispatchWorkItem?

    public init() {}

    deinit {
        stop()
    }

    public func start(watching rawURL: URL, onChange: @escaping () -> Void) throws {
        stop()
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, contextInfo, _, _, _, _ in
            guard let contextInfo else { return }
            let watcher = Unmanaged<RawFolderWatcher>.fromOpaque(contextInfo).takeUnretainedValue()
            watcher.scheduleDebouncedChange()
        }

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let createdStream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [rawURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            flags
        ) else {
            throw RawFolderWatcherError.streamCreationFailed
        }

        stream = createdStream
        FSEventStreamSetDispatchQueue(createdStream, DispatchQueue.main)
        FSEventStreamStart(createdStream)
    }

    public func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }

        onChange = nil
    }

    private func scheduleDebouncedChange() {
        DispatchQueue.main.async {
            self.debounceWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.onChange?()
            }
            self.debounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
        }
    }
}
