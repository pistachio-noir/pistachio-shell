# Settings window proposal

10 November 2026. **Design review only; waiting for the owner's approval.**

Open `index.html` in a browser. Each of its 24 boards is a standalone HTML file; sidebar links, tabs and selected selectors navigate between the illustrated states. They do not control the machine. All sample devices, names, places, apps' readings and values are made up. Colours, shapes, typography and motion follow the Pistachio Noir UI design skill; palette tokens live in `settings.css`.

Proposed app: a normal movable settings window, 1040 × 760 on a 1280 × 900 artboard, with a persistent sidebar. Open it from the launcher and quick settings; a future `psc settings open` would expose it to keybinds. No new keybind or Hyprland config edit is part of this design pass.

The window holds the detailed controls currently spread through the launcher: appearance; brightness and night light; sound devices, microphones and app volumes; notification schedules, quiet contexts and app rules; Bluetooth devices and pairing; wired network status; LocalSend preferences; Lens providers, models, effort and fallback; terminal, weather location and Cider token; system readings and removable drives; About and showoff mode. It reuses the existing service responsibilities; the boards are not approval to implement new features.

The launcher proposal keeps output volume, brightness, Bluetooth, Night light, Do not disturb and a Settings entry. Existing app/window/workspace modes and power actions remain available. Quick settings keeps its everyday controls. Exact shortcuts can be settled after the design is approved.

Main decisions proposed for review:

- One persistent sidebar, with Personal / Connections / Shell groups.
- Immediate application for toggles and levels. Save / Cancel for text edits.
- Device/model/effort selectors open an anchored list; their open states have separate boards.
- Bluetooth pairing uses a centred confirmation dialog. Empty discovery and weather errors have dedicated boards.
- Wired network status only, matching this machine. No Wi-Fi or Ethernet disconnect control.
- Lens keeps independent provider settings, optional single-attempt fallback and automatic chat saving.
- A small global settings search, illustrated with results and no-results boards.

No files under `src/` are changed by this proposal. Implementation starts only after the owner approves the boards.
