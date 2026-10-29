#  AWDL Control

Apple Wireless Direct Link (AWDL) is a technology built in to macOS and iOS that supports AirDrop and Continuity features.

AWDL can cause network lag spikes when playing online multiplayer games or when game streaming over WiFi. These spikes can be caused by background activity on your Mac, or they can even be caused by other nearby Apple devices!

AWDL Control is a Mac app that automatically disables AWDL while you are playing a game or mirroring a Chrome tab or desktop to Chromecast over WiFi. It brings AWDL back up when neither activity needs it. This preserves the useful Apple ecosystem functionality that AWDL provides, while preventing AWDL-related network lag spikes during games and casting.

## System Requirements

macOS 13.0 or higher.

## Downloads

[Download Latest Release](https://github.com/james-howard/AWDLControl/releases/latest/download/AWDLControl.zip)

## Installation

1. Drag AWDLControl.app to your Mac's Applications folder.
2. Launch AWDLControl.app and click on the "Register Helper" button to install.
    * macOS will prompt you for Admin authorization to install the helper.
3. (Optional) Configure AWDL Control to start at login time so it will always be running.

## How to Use

Once AWDL Control is installed and its helper is registered, it lives in your Mac menu bar.

AWDL Control has 3 modes:

* Automatic (Games & Chromecast)
    - AWDL will be disabled when on WiFi and you are actively playing a game or casting a tab/desktop from Google Chrome to Chromecast.
    - Casting stays protected when you switch to another application. AWDL is restored after casting stops, unless a game is still active.
* AWDL On
    - Allow AWDL connections. This is the stock / out of the box Mac setting.
* AWDL Off
    - Suppress AWDL connections at all times. Useful if the app you're using is network latency sensitive, but isn't identifiable as a game.

### Chromecast

Select **Automatic (Games & Chromecast)**, then start casting a tab or your screen from Google Chrome. Within a few seconds, the menu should show **Active for Chromecast**. Stop casting in Chrome to restore AWDL automatically. Existing Game Mode settings carry over to Automatic.

Detection supports Google Chrome (including Beta, Dev, and Canary) and Chromium. It detects Chrome's mirroring service, not simply an open browser or a nearby Chromecast. Playback that runs directly on the receiver (for example, a website handing a video URL to the TV) may not launch this service and is not detected. Other sender apps are not covered; use **AWDL Off** if needed, then return to Automatic afterwards.

AirDrop and AWDL-dependent Continuity features are unavailable while AWDL is disabled. **AWDL On** always overrides automatic detection. This addresses AWDL-related interference; it does not fix every possible cause of casting lag.

## Uninstallation

1. If AWDL Control is running, click the AWDL Control menu bar icon and select "Quit".
2. Drag AWDLControl.app from Applications to the Trash.
3. There is no step 3. Yes, everything is totally gone including the helper!

## Pro Tips

### Hide the menu bar item but leave the app running

By default, if you remove the AWDL Control menu bar item, either by holding the Command key
and dragging it out of the menu bar or using the macOS System Settings "Menu Bar" panel,
AWDL Control will quit. This is by design so that the software is not inadvertently left
suppressing AWDL without any visible indication.

If you're a pro and won't forget that you have it running, hold the Option key and
click the AWDL Control menu bar item and you will see the normally hidden 
"Hide AWDL Control" menu item. This hides AWDL Control, but leaves it running in whatever
mode it is in. To bring it back to the menu bar, double click the AWDL Control app
from the Finder.

## Feedback

Please report bugs here on GitHub.

Please send fan mail to jameshoward@mac.com

## Technical Notes

In older versions of macOS, running the following command in the Terminal could reliably disable AWDL:

```
sudo ifconfig awdl0 down
```

In recent macOS, the system will automatically bring the `awdl0` interface back up, which limits the effectiveness of that command.

AWDL Control efficiently automates keeping the `awdl0` interface down by monitoring network route changes and immediately bringing the interface back down if some other system component tries to bring it back up. Hat tip to [awdlkiller](https://github.com/jamestut/awdlkiller) by James Nugraha, which is a command line tool that originally implemented this idea!

### Helper Service

The AWDL Control Helper is a new style bundled LaunchDaemon, registered with [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice/daemon(plistname:)?language=objc). The big advantage of this compared to old style LaunchDaemons is the daemon and its launchd plist are part of the app bundle. This means the app can be relocated without issue, and uninstallation is as simple as dragging the app to the Trash without worrying about any orphaned plists or programs cluttering up the filesystem or, worse, still running in the background.

The helper daemon is necessary because elevated privileges are required to bring network interfaces up or down.

The helper only runs when the main AWDL Control application with the user interface is also running. When you quit AWDL Control, the daemon brings `awdl0` back up, and exits itself. This means there is never any hidden background software running on your computer that you can't see. We just need the daemon for the elevated privileges.

The helper is intentionally as simple as possible to limit the risk of running code with elevated privileges. All it can do is bring `awdl0` up or hold it down. The rest of the app logic runs in the UI process.

### Game Mode

AWDL Control uses approximately the same mechanism as macOS does to determine when to activate Game Mode. This means when the active application's Info.plist contains either:

* `LSApplicationCategoryType = "public.app-category.games"`
* `LSSupportsGameMode = true`

### Chromecast Detection

Chrome launches a dedicated utility process for Cast mirroring and keeps it alive for the session (see Chromium's [CastMirroringServiceHost](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/chrome/browser/media/cast_mirroring_service_host.cc)). AWDL Control checks for that service in the current user's running Chrome instances, independently of the foreground application. The detector runs in the unprivileged UI application; the helper and its interface are unchanged.

This deliberately avoids treating Cast discovery or an idle TCP connection as an active stream. It does not read browser pages, capture packets, or contact receivers. The process marker is a Chromium implementation detail, so future Chrome changes may require an update. If inspection fails, the detector reports no casting; **AWDL Off** remains the manual fallback.

See [Tests/README.md](Tests/README.md) for automated checks and the hardware verification procedure.

## Dear Apple

I have an open feedback with you about the issue this app addresses.

* FB22389467 - AWDL Channel Hopping can cause latency spikes
* FB13512447 - WiFi background scans cause latency spikes

Expanding macOS's Game Mode to limit any activity on the WiFi interface that can cause latency spikes would be a significant enhancement and would improve the viability of multiplayer gaming and game streaming on the Mac. AWDL is one culprit, but CoreLocation is also another major offender when doing WiFi scans for location in the background (e.g. for Calendar appointments with locations), as are WiFi scans for AP roaming. Game Mode already has a feature to reduce Gamepad latency over the Bluetooth radio, so it fits in well to consider what you can do to limit WiFi interruptions in games.

Nothing would make me happier than to see Apple address this issue in macOS itself.

## Alternatives to AWDL Control

Look, I get it, nobody wants to install yet another utility, especially with a privileged helper, just to manage a shortcoming of macOS. Here are a couple of other ideas.

* Run an Ethernet cable to your Mac. You're going to read this and not do it because complaining about lag is easier than physically moving your computer or drilling holes in your walls, but if you're serious about competitive games, you need Ethernet.
* Set your 5GHz WiFi channel at your router to 149 (in the US) or 44 (in the EU). I'm not sure about other regions. This can reduce lag due to wireless channel hopping performed by AWDL. 
