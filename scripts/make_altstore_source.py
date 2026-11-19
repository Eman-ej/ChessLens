#!/usr/bin/env python3
"""Generate an AltStore Classic source only after its public assets can be verified."""

import argparse
from datetime import date
import json
from pathlib import Path
import re
import tempfile
from urllib.parse import urlsplit
from urllib.request import urlopen

from package_distribution import digest, require, verify


def check_urls(asset, site, icon, package):
    for url in (asset, site, icon):
        parsed = urlsplit(url)
        require(parsed.scheme == "https" and parsed.hostname and not parsed.username and not parsed.password, "Use public HTTPS URLs")
    expected = rf"/[\w-]+/[\w.-]+/releases/download/v{re.escape(package['version'])}/{re.escape(package['filename'])}"
    release = urlsplit(asset)
    require(release.netloc == "github.com" and not release.query and not release.fragment and re.fullmatch(expected, release.path),
            "Use the direct GitHub Release asset URL, with the matching v-prefixed tag and IPA filename")
    with urlopen(asset, timeout=45) as response:
        require(urlsplit(response.url).scheme == "https", "The IPA download redirected away from HTTPS")
        require(digest(response) == package["sha256"], "Public IPA does not match the verified local IPA")
    with urlopen(icon, timeout=30) as response:
        require(urlsplit(response.url).scheme == "https" and response.read(8) == b"\x89PNG\r\n\x1a\n", "The public icon is not a PNG")


def source_for(package, options, history):
    bundle = package["bundleIdentifier"]
    stockfish_only = package["edition"] == "stockfish"
    record = {
        "version": package["version"], "buildVersion": package["build"],
        "date": options.release_date.isoformat(), "localizedDescription": options.notes,
        "downloadURL": options.asset, "size": package["size"], "minOSVersion": package["minimumIOS"],
    }
    return {
        "name": "ChessLens", "subtitle": "Offline chess analysis" if stockfish_only else "Chessboard scanning and analysis", "website": options.site,
        "iconURL": options.icon, "featuredApps": [bundle], "news": [],
        "apps": [{
            "name": "ChessLens", "bundleIdentifier": bundle, "developerName": options.developer,
            "subtitle": "Find your next move." if stockfish_only else "Scan a board. Find your next move.",
            "localizedDescription": (
                "Set up a position or paste a FEN, play legal moves, and analyze with Stockfish 19 on your iPhone. No camera or account required."
                if stockfish_only else "Scan a physical chessboard, review the position, and find a move with on-device Stockfish. No ChessLens account or photo uploads."
            ),
            "iconURL": options.icon, "category": "games", "appPermissions": package["appPermissions"],
            "versions": [record, *[version for version in history if version["version"] != record["version"]]],
        }],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--asset", required=True, help="Direct, public GitHub Release IPA URL.")
    parser.add_argument("--icon", required=True, help="Public HTTPS PNG URL.")
    parser.add_argument("--site", required=True, help="Public ChessLens site URL.")
    parser.add_argument("--developer", required=True, help="Public name to display in AltStore.")
    parser.add_argument("--release-date", required=True, type=date.fromisoformat)
    parser.add_argument("--notes", required=True)
    parser.add_argument("--stockfish-only", action="store_true", help="Require the model-free release bundle.")
    options = parser.parse_args()
    try:
        package = verify(options.ipa, stockfish_only=options.stockfish_only)
        history = []
        if options.output.exists():
            old_apps = json.loads(options.output.read_text())["apps"]
            require(len(old_apps) == 1 and old_apps[0]["bundleIdentifier"] == package["bundleIdentifier"], "Refusing to overwrite a different AltStore source")
            history = old_apps[0]["versions"]
        check_urls(options.asset, options.site, options.icon, package)
        payload = source_for(package, options, history)
        options.output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix=".chesslens-source-", dir=options.output.parent) as temp:
            draft = Path(temp) / "source.json"
            draft.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
            draft.replace(options.output)
    except (KeyError, ValueError, OSError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
