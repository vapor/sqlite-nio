#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#elseif os(Windows)
import WinSDK
#endif

/// A fixed-width pool of dedicated worker threads used to run blocking libsqlite3 calls to avoid
/// blocking the default (global) concurrency executor's threads.
///
/// The ``shared`` pool is created lazily on first use and lives for the lifetime of the process. 
/// To control where a connection's work runs, pass any `TaskExecutor` of
/// your own to ``SQLiteConnection/open(storage:executor:)`` instead and it's your
/// responsibility to control the lifetime of, and it must outlive the connection.
///
/// On single-threaded platforms (WASI), the pool has no worker threads and runs submitted work
/// inline on the calling thread.
public final class SQLiteThreadPool: TaskExecutor, Sendable {
    /// The shared pool used by default for all connections
    public static let shared = SQLiteThreadPool(numberOfThreads: SQLiteThreadPool.defaultThreadCount)

    #if os(WASI)

    static var defaultThreadCount: Int { 1 }

    init(numberOfThreads: Int) {}

    public func enqueue(_ job: consuming ExecutorJob) {
        // WASI is single-threaded
        unsafe job.runSynchronously(on: self.asUnownedTaskExecutor())
    }

    #else

    private let queue = JobQueue()

    static var defaultThreadCount: Int {
        #if os(Windows)
        let info = UnsafeMutablePointer<SYSTEM_INFO>.allocate(capacity: 1)
        defer { unsafe info.deallocate() }
        unsafe GetSystemInfo(info)
        let processorCount = unsafe info.pointee.dwNumberOfProcessors
        return max(1, Int(processorCount))
        #else
        return Int(max(1, sysconf(Int32(_SC_NPROCESSORS_ONLN))))
        #endif
    }

    init(numberOfThreads: Int) {
        precondition(numberOfThreads > 0, "SQLiteThreadPool requires at least one thread")
        for index in 0 ..< numberOfThreads {
            Self.spawnWorkerThread(named: "sqlite-nio-\(index)", pool: self)
        }
    }

    public func enqueue(_ job: consuming ExecutorJob) {
        self.queue.push(UnownedJob(job))
    }

    private func workerLoop() -> Never {
        let unownedExecutor = unsafe self.asUnownedTaskExecutor()
        while true {
            unsafe self.queue.pop().runSynchronously(on: unownedExecutor)
        }
    }

    private static func spawnWorkerThread(named name: String, pool: SQLiteThreadPool) {
        final class Context {
            let pool: SQLiteThreadPool
            let name: String
            init(pool: SQLiteThreadPool, name: String) {
                self.pool = pool
                self.name = name
            }
        }
        // This is never released as the thread runs forever
        let context = unsafe Unmanaged.passRetained(Context(pool: pool, name: name)).toOpaque()

        // 2 MB on every platform
        let workerStackSize = 1 << 21

        #if os(Windows)
        let handle = unsafe CreateThread(nil, SIZE_T(workerStackSize), { arg in
            let context = unsafe Unmanaged<Context>.fromOpaque(arg!).takeRetainedValue()
            // Work around 6.3/6.4 differences in safety
            let wideName = Array(context.name.utf16) + [0]
            _ = unsafe SetThreadDescription(GetCurrentThread(), wideName)
            context.pool.workerLoop()
        }, context, 0, nil)
        precondition(unsafe handle != nil, "SQLiteThreadPool failed to spawn a worker thread (error \(GetLastError()))")
        unsafe CloseHandle(handle)
        #else

        let attributes = UnsafeMutablePointer<pthread_attr_t>.allocate(capacity: 1)
        defer { unsafe attributes.deallocate() }
        precondition(unsafe pthread_attr_init(attributes) == 0)
        defer { unsafe pthread_attr_destroy(attributes) }
        precondition(unsafe pthread_attr_setstacksize(attributes, workerStackSize) == 0)

        // Handle pthread differences between platforms, such as `pthread_t` being a pointer on Darwin and Musl, but integer on Glibc and Android
        #if canImport(Darwin)
        var tid: pthread_t? = nil
        let createRet = unsafe pthread_create(&tid, attributes, { arg in
            let context = unsafe Unmanaged<Context>.fromOpaque(arg).takeRetainedValue()
            unsafe pthread_setname_np(context.name)
            context.pool.workerLoop()
        }, context)
        #else
        #if canImport(Musl)
        var tid: pthread_t? = nil
        #else
        var tid = pthread_t()
        #endif
        let createRet = unsafe pthread_create(&tid, attributes, { arg in
            // If this is optional or not differs between platforms and platform versions
            let argument: UnsafeMutableRawPointer? = unsafe arg
            let context = unsafe Unmanaged<Context>.fromOpaque(argument!).takeRetainedValue()
            context.pool.workerLoop()
        }, context)
        #endif
        precondition(createRet == 0, "SQLiteThreadPool failed to spawn a worker thread (error \(createRet))")

        #endif
    }

    #endif
}

#if !os(WASI)
/// An unbounded FIFO queue of jobs guarded by a mutex/condition-variable pair to block idle worker threads until work arrives.
///
/// We can't use `Mutex` because we need a condition variable for a blocking `pop()` so use the platform's native pair directly:
/// pthreads on POSIX platforms, an `SRWLOCK` and `CONDITION_VARIABLE` on Windows.
@safe private final class JobQueue: @unchecked Sendable {
    #if os(Windows)

    private let lock: UnsafeMutablePointer<SRWLOCK>
    private let condition: UnsafeMutablePointer<CONDITION_VARIABLE>
    private var jobs = JobBuffer()

    init() {
        unsafe self.lock = .allocate(capacity: 1)
        unsafe self.condition = .allocate(capacity: 1)
        unsafe InitializeSRWLock(self.lock)
        unsafe InitializeConditionVariable(self.condition)
    }

    deinit {
        // SRW locks and condition variables have no teardown functions.
        unsafe self.condition.deallocate()
        unsafe self.lock.deallocate()
    }

    func push(_ job: UnownedJob) {
        unsafe AcquireSRWLockExclusive(self.lock)
        self.jobs.append(job)
        unsafe WakeConditionVariable(self.condition)
        unsafe ReleaseSRWLockExclusive(self.lock)
    }

    /// Blocks the calling thread until a job is available.
    func pop() -> UnownedJob {
        unsafe AcquireSRWLockExclusive(self.lock)
        while self.jobs.isEmpty {
            // DWORD.max is INFINITE; flags 0 means the lock is held in exclusive mode.
            unsafe SleepConditionVariableSRW(self.condition, self.lock, DWORD.max, 0)
        }
        let job = self.jobs.removeFirst()
        unsafe ReleaseSRWLockExclusive(self.lock)
        return job
    }

    #else

    private let mutex: UnsafeMutablePointer<pthread_mutex_t>
    private let condition: UnsafeMutablePointer<pthread_cond_t>
    private var jobs = JobBuffer()

    init() {
        unsafe self.mutex = .allocate(capacity: 1)
        unsafe self.condition = .allocate(capacity: 1)
        precondition(unsafe pthread_mutex_init(self.mutex, nil) == 0)
        precondition(unsafe pthread_cond_init(self.condition, nil) == 0)
    }

    deinit {
        precondition(unsafe pthread_cond_destroy(self.condition) == 0)
        precondition(unsafe pthread_mutex_destroy(self.mutex) == 0)
        unsafe self.condition.deallocate()
        unsafe self.mutex.deallocate()
    }

    func push(_ job: UnownedJob) {
        unsafe pthread_mutex_lock(self.mutex)
        self.jobs.append(job)
        unsafe pthread_cond_signal(self.condition)
        unsafe pthread_mutex_unlock(self.mutex)
    }

    /// Blocks the calling thread until a job is available.
    func pop() -> UnownedJob {
        unsafe pthread_mutex_lock(self.mutex)
        while self.jobs.isEmpty {
            unsafe pthread_cond_wait(self.condition, self.mutex)
        }
        let job = self.jobs.removeFirst()
        unsafe pthread_mutex_unlock(self.mutex)
        return job
    }

    #endif
}

/// A FIFO of jobs with amortised constant-time append and removal
private struct JobBuffer {
    private var storage: [UnownedJob] = []
    private var head = 0

    /// Consumed jobs are only discarded from a non-empty buffer once there are at least this many of them,
    /// and storage no larger than this is kept for reuse when the buffer drains.
    private static var compactionThreshold: Int { 1024 }

    var isEmpty: Bool {
        self.head == self.storage.count
    }

    mutating func append(_ job: UnownedJob) {
        self.storage.append(job)
    }

    /// The buffer must not be empty.
    mutating func removeFirst() -> UnownedJob {
        let job = self.storage[self.head]
        self.head += 1

        if self.head == self.storage.count {
            // Drained: start again from the front, without holding on to a large allocation after a burst.
            self.storage.removeAll(keepingCapacity: self.storage.capacity <= Self.compactionThreshold)
            self.head = 0
        } else if self.head >= Self.compactionThreshold, self.head >= self.storage.count - self.head {
            // At least half of the storage has been consumed. Discarding it moves no more jobs than it
            // discards, which keeps removal amortised constant-time.
            self.storage.removeFirst(self.head)
            self.head = 0
        }
        return job
    }
}
#endif
