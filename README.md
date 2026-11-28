# kali-looks

Dress your normal Kali (Xfce) desktop as **macOS**, and pick **macOS Tahoe**, **Windows XP** or **Windows 7** at the login screen next to it. Each of those three is its own login session with its own settings, built on the most faithful replica that exists for it. Built on Kali Linux (Xfce 4.20, Plasma 6.7, X11).

```bash
git clone https://github.com/iiCiel/kali-looks.git
cd kali-looks
./looks.sh install          # puts the `looks` command in ~/.local/bin

looks setup xfce            # macOS for your normal Kali desktop (run it inside Xfce)
looks setup macos           # each takes a few minutes and asks for your password
looks setup winxp
looks setup win7            # compiles AeroThemePlasma the first time (10-30 min)
looks sessions              # puts them on the login screen
```

Then log out and choose a look from the login screen's session menu. It lists exactly four: **Xfce Session** (your own desktop, macOS for Xfce), **macOS Tahoe**, **Windows XP** and **Windows 7**. To change looks later, open **Switch Look** from any of them (or run `looks switch`): it logs you out with the next look preselected.

| macOS (Xfce) | macOS Tahoe | Windows XP | Windows 7 |
|---|---|---|---|
| ![macOS look for Xfce](looks/xfce/screenshots/desktop-light.jpg) | ![macOS Tahoe look](screenshots/macos.jpg) | ![Windows XP look](screenshots/winxp.jpg) | ![Windows 7 look](screenshots/win7.jpg) |

### Updating

```bash
cd kali-looks && git pull
looks setup macos           # again for each look whose folder (looks/<name>) changed
looks sessions              # login screen changes
```

Running a look's setup again installs it with the new changes; the macOS Tahoe Dock is compiled during `looks setup macos`, so Dock changes arrive that way. Changes to the shortcuts and the session hook (`lib/`) apply at your next login on their own.

## The looks

kali-looks doesn't draw its own imitation. It installs the best existing project for each look, at a pinned, tested version, into that look's session only.

| Look | Built on | What you get |
|---|---|---|
| **macOS (Xfce)** | [looks/xfce](looks/xfce) (formerly cupertino-xfce), with [WhiteSur](https://github.com/vinceliuice/WhiteSur-gtk-theme) by Vince Liuice and [Plank Reloaded](https://github.com/zquestz/plank-reloaded) | Your normal Kali desktop as macOS: global menu bar, Control Center, magnifying dock, Spotlight, Launchpad, Mission Control, light and dark mode, blur and rounded corners, Mac shortcuts, login screen and boot splash. It has no session of its own and installs into your own Xfce settings; `looks remove xfce` puts them back. Options and details: [looks/xfce/README.md](looks/xfce/README.md) |
| **macOS Tahoe** | [macOS Tahoe Shell for KDE](https://github.com/lestercorderomurillo/macos-tahoe-liquid-kde) by Lester Cordero Murillo and contributors | Menu bar with the app's own menus, Control Center, Liquid Glass dock with magnification, Launchpad, Spotlight-style search, SF Pro, Tahoe icons, cursors, sounds and wallpapers, rounded windows with traffic-light buttons. kali-looks adds what a real Tahoe Mac has on top: the menu bar on every screen with Battery, Wi-Fi, Spotlight, Control Center and the clock, Finder's full menu, light app colors, and the Tahoe wallpaper on the desktop and lock screen. The Dock works like a Mac's: every running app keeps its icon and a dot even with no window open (Discord or Steam closed to the menu bar), right-click → **Quit** ends the whole app, and your three most recent apps sit between the dividers |
| **Windows XP** | [XPlasma Plus](https://github.com/ergosteur/XPlasma-Plus), a fork of hotsocket's [XPlasma](https://tangled.org/hotsocket.fyi/xplasma) | Renders XP's real Luna visual style: Start menu, taskbar and tray, window borders, Qt and GTK controls, Tahoma, XP icons, pointers and sounds, Bliss, XP logout dialogs and lock screen |
| **Windows 7** | [AeroThemePlasma](https://github.com/aeroshell-desktop/aerothemeplasma) by the AeroShell project | Aero glass, Superbar, Start orb and menu, Aero Peek and Snap, Windows 7 frames, icons, cursors, sounds, Segoe UI |

Left out of the session looks on purpose, because they'd reach outside the look's own session: Firefox theming, login-screen themes (Kali uses LightDM) and boot splashes. The Xfce look does theme those, since it's your main desktop (skip them with `looks setup xfce --no-firefox --no-login --no-boot-splash`).

## Keyboard shortcuts

Each look gets its own system's keys. On a PC keyboard, ⌘ Cmd is the Windows key.

| | macOS Tahoe | Windows XP and Windows 7 |
|---|---|---|
| Screenshot tool | ⌘ Shift 5, or Print Screen | Win+Shift+S, or Print Screen |
| Whole screen | ⌘ Shift 3, or Shift+Print Screen | Shift+Print Screen |
| An area | ⌘ Shift 4, or Win+Shift+Print Screen | Win+Shift+Print Screen |
| Active window | Win+Print Screen | Win+Print Screen |
| See and end running apps | Ctrl+Esc (Activity Monitor) | Ctrl+Shift+Esc (Task Manager) |
| Close a window | Alt+F4 | Alt+F4 |
| Force quit (then click the window) | Win+Ctrl+Esc | Win+Ctrl+Esc |

The laptop's own keys work in every look too: volume, mute, mic mute, media and brightness, plus KDE's usual Alt+Tab, Show Desktop, window snapping and Lock (Win+L).

A look's setup leaves KDE's global shortcuts switched off, so kali-looks turns KDE's defaults back on once per look (and again after each `looks setup`), and fills in the keys above before every login. It skips a key another action already uses, and the macOS look keeps two off on purpose: the Windows key alone opens nothing, and Win+Q isn't KDE's Activities (⌘Q quits apps on a Mac). After that it only writes shortcuts that are missing or off, so one you change in System Settings stays yours. The Xfce look has its own Mac shortcuts ([looks/xfce/README.md](looks/xfce/README.md)).

If the brightness keys do nothing while Chrome Remote Desktop is installed, run `looks desktop-rights` (see below).

## Good to know

- **Which apps are running.** In macOS Tahoe, a dot under a Dock icon means the app is running; no dot means it's only pinned or recent. Apps that keep running with no window also show an icon at the right of the menu bar. Ctrl+Esc (Ctrl+Shift+Esc in the Windows looks) lists everything.
- **Closing a window isn't quitting.** Apps like Discord, Steam or Claude keep running in the background when you close their window. Quit them from the Dock (macOS Tahoe) or their menu-bar icon.
- **Apps reopening at login.** Plasma reopens whatever was still running when you logged out. To start every login empty: System Settings → Session → Desktop Session → *Start with an empty session*.
- **Main screen with several monitors.** System Settings → Display Configuration → **Change Screen Priorities…**, then drag the screen you want first (Plasma 6 has no "primary" checkbox).
- **Sleep when plugged in.** System Settings → Power Management → **On AC Power** → *Suspend session* (and *Turn off screen*). Screen Locking only sets when the lock screen comes on.
- **One wallpaper on every screen.** In macOS Tahoe, a wallpaper you pick on one screen goes on all of them, and every screen draws it again when screens are plugged in or reordered.

## How the sessions stay separate

- `~/.config` becomes a link. Your own settings (Xfce, and every app) live in `~/.local/share/kali-looks/config/base`; each look has its own folder next to it.
- A look's folder holds that look's desktop settings and links back to your own settings for everything else, so Firefox, Chrome, VS Code, Claude and the rest are the same in every session. App folders created while you're in a look move to your own settings automatically.
- A small hook in `~/.xsessionrc` points `~/.config` at the right folder before each session starts. Xfce gets exactly the folder it always had.
- The few desktop settings that live outside `~/.config` (the GTK 2 theme in `~/.gtkrc-2.0` and the default pointer) are swapped the same way, so a look's pointer never shows up in Xfce.
- Sessions that start without `~/.xsessionrc` (Plasma on Wayland, Xfce on Wayland, the plain Plasma session) are hidden from the login screen, since they'd run on whichever look's settings were used last, and so is LightDM's generic Default Xsession. `looks sessions remove` brings them back.
- The macOS Tahoe Dock learns which apps are running from the systemd unit Plasma starts each app in (`looks dock-apps list`), so it sees apps with no window too. An app started from a terminal has no such unit and only shows while it has a window.
- A remote desktop session (Chrome Remote Desktop) always uses your own settings and never moves `~/.config`.
- `looks setup` runs each look's installer inside a hidden session (its own X display and D-Bus), so your screen isn't touched while it installs.
- Every screen of a look, and its lock screen, gets the look's wallpaper, also a screen you plug in later (no Plasma "Next" or Kali blue). `looks wallpaper` fills in any screen that still shows it.
- Desktop portals (which tell apps light or dark, and open file dialogs) restart with each look's settings.
- `looks reset <look>` starts a look over from scratch (the old settings are kept in a backup). `looks sessions remove` turns `~/.config` back into a plain folder.

## With Chrome Remote Desktop installed

Chrome Remote Desktop starts its own desktop at boot, and the system then counts it, not the laptop, as your main session. Plasma's parts are judged by that session, so they act as if you weren't at the computer: the network icon and Turn Off ask for an admin password, and the brightness keys do nothing. `looks desktop-rights` installs a polkit rule that gives your user, in an active session, just those everyday rights back: turn off, restart and sleep; network and Wi-Fi; USB drives; screen brightness. `looks desktop-rights remove` takes it out.

## Fewer password prompts (optional)

`looks auth` installs a polkit rule: after you type your password once, admin prompts from your desktop are skipped for 30 minutes. It covers any `pkexec` prompt, not only kali-looks, so leave it off on a machine you share. The window only opens or extends when you type your password, never on its own, and it ends at reboot. `looks auth remove` takes it out.

## Windows 7: read this first

AeroThemePlasma is a deep modification of Plasma, not a theme:

- It's compiled from source and installs into `/usr`, including its **own build of `libplasma`** that replaces Kali's.
- When a Kali update upgrades Plasma, the Windows 7 session stops working until you run `looks rebuild win7`.
- `looks remove win7` deletes everything it installed and reinstalls the Kali packages it replaced.
- Segoe UI comes from your own Windows install if the computer has one (read-only); otherwise Microsoft's open-licence stand-in, Selawik.
- The wallpaper is an original Aero-style one. To use another, save it as `~/.local/share/kali-looks/win7-wallpaper.jpg` and run `looks setup win7`.

## Credits and licences

kali-looks itself is MIT, including looks/xfce and its wallpapers, boot splash, dock themes and Control Center. The projects it installs keep their own licences and credits:
- WhiteSur GTK and Firefox themes: MIT; WhiteSur icons and cursors: GPL-3.0; Plank Reloaded: GPL-3.0 / LGPL-2.1 (more in [looks/xfce/README.md](looks/xfce/README.md#credits))
- macOS Tahoe Shell for KDE: GPL-3.0
- XPlasma Plus / XPlasma: GPL-3.0. Its XP artwork, fonts and sounds are Microsoft's and are downloaded from XPlasma Plus' release, not from this repository.
- AeroThemePlasma: AGPL-3.0
- Selawik: SIL Open Font License

macOS and Windows are trademarks of Apple and Microsoft. This project isn't affiliated with either.
