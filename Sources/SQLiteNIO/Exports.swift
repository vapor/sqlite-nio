#if swift(>=5.8)

@_documentation(visibility: internal) @_exported import struct NIOCore.ByteBuffer
@_documentation(visibility: internal) @_exported import class NIOPosix.NIOThreadPool
@_documentation(visibility: internal) @_exported import protocol NIOCore.EventLoop
@_documentation(visibility: internal) @_exported import protocol NIOCore.EventLoopGroup
@_documentation(visibility: internal) @_exported import class NIOPosix.MultiThreadedEventLoopGroup

#else

@_exported import struct NIOCore.ByteBuffer
@_exported import class NIOPosix.NIOThreadPool
@_exported import protocol NIOCore.EventLoop
@_exported import protocol NIOCore.EventLoopGroup
@_exported import class NIOPosix.MultiThreadedEventLoopGroup

#endif
