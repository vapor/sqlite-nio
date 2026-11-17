#ifndef SQLITE_NIO_SAFETY_H
#define SQLITE_NIO_SAFETY_H

#include "sqlite_nio_sqlite3.h"

/*
** Swift memory-safety annotations for the vendored SQLite API for functions we know to be safe.
**
** This header is maintained by hand
*/
#define SQLITE_NIO_SWIFT_SAFE __attribute__((swift_attr("@safe")))

#ifdef __cplusplus
extern "C" {
#endif

SQLITE_API int sqlite_nio_sqlite3_value_type(sqlite3_value*) SQLITE_NIO_SWIFT_SAFE;
SQLITE_API sqlite3_int64 sqlite_nio_sqlite3_value_int64(sqlite3_value*) SQLITE_NIO_SWIFT_SAFE;
SQLITE_API double sqlite_nio_sqlite3_value_double(sqlite3_value*) SQLITE_NIO_SWIFT_SAFE;
SQLITE_API int sqlite_nio_sqlite3_value_bytes(sqlite3_value*) SQLITE_NIO_SWIFT_SAFE;

SQLITE_API int sqlite_nio_sqlite3_step(sqlite3_stmt*) SQLITE_NIO_SWIFT_SAFE;
SQLITE_API int sqlite_nio_sqlite3_bind_double(sqlite3_stmt*, int, double) SQLITE_NIO_SWIFT_SAFE;
SQLITE_API int sqlite_nio_sqlite3_bind_int64(sqlite3_stmt*, int, sqlite3_int64) SQLITE_NIO_SWIFT_SAFE;
SQLITE_API int sqlite_nio_sqlite3_bind_null(sqlite3_stmt*, int) SQLITE_NIO_SWIFT_SAFE;
SQLITE_API int sqlite_nio_sqlite3_column_count(sqlite3_stmt*) SQLITE_NIO_SWIFT_SAFE;
SQLITE_API int sqlite_nio_sqlite3_column_type(sqlite3_stmt*, int) SQLITE_NIO_SWIFT_SAFE;
SQLITE_API sqlite3_int64 sqlite_nio_sqlite3_column_int64(sqlite3_stmt*, int) SQLITE_NIO_SWIFT_SAFE;
SQLITE_API double sqlite_nio_sqlite3_column_double(sqlite3_stmt*, int) SQLITE_NIO_SWIFT_SAFE;
SQLITE_API int sqlite_nio_sqlite3_column_bytes(sqlite3_stmt*, int) SQLITE_NIO_SWIFT_SAFE;

SQLITE_API void sqlite_nio_sqlite3_result_null(sqlite3_context*) SQLITE_NIO_SWIFT_SAFE;
SQLITE_API void sqlite_nio_sqlite3_result_int64(sqlite3_context*, sqlite3_int64) SQLITE_NIO_SWIFT_SAFE;
SQLITE_API void sqlite_nio_sqlite3_result_double(sqlite3_context*, double) SQLITE_NIO_SWIFT_SAFE;
SQLITE_API void sqlite_nio_sqlite3_result_error_code(sqlite3_context*, int) SQLITE_NIO_SWIFT_SAFE;

#ifdef __cplusplus
}
#endif

#endif /* SQLITE_NIO_SAFETY_H */
