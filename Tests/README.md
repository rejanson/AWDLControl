# Verification

Run `./Tests/run-tests.sh` on macOS with Xcode Command Line Tools or Xcode installed. The tests compile into a temporary directory and do not register the privileged helper or change network interfaces. They cover process detection and the automatic-mode decisions using a fake helper connection.

CI also builds and runs Clang static analysis on the full app/helper with Xcode 26.2, without signing. This checks packaging and Interface Builder compilation, but cannot validate the privileged helper at runtime.

## Hardware checks

Use a normally signed/installed app with its helper registered, a Mac on WiFi, Chrome, and a Chromecast. Builds signed with another identity cannot connect to the upstream helper without a corresponding development signing configuration; do not remove the helper's code-signing requirement.

1. In Automatic, leave Chrome open without casting (including the Cast discovery menu). AWDL should remain available unless a game is active.
2. Cast a tab, then repeat with desktop casting. Within a few seconds the menu should show **Active for Chromecast** and AWDL should be suppressed. Switch to Finder; protection should continue.
3. Stop casting, close the casting tab, or quit Chrome. AWDL should become available within a few seconds when no game is active.
4. During casting, select **AWDL On** and **AWDL Off**. Each manual selection must win. Return to Automatic and confirm detection resumes.
5. Start/stop a game during casting. Stopping either activity must not restore AWDL while the other still qualifies.
6. Switch to Ethernet/disconnect WiFi, then reconnect. Automatic mode should release AWDL off WiFi and reevaluate casting on return. Repeat across sleep/wake.
7. Confirm AirDrop works after casting ends and that quitting AWDL Control restores AWDL through the existing helper teardown.
8. Compare the same cast with Automatic and AWDL On on the affected network. Record Chrome/macOS versions, casting type, network setup, and observed stalls/latency. Detection tests alone do not establish a performance improvement.

Receiver-side playback without Chrome's mirroring process, senders other than Chrome/Chromium, and activity belonging to another macOS user are outside automatic detection.
