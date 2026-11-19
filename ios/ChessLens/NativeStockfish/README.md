# Local Stockfish 19

This directory contains the official Stockfish 19 C++ source and NNUE evaluation network, plus the ChessLens in-process bridge. iOS never launches a child process or connects to the Mac for this engine.

- Upstream: https://github.com/official-stockfish/Stockfish/tree/edb0d9db6731067ec50ce619ff372b463bc4dd5d
- Release: `sf_19`, commit `edb0d9db6731067ec50ce619ff372b463bc4dd5d`.
- Source archive: https://codeload.github.com/official-stockfish/Stockfish/tar.gz/refs/tags/sf_19
- Source archive SHA-256: `519b653d0d1ffb96531d982ccbe5c6a19425e8388e0e3c2f70f34b424ab32d76`.
- Network: `nn-1a298aa575a0.nnue`, SHA-256 `1a298aa575a085434d29027978dc36867fe9c5bcea9376654b7a8eba1e52dfc2`.
- Network was exported from the already installed official Stockfish 19 Mac binary, whose release archive digest is recorded in the original project's `server/.tools/SOURCE.txt`. Its hash matches the upstream engine's default network name. An integrity check runs before the bridge loads it.
- Official network download: https://tests.stockfishchess.org/api/nn/nn-1a298aa575a0.nnue

The bridge initializes the engine lazily on the caller's worker queue, serializes searches, requests 3 principal variations with one engine thread and a 16 MiB hash, and bounds a requested search to 50–10,000 milliseconds. The app requests 2 seconds. `stop()` interrupts an active search. Native Stockfish 19 rejects malformed or unsupported FEN through its `set_position` error API. The bridge converts errors to Swift errors. It also intercepts Stockfish's network-verification error callback before upstream's process-exit fallback.

The one upstream portability modification is in `vendor/src/shm.h`: defining `CHESSLENS_NO_SHM` disables Unix cross-process shared memory and uses Stockfish's existing local-memory fallback. This avoids iOS process-sharing assumptions. All other vendor files are retained from the release archive. Bridge/core files are new ChessLens integration code.

Build C++17, `IS_64BIT`, `NNUE_EMBEDDING_OFF`, `CHESSLENS_NO_SHM`, `NDEBUG`; use `USE_NEON=8` on arm64. Compile all vendor `src/*.cpp` except `main.cpp`, and `nnue/*.cpp`, `nnue/features/*.cpp`, `syzygy/tbprobe.cpp`, plus `NativeEngine.cpp` and `StockfishBridge.mm`. Do not compile `src/universal/*` (those are desktop multiarchitecture entrypoints). Include the NNUE as a resource at the app bundle root. Set the Swift bridging header to `ChessLens/NativeStockfish/ChessLens-Bridging-Header.h`.

Run `python3 scripts/check_native_stockfish.py` from the project root for native-engine + Swift integration checks on macOS. The checks use the same bundled network and bridge as the iOS app. They do not prove physical-device performance or memory usage.

Stockfish and its network are GPL-3.0-or-later. Retain `vendor/Copying.txt` and `vendor/AUTHORS`. This bridge/core is also GPL-3.0-or-later. A distributed app linking Stockfish must meet the GPL obligations, including providing the complete corresponding source and build materials. The recognition models have their own separate notices and rights; this folder does not change them.
