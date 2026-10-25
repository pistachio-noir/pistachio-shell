import Quickshell.Hyprland

// Part of the compositor adapter: while `active`, the listed windows keep input and a click anywhere
// else emits cleared(). UI files use this to close panels, so they never import a compositor module.
HyprlandFocusGrab {}
