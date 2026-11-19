# ChessLens

ChessLens is a native offline chess analysis app for iPhone. Edit the board or import a FEN, play legal moves, and ask the built-in Stockfish 19 engine for its best move and alternatives. This edition does not include camera scanning, photo permissions, or any recognition models.

Requires iOS 17.0 or later on an arm64 iPhone. For signed installation using your free Apple Account, see [Install and troubleshoot](docs/INSTALLATION.md). See [Privacy](docs/PRIVACY.md).

For the official unsigned IPA and checksum, check [GitHub Releases](https://github.com/Eman-ej/ChessLens/releases).

## Build from source

On macOS with Xcode and Python 3, run from this directory:

```sh
python3 scripts/fetch_stockfish_network.py
xcodebuild -project ios/ChessLens.xcodeproj -scheme ChessLens \
  -configuration Release -xcconfig ios/StockfishRelease.xcconfig \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/ChessLensStockfishRelease \
  ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build
python3 scripts/package_distribution.py release-builds/v1.0.0/ChessLens-v1.0.0.ipa \
  --stockfish-only --from-app /tmp/ChessLensStockfishRelease/Build/Products/Release-iphoneos/ChessLens.app
```

A Git checkout fetches the pinned Stockfish network from the upstream server and verifies its SHA-256. The full corresponding source ZIP already includes the network; the script verifies the local copy without downloading it again.

The IPA is unsigned so you can sign it yourself. Use AltStore Classic to sign and install your own builds, or open the Xcode project, select your own development team and a unique bundle ID in Signing & Capabilities, then run on your iPhone. No original developer signing key or profile is required.

To run the local engine integration checks: `python3 scripts/check_native_stockfish.py`.

## Licensing

ChessLens's original code and the Stockfish-edition icon are licensed under the GNU General Public License, version 3 or (at your option) any later version. See [LICENSE](LICENSE). The vendored Stockfish 19 source, NNUE evaluation data, iOS portability patch, authors, and bridge sources are retained under [NativeStockfish](ios/ChessLens/NativeStockfish/README.md). The linked executable needs both the ChessLens and Stockfish sources; this source tree contains both.
