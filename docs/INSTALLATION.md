# Install ChessLens with AltStore Classic

Use the verified `ChessLens-v1.0.0.ipa` from the [official GitHub Releases page](https://github.com/Eman-ej/ChessLens/releases) when available. Tapping a GitHub download does not install the app.

**What you need:** An iPhone running iOS 17 or later, an Apple Account, a Mac or Windows PC for AltServer, and a cable for initial setup. Choose **AltStore Classic**, not AltStore PAL. Use the official AltStore setup guides for [Mac](https://faq.altstore.io/altstore-classic/how-to-install-altstore-macos) or [Windows](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows).

1. Run AltServer on your computer. Connect and unlock the iPhone, trust the computer if asked, and follow the guide to install AltStore Classic on your iPhone with your Apple Account. Enable Wi‑Fi syncing if you want to refresh without the cable.
2. If prompted, trust your developer profile under **Settings → General → VPN & Device Management**. Enable **Settings → Privacy & Security → Developer Mode** and restart and confirm when asked.
3. On your iPhone, download the `.ipa` from the ChessLens GitHub Release into **Files**. Open **AltStore → My Apps**, tap **+**, and select the `.ipa`. Keep AltServer running. Keep the devices on the same local Wi‑Fi network, or use the cable.
4. Open ChessLens from your Home Screen. Choose **Try a sample position**, then **Find best move**. To analyze your own game, edit the board and set the side to move, or load a complete FEN under **Import or copy FEN**. The Stockfish edition does not scan photos.
5. Before the seven days are up, open **AltStore → My Apps → Refresh All** with AltServer reachable. Signing and refreshing require connectivity; analyzing a position in ChessLens does not.

Apple's [Personal Team rules](https://developer.apple.com/support/compare-memberships/) describe a limit of 10 registered App IDs, 3 provisioned devices, and 3 installed apps per device, with seven-day expiry for the free provisioning. AltStore Classic normally takes one of the three app slots. See [AltStore's free signing and refresh notes](https://faq.altstore.io/altstore-classic/your-altstore).

## If something goes wrong

| Symptom | What to do |
| --- | --- |
| AltStore can't find AltServer | Run AltServer and use the same local Wi‑Fi or a USB cable. Unlock the iPhone and check the trust prompt. Check the [official troubleshooting guide](https://faq.altstore.io/altstore-classic/troubleshooting-guide) for Wi‑Fi sync, firewall and network settings. |
| App has expired or won't open | Refresh with AltServer. If AltStore itself expired, reinstall AltStore Classic from AltServer using the same Apple Account, then refresh or reinstall ChessLens. |
| Too many apps or App IDs | Free a slot using AltStore's [deactivate feature](https://faq.altstore.io/altstore-classic/activating-apps), or wait for old App IDs to expire. Deleting an app doesn't immediately free its App ID. |
| File doesn't install | Confirm you're on iOS 17 or newer and have the original `.ipa` in Files, not an extracted folder. Verify the SHA‑256 against the published release notes; re-download if it differs. |
| Stockfish can't analyze an edited position | Make sure there is one king per side and check whose turn it is, castling rights, and en passant. Try **Try a sample position** to check the engine. |
