#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
@preconcurrency import Glibc
#elseif canImport(Musl)
@preconcurrency import Musl
#elseif canImport(Android)
@preconcurrency import Android
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
        job.runSynchronously(on: self.asUnownedTaskExecutor())
    }

    #else

    private let queue = JobQueue()

    static var defaultThreadCount: Int {
        #if os(Windows)
        var info = SYSTEM_INFO()
        GetSystemInfo(&info)
        return max(1, Int(info.dwNumberOfProcessors))
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

    private func workerLoop() {
        let unownedExecutor = self.asUnownedTaskExecutor()
        while true {
            self.queue.pop().runSynchronously(on: unownedExecutor)
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
        let context = Unmanaged.passRetained(Context(pool: pool, name: name)).toOpaque()

        // 2 MB on every platform
        let workerStackSize = 1 << 21

        #if os(Windows)
        let handle = CreateThread(nil, SIZE_T(workerStackSize), { arg in
            let context = Unmanaged<Context>.fromOpaque(arg!).takeRetainedValue()
            _ = context.name.withCString(encodedAs: UTF16.self) {
                SetThreadDescription(GetCurrentThread(), $0)
            }
            context.pool.workerLoop()
            return 0
        }, context, 0, nil)
        precondition(handle != nil, "SQLiteThreadPool failed to spawn a worker thread (error \(GetLastError()))")
        CloseHandle(handle)
        #else

        var attr = pthread_attr_t()
        precondition(pthread_attr_init(&attr) == 0)
        precondition(pthread_attr_setstacksize(&attr, workerStackSize) == 0)
        defer { pthread_attr_destroy(&attr) }

        // Handle pthread differences between platforms, such as `pthread_t` being a pointer on Darwin and Musl, but integer on Glibc and Android
        #if canImport(Darwin)
        var tid: pthread_t? = nil
        let createRet = pthread_create(&tid, &attr, { arg in
            let context = Unmanaged<Context>.fromOpaque(arg).takeRetainedValue()
            pthread_setname_np(context.name)
            context.pool.workerLoop()
            return nil
        }, context)
        #else
        #if canImport(Musl)
        var tid: pthread_t? = nil
        #else
        var tid = pthread_t()
        #endif
        let createRet = pthread_create(&tid, &attr, { arg in
            let context = Unmanaged<Context>.fromOpaque(arg!).takeRetainedValue()
            context.pool.workerLoop()
            return nil
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
private final class JobQueue: @unchecked Sendable {
    #if os(Windows)

    private let lock: UnsafeMutablePointer<SRWLOCK>
    private let condition: UnsafeMutablePointer<CONDITION_VARIABLE>
    private var jobs: [UnownedJob] = []

    init() {
        self.lock = .allocate(capacity: 1)
        self.condition = .allocate(capacity: 1)
        InitializeSRWLock(self.lock)
        InitializeConditionVariable(self.condition)
    }

    deinit {
        // SRW locks and condition variables have no teardown functions.
        self.condition.deallocate()
        self.lock.deallocate()
    }

    func push(_ job: UnownedJob) {
        AcquireSRWLockExclusive(self.lock)
        self.jobs.append(job)
        WakeConditionVariable(self.condition)
        ReleaseSRWLockExclusive(self.lock)
    }

    /// Blocks the calling thread until a job is available.
    func pop() -> UnownedJob {
        AcquireSRWLockExclusive(self.lock)
        while self.jobs.isEmpty {
            // DWORD.max is INFINITE; flags 0 means the lock is held in exclusive mode.
            SleepConditionVariableSRW(self.condition, self.lock, DWORD.max, 0)
        }
        let job = self.jobs.removeFirst()
        ReleaseSRWLockExclusive(self.lock)
        return job
    }

    #else

    private let mutex: UnsafeMutablePointer<pthread_mutex_t>
    private let condition: UnsafeMutablePointer<pthread_cond_t>
    private var jobs: [UnownedJob] = []

    init() {
        self.mutex = .allocate(capacity: 1)
        self.condition = .allocate(capacity: 1)
        precondition(pthread_mutex_init(self.mutex, nil) == 0)
        precondition(pthread_cond_init(self.condition, nil) == 0)
    }

    deinit {
        precondition(pthread_cond_destroy(self.condition) == 0)
        precondition(pthread_mutex_destroy(self.mutex) == 0)
        self.condition.deallocate()
        self.mutex.deallocate()
    }

    func push(_ job: UnownedJob) {
        pthread_mutex_lock(self.mutex)
        self.jobs.append(job)
        pthread_cond_signal(self.condition)
        pthread_mutex_unlock(self.mutex)
    }

    /// Blocks the calling thread until a job is available.
    func pop() -> UnownedJob {
        pthread_mutex_lock(self.mutex)
        while self.jobs.isEmpty {
            pthread_cond_wait(self.condition, self.mutex)
        }
        let job = self.jobs.removeFirst()
        pthread_mutex_unlock(self.mutex)
        return job
    }

    #endif
}
#endif
