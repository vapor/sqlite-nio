#if REQUIRES_TRAIT_CHOICE
  // Enforce: exactly one of the two traits
  #if !SQLite && !SQLCipher
    #error("Enable exactly one trait: `SQLite` or `SQLCipher` (in your Package.swift).")
  #endif

  #if SQLite && SQLCipher
    #error("`SQLite` and `SQLCipher` are mutually exclusive. Enable only one.")
  #endif
#endif
