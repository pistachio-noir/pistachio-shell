# Selected shell features — agreed scope

Owner approved building after the consolidated discussion on 11 November 2026. Existing Quickshell 0.3.2 services/UI separation, Theme palette, Reveal motion, no Hyprland configuration edits and owner-only commits remain binding.

## Captures
- Recording: setup → area/full screen → countdown → start. Remember system/mic/both/off and countdown (Off/3/5/10); initial system-only, microphone off, countdown off. Follow current Sound input. Pause/resume alongside Stop, elapsed excludes pauses. Escape cancels countdown.
- Trim: action on saved recording notification, start/end and save new file. Owner left question 2 blank; recommended notification action retained as implementer ruling.
- Screenshot Save/Copy/Both selection; Copy is strictly temporary, never saved under Pictures. Default Save, remember choice.

## Lens
- Up to three snips/image files with removable thumbnails, follow-ups reuse attached images. Existing single text-file attachment and Apply/Discard remain.
- Ask both produces ONE combined answer. Both provider responses saved; preferred provider synthesises them (third request). Only final, explicit diff Apply can edit the attached file. Existing provider model/effort and coding consent rules remain.

## Launcher, files and windows
- Pinned section above Frequent in main view; manual ordering and Pin/Unpin.
- Exact aliases for apps and shell actions ONLY, no folder or arbitrary command aliases.
- Space previews images/text/code/PDF first page (when backend available), unsupported files show metadata. Desktop and launcher, read-only.
- Open with for one invocation; changing MIME default requires explicit Remember.
- Background command jobs only: elapsed/output/Cancel/Run again, session history only.
- Launch feedback: pending and confirmed failures, no failure inferred merely from slow startup.
- Floating window menu: 1280×720, 960×600 and Centre, runtime compositor calls only.

## Settings and system
- Health in Settings: shell/helpers, optional dependencies, manual status/auth checks, redacted diagnostics, no paid model probe.
- Reset page: shell preferences ONLY, review before applying; no pairing, credentials or OS device state reset.
- Mic check: explicit start meter, 5-second sample and explicit Play; temporary audio, stop access on leaving.
- Bluetooth details read-only profile/codec/sample rate when available.
- Media player selection session only, Auto, temporary fallback if chosen player disappears.
- Wired IP/gateway/DNS details and Copy buttons; no network toggles.
- Failed eject explains app holders; return to app, never force-close.
- Hold-to-show 2× magnifier, wheel adjustment, no keyboard/pointer theft; README keybinds for owner to install.

## Deferred
- Preferences export/import #25 goes to Claude, later.
- Launcher multi-selection #18 later. All other later/ditched features untouched.

## Approach and rulings
Extend existing services and neighbouring controls rather than create a second settings/launcher architecture. Independent domains can be delegated with exclusive file ownership. Work in current checkout to retain live-shell path; no git mutation. User's explicit “talk first then build / let's build” is approval of this recorded scope; do not reopen the same decisions for process-only approval gates.
