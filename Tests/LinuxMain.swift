import XCTest

import NIOSQLiteTests

var tests = [XCTestCaseEntry]()
tests += NIOSQLiteTests.allTests()
XCTMain(tests)
