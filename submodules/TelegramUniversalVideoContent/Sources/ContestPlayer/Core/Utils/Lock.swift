import Darwin

final class UnfairLock: @unchecked Sendable {
    private let mutex: UnsafeMutablePointer<os_unfair_lock_s> = .allocate(capacity: 1)

    init() {
        mutex.initialize(to: os_unfair_lock_s())
    }
    
    deinit {
        mutex.deinitialize(count: 1)
        mutex.deallocate()
    }

    func lock() {
        os_unfair_lock_lock(mutex)
    }

    func unlock() {
        os_unfair_lock_unlock(mutex)
    }
    
    @inlinable
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer {
            unlock()
        }
        return try body()
    }
}

@propertyWrapper
final class ThreadSafe<Value> {
    private var _wrappedValue: Value
    private let lock = UnfairLock()

    init(wrappedValue: Value) {
        _wrappedValue = wrappedValue
    }

    init(initialValue: Value) {
        _wrappedValue = initialValue
    }

    var wrappedValue: Value {
        get {
            lock.withLock { _wrappedValue }
        }
        set {
            lock.withLock { _wrappedValue = newValue }
        }
        _modify {
            lock.lock()
            defer { lock.unlock() }

            yield &_wrappedValue
        }
    }
}
