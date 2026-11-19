#!/usr/bin/env python3
"""Package or verify a local, unsigned ChessLens iPhone IPA. Does not publish it."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = "Payload/ChessLens.app/"
NETWORK = "nn-1a298aa575a0.nnue"
NETWORK_SHA256 = "1a298aa575a085434d29027978dc36867fe9c5bcea9376654b7a8eba1e52dfc2"
MODELS = {"ChessLensColabT4.mlmodelc", "FenformerBoard.mlmodelc", "FenformerFraming.mlmodelc"}
FILES = {
    "AppIcon60x60@2x.png", "Assets.car", "ChessLens", "ColabModelNotices.txt", "Copying.txt",
    "FenformerNotices.txt", "Info.plist", "SampleRealBoard.jpg", "StockfishNotices.txt", NETWORK,
}
OPTIONAL = {"AppIcon76x76@2x~ipad.png", "PkgInfo"}
STOCKFISH_FILES = FILES - {"ColabModelNotices.txt", "FenformerNotices.txt", "SampleRealBoard.jpg"}
PRIVATE_NAME = re.compile(r"(^\.|^_CodeSignature$|profile$|\.(?:pem|key|p8|p12|cer|dylib)$)", re.I)
SECRET = re.compile(rb"-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,}|sk-[0-9a-f]{32}\b")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(file):
    hashed = hashlib.sha256()
    for block in iter(lambda: file.read(1024 * 1024), b""):
        hashed.update(block)
    return hashed.hexdigest()


def verify(ipa, stockfish_only=False):
    settings = dict(re.findall(r"^(\w+) = ([\w.]+)$", (ROOT / "ios/Distribution.xcconfig").read_text(), re.M))
    if stockfish_only:
        settings.update(re.findall(r"^(\w+) = ([\w.]+)$", (ROOT / "ios/StockfishRelease.xcconfig").read_text(), re.M))
    required_files = STOCKFISH_FILES if stockfish_only else FILES
    models = set() if stockfish_only else MODELS
    with zipfile.ZipFile(ipa) as archive:
        members = archive.infolist()
        require(len({entry.filename for entry in members}) == len(members), "Duplicate ZIP entry")
        bundled_files = set()
        for entry in members:
            filename = entry.filename
            if entry.is_dir() and filename in {"Payload/", BUNDLE}:
                continue
            require(filename.startswith(BUNDLE), "Unexpected item outside ChessLens.app")
            path = PurePosixPath(filename[len(BUNDLE):])
            require(path.parts and ".." not in path.parts and all(not PRIVATE_NAME.search(part) for part in path.parts), f"Unexpected file: {filename}")
            require(not stat.S_ISLNK(entry.external_attr >> 16), "Symlinks are not allowed")
            if not entry.is_dir():
                bundled_files.add(str(path))
        top_level = {name.split("/", 1)[0] for name in bundled_files}
        require(required_files <= bundled_files and models <= top_level, "Required resources are missing")
        unexpected = {name for name in bundled_files if name not in required_files | OPTIONAL and name.split("/")[0] not in models}
        require(not unexpected, f"Unexpected bundle resources: {unexpected}")
        require(all(f"{model}/metadata.json" in bundled_files for model in models), "Compiled model metadata is missing")
        require(archive.testzip() is None, "ZIP CRC check failed")
        metadata = plistlib.loads(archive.read(BUNDLE + "Info.plist"))
        require(metadata["CFBundleIdentifier"] == settings["PRODUCT_BUNDLE_IDENTIFIER"], "Wrong bundle ID")
        require(metadata["CFBundleShortVersionString"] == settings["MARKETING_VERSION"], "Wrong marketing version")
        require(metadata["CFBundleVersion"] == settings["CURRENT_PROJECT_VERSION"], "Wrong build number")
        require(ipa.name == f"ChessLens-v{metadata['CFBundleShortVersionString']}.ipa", "Wrong IPA filename")
        require(metadata["CFBundleExecutable"] == "ChessLens" and metadata["CFBundleSupportedPlatforms"] == ["iPhoneOS"], "Not an iPhone device app")
        require(metadata["CFBundlePackageType"] == "APPL" and metadata["UIDeviceFamily"] == [1], "Not an iPhone-only application bundle")
        require("NSAppTransportSecurity" not in metadata and "NSLocalNetworkUsageDescription" not in metadata, "Development networking is still enabled")
        permissions = {key: value for key, value in metadata.items() if key.endswith("UsageDescription")}
        if stockfish_only:
            require(not permissions, "Stockfish-only app must not request privacy permissions")
        else:
            require(set(permissions) == {"NSCameraUsageDescription"} and permissions["NSCameraUsageDescription"], "Unexpected or missing privacy permission")
        with archive.open(BUNDLE + NETWORK) as network:
            require(digest(network) == NETWORK_SHA256, "Stockfish evaluation network checksum mismatch")
        executable = archive.read(BUNDLE + "ChessLens")
        require(not SECRET.search(executable + archive.read(BUNDLE + "Info.plist")), "Possible secret embedded in executable or metadata")
        require(b"CHESSLENS_CONNECTION_TOKEN" not in executable and b"CHESSLENS_ENGINE_SELF_TEST" not in executable, "Development launch options are present")
        require(b"api.deepseek.com" not in executable, "A remote scan endpoint is still linked")
        require((archive.getinfo(BUNDLE + "ChessLens").external_attr >> 16) & stat.S_IXUSR, "Main executable has no execute permission")
        with tempfile.TemporaryDirectory(prefix="chesslens-ipa-check-") as temp:
            binary = Path(temp) / "ChessLens"
            binary.write_bytes(executable)
            arches = subprocess.check_output(["xcrun", "lipo", "-archs", binary], text=True).split()
            build = subprocess.check_output(["xcrun", "vtool", "-show-build", binary], text=True)
            require(arches == ["arm64"] and re.search(r"\bplatform\s+IOS\s", build), "Expected an arm64 iPhone Mach-O")
            minimum = re.search(r"\bminos\s+([\d.]+)", build)
            require(minimum and minimum[1] == metadata["MinimumOSVersion"], "Deployment target does not match the executable")
            commands = subprocess.check_output(["xcrun", "otool", "-l", binary], text=True)
            require("LC_CODE_SIGNATURE" not in commands, "Expected an unsigned IPA, with no signing data")
            if stockfish_only:
                libraries = subprocess.check_output(["xcrun", "otool", "-L", binary], text=True)
                require(not any(name in libraries for name in ("CoreML", "PhotosUI", "AVFoundation")), "Photo or recognition frameworks linked")
    with ipa.open("rb") as file:
        checksum = digest(file)
    return {
        "filename": ipa.name, "sha256": checksum, "size": ipa.stat().st_size,
        "bundleIdentifier": metadata["CFBundleIdentifier"], "version": metadata["CFBundleShortVersionString"],
        "build": metadata["CFBundleVersion"], "minimumIOS": metadata["MinimumOSVersion"],
        "architecture": arches[0], "edition": "stockfish" if stockfish_only else "camera-beta",
        "models": sorted(models), "appPermissions": {"entitlements": [], "privacy": permissions},
    }


def package(app, target, stockfish_only=False):
    require(app.is_dir(), "Xcode has not built ChessLens.app")
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".chesslens-package-", dir=target.parent) as temp:
        staged = Path(temp) / target.name
        with zipfile.ZipFile(staged, "w", zipfile.ZIP_DEFLATED, compresslevel=4) as archive:
            for path in sorted(app.rglob("*")):
                require(not path.is_symlink(), f"Symlink in built app: {path.name}")
                if path.is_file():
                    archive.write(path, BUNDLE + path.relative_to(app).as_posix())
        report = verify(staged, stockfish_only=stockfish_only)
        staged.replace(target)
        return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--from-app", type=Path, help="Package this device build first; otherwise only verify the IPA.")
    parser.add_argument("--stockfish-only", action="store_true", help="Require the model-free release bundle.")
    args = parser.parse_args()
    try:
        report = package(args.from_app, args.ipa, args.stockfish_only) if args.from_app else verify(args.ipa, args.stockfish_only)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        parser.exit(1, f"{error}\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
