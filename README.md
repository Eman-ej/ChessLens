# ChessLens

This branch adds offline physical-board scanning to the AltStore edition. The private test build is 1.1.0 (19) and uses the existing AltStore bundle identifier. The published v1.0.0 release provides manual setup, FEN import and Stockfish 19.

Choose **Camera**, **Choose photo** or **Try a sample photo**, then **Scan board**. For guided scanning, select **Scan with marked corners**, tap the four outer corners of the playing squares and identify a1. The sample photo comes with its corners marked. Review the pieces, set the side to move and any known castling or en passant rights, then tap **Find best move**.

Requires iOS 17.0 or later on an arm64 iPhone. For signed installation using your free Apple Account, see [Install and troubleshoot](docs/INSTALLATION.md). See [Privacy](docs/PRIVACY.md).

For a private test, transfer the locally built IPA to Files on the iPhone and select it in **AltStore Classic → My Apps → +** with AltServer reachable. The [public releases](https://github.com/Eman-ej/ChessLens/releases) have their own version history.

## Build from source

The private scanner build expects locally supplied resources in `ios/ChessLens/`. To reproduce the build, supply the matching `FenformerBoard.mlpackage`, `FenformerFraming.mlpackage`, `ChessLensColabT4.mlmodel` and `SampleRealBoard.jpg`. The repository excludes these four assets while their redistribution terms are under review.

On macOS with Xcode and Python 3, run from this directory:

```sh
python3 scripts/fetch_stockfish_network.py
xcodebuild -project ios/ChessLens.xcodeproj -scheme ChessLens \
  -configuration Release -xcconfig ios/Distribution.xcconfig \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/ChessLensAltScanner19Device \
  ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build
python3 scripts/package_distribution.py release-builds/private-v1.1.0/ChessLens-v1.1.0.ipa \
  --from-app /tmp/ChessLensAltScanner19Device/Build/Products/Release-iphoneos/ChessLens.app
```

A Git checkout fetches the pinned Stockfish network from the upstream server and verifies its SHA-256. If the network is already present, the script verifies the local copy.

The IPA is unsigned so you can sign it yourself. Use AltStore Classic to sign and install your own builds, or open the Xcode project, select your own development team and a unique bundle ID in Signing & Capabilities, then run on your iPhone. No original developer signing key or profile is required.

To run the local engine integration checks: `python3 scripts/check_native_stockfish.py`.

## Licensing

ChessLens's original code and the Stockfish-edition icon are licensed under the GNU General Public License, version 3 or (at your option) any later version. See [LICENSE](LICENSE). The vendored Stockfish 19 source, NNUE evaluation data, iOS portability patch, authors, and bridge sources are retained under [NativeStockfish](ios/ChessLens/NativeStockfish/README.md). The linked executable needs both the ChessLens and Stockfish sources; this source tree contains both.

The scanner weights and sample photo have separate terms. See the [Fenformer notices](ios/ChessLens/FenformerNotices.txt) and [Colab T4 and ChessReD notices](ios/ChessLens/ColabModelNotices.txt). Public redistribution of the bundled scanner assets is unresolved.
