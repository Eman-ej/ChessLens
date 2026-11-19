#!/usr/bin/env python3
"""Build the actual bundled Stockfish + Objective-C bridge and run Swift integration checks on macOS."""
import argparse
import concurrent.futures
import hashlib
import os
from pathlib import Path
import platform
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / "ios/ChessLens/NativeStockfish"
EXPECTED_NET = "1a298aa575a085434d29027978dc36867fe9c5bcea9376654b7a8eba1e52dfc2"

def run(command):
    result = subprocess.run([str(x) for x in command], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(result.stdout or f"Command failed: {command[0]}")
    return result.stdout

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path)
    parser.add_argument("--build-only", action="store_true")
    args = parser.parse_args()
    if platform.system() != "Darwin":
        raise SystemExit("These bridge checks require macOS with Xcode.")
    build = args.build_dir or Path(tempfile.mkdtemp(prefix="chesslens-native-check-"))
    build.mkdir(parents=True, exist_ok=True)
    net = NATIVE / "nn-1a298aa575a0.nnue"
    if hashlib.sha256(net.read_bytes()).hexdigest() != EXPECTED_NET:
        raise SystemExit("Bundled NNUE integrity check failed.")
    sources = sorted(p for p in (NATIVE / "vendor/src").glob("*.cpp") if p.name != "main.cpp")
    sources += sorted((NATIVE / "vendor/src/nnue").glob("*.cpp"))
    sources += sorted((NATIVE / "vendor/src/nnue/features").glob("*.cpp"))
    sources += [NATIVE / "vendor/src/syzygy/tbprobe.cpp", NATIVE / "NativeEngine.cpp", NATIVE / "StockfishBridge.mm"]
    flags = ["-std=c++17", "-O2", "-DNDEBUG", "-DNNUE_EMBEDDING_OFF", "-DIS_64BIT", "-DCHESSLENS_NO_SHM", "-pthread"]
    if platform.machine() == "arm64": flags.append("-DUSE_NEON=8")
    def compile_one(source):
        target = build / ("_".join(source.relative_to(NATIVE).parts) + ".o")
        extra = ["-fobjc-arc"] if source.suffix == ".mm" else []
        run(["xcrun", "clang++", *flags, *extra, "-c", source, "-o", target])
        return target
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        objects = list(pool.map(compile_one, sources))
    archive = build / "libChessLensStockfish.a"
    run(["xcrun", "libtool", "-static", "-o", archive, *objects])
    print(f"Native archive: {archive}")
    if args.build_only: return
    app = ROOT / "ios/ChessLens"
    executable = build / "check-local-stockfish"
    run(["xcrun", "swiftc", "-parse-as-library", "-module-cache-path", build / "module-cache", "-import-objc-header", NATIVE / "StockfishBridge.h",
         app / "ChessPosition.swift", app / "ChessLegalMoves.swift", app / "ServiceClient.swift",
         app / "LocalStockfish.swift", ROOT / "scripts/check_local_stockfish.swift", archive,
         "-Xlinker", "-lc++", "-framework", "Foundation", "-framework", "Security", "-o", executable])
    env = dict(os.environ, CHESSLENS_STOCKFISH_NETWORK=str(net))
    result = subprocess.run([str(executable)], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(result.stdout)
    raise SystemExit(result.returncode)

if __name__ == "__main__": main()
