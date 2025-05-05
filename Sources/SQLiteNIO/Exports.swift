@_documentation(visibility: internal) @_exported import struct NIOCore.ByteBuffer

#if canImport(NIOAsyncRuntime)
@_documentation(visibility: internal) @_exported import class NIOAsyncRuntime.AsyncThreadPool
#elseif canImport(NIOPosix)
@_documentation(visibility: internal) @_exported import class NIOPosix.NIOThreadPool
#endif

@_documentation(visibility: internal) @_exported import protocol NIOCore.EventLoop
@_documentation(visibility: internal) @_exported import protocol NIOCore.EventLoopGroup

#if canImport(NIOAsyncRuntime)
@_documentation(visibility: internal) @_exported import class NIOAsyncRuntime.AsyncEventLoopGroup
#elseif canImport(NIOPosix)
@_documentation(visibility: internal) @_exported import class NIOPosix.MultiThreadedEventLoopGroup
#endif
