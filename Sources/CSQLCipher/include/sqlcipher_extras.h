/*
 * sqlcipher_extras.h
 *
 * SwiftPM does not propagate `cSettings` defines (like SQLITE_HAS_CODEC)
 * when it parses public headers to build the Clang module interface
 * that Swift imports. As a result, the SQLCipher-specific APIs in
 * `sqlite_nio_sqlcipher.h` (such as sqlite3_key / sqlite3_rekey) are
 * hidden behind `#ifdef SQLITE_HAS_CODEC` and end up invisible to Swift.
 *
 * This header makes the build self-sufficient by forcing
 * `SQLITE_HAS_CODEC` to be defined whenever the module is imported.
 * That way, the SQLCipher APIs are always declared and visible in Swift.
 */

#ifndef SQLCIPHER_EXTRAS_H
#define SQLCIPHER_EXTRAS_H

#ifndef SQLITE_HAS_CODEC
#define SQLITE_HAS_CODEC 1
#endif

#endif /* SQLCIPHER_EXTRAS_H */
