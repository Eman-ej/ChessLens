#!/usr/bin/env python3
"""Fetch and verify the exact Stockfish 19 evaluation network for a source checkout."""

from pathlib import Path
import tempfile
from urllib.request import urlopen

from package_distribution import NETWORK, NETWORK_SHA256, digest, require

directory = Path(__file__).resolve().parents[1] / "ios/ChessLens/NativeStockfish"
target = directory / NETWORK

if target.is_file():
    with target.open("rb") as existing:
        require(digest(existing) == NETWORK_SHA256, "Existing NNUE has the wrong checksum")
else:
    with tempfile.TemporaryDirectory(dir=directory) as temp:
        staged = Path(temp) / NETWORK
        with urlopen(f"https://tests.stockfishchess.org/api/nn/{NETWORK}", timeout=45) as response:
            with staged.open("wb") as output:
                for block in iter(lambda: response.read(1024 * 1024), b""):
                    output.write(block)
        with staged.open("rb") as downloaded:
            require(digest(downloaded) == NETWORK_SHA256, "Downloaded NNUE has the wrong checksum")
        staged.replace(target)
print(f"Verified {NETWORK}")
