import qs.services
import Quickshell
import Quickshell.Io
import QtQuick

// Test shell for tests/*.sh: exposes the real services over IPC.
Scope {
    // start every service now: they fill in (or finish their checks) a moment after first use
    // (Notifs also registers as the notification daemon if the bus name is free)
    Component.onCompleted: [Compositor.windows, Network.connected, Bluetooth.enabled, Brightness.available, NightLight.available, Notifs.dnd, Apps.list]

    IpcHandler {
        target: "compositor"

        function state(): string {
            return JSON.stringify({
                active: Compositor.workspaces.filter(w => w.active).map(w => w.id),
                workspaces: Compositor.workspaces,
                windows: Compositor.windows,
                bounds: Compositor.windowBounds.map(r => [r.x, r.y, r.width, r.height]),
                focused: Compositor.focusedWindow?.appId ?? null
            });
        }
        function goto(id: int): void { Compositor.goto(id); }
        function focus(address: string): void { Compositor.focus(address); }
        function moveWindow(address: string, ws: int): void { Compositor.moveWindow(address, ws); }
        function sendWindow(address: string, ws: int): void { Compositor.sendWindow(address, ws); }
        function toggleFloating(address: string): void { Compositor.toggleFloating(address); }
        function close(address: string): void { Compositor.close(address); }
    }

    IpcHandler {
        target: "services"

        function state(): string {
            return JSON.stringify({
                volume: Audio.volume,
                muted: Audio.muted,
                bluetooth: Bluetooth.enabled,
                agent: Bluetooth.agent,
                ethernet: Network.connected,
                speed: Network.speed,
                brightness: Brightness.value,
                brightnessAvailable: Brightness.available,
                nightLight: NightLight.enabled,
                nightLightAvailable: NightLight.available,
                temperature: NightLight.temperature,
                nightSchedule: NightLight.scheduled,
                inSchedule: NightLight.inSchedule,
                dnd: Notifs.dnd,
                dndScheduled: Notifs.dndScheduled,
                inDndSchedule: Notifs.inDndSchedule,
                uptime: Uptime.seconds,
                streams: Audio.streams.map(n => Audio.appName(n)),
                micVolume: Audio.micVolume,
                micMuted: Audio.micMuted,
                sources: Audio.sources.map(n => n.name),
                unplugged: Audio.unplugged,
                recorders: Audio.recorders.map(n => Audio.appName(n)),
                screen: ScreenShare.apps,
                cpu: SystemStats.cpu,
                memTotal: SystemStats.memTotal,
                memUsed: SystemStats.memUsed,
                gpuFound: SystemStats.gpuFound,
                lensProvider: ShellSettings.lensProvider,
                lensClaudeModel: ShellSettings.lensClaudeModel,
                lensClaudeEffort: ShellSettings.lensClaudeEffort,
                lensCodexModel: ShellSettings.lensCodexModel,
                lensCodexEffort: ShellSettings.lensCodexEffort,
                lensClaudeFallback: ShellSettings.lensClaudeFallback,
                lensCodexFallback: ShellSettings.lensCodexFallback,
                disks: SystemStats.disks
            });
        }
        function setVolume(v: real): void { Audio.setVolume(v); }
        function setLensChoice(key: string, value: string): void { ShellSettings.setLensChoice(key, value); }
        function setLensFallback(provider: string, on: bool): void { ShellSettings.setLensFallback(provider, on); }
        function setMicVolume(v: real): void { Audio.setMicVolume(v); }
        function toggleMicMute(): void { Audio.toggleMicMute(); }
        function setStatsWatching(on: bool): void { SystemStats.setWatching(on); }
        // a made-up reading (a line of services/stats.sh), and a heat that started `ms` ago, for the warnings
        function parseStats(line: string): void { SystemStats.parse(line); }
        function backdateHeat(key: string, ms: int): void { SystemStats.hotSince = Object.assign({}, SystemStats.hotSince, { [key]: Date.now() - ms }); }
        function setBluetooth(on: bool): void { Bluetooth.setEnabled(on); }
        function setBrightness(v: real): void { Brightness.set(v); }
        function setNightLight(on: bool): void { NightLight.setEnabled(on); }
        function setTemperature(k: int): void { NightLight.setTemperature(k); }
        function setNightSchedule(on: bool, from: int, to: int): void { NightLight.setSchedule(on, from, to); }
        function setDnd(on: bool): void { Notifs.setDnd(on); }
        function setDndSchedule(on: bool): void { Notifs.setDndSchedule(on); }
        function setDndFollowsNight(on: bool): void { Notifs.setDndFollowsNight(on); }
        function setDndTimes(from: int, to: int): void { Notifs.setDndTimes(from, to); }
        function sinks(): string { return JSON.stringify(Audio.sinks.map(n => n.name)); }
        function setSink(name: string): void {
            const node = Audio.sinks.find(n => n.name === name);
            if (node)
                Audio.setSink(node);
        }
        // per-app volume, by app name
        function setStreamVolume(app: string, v: real): void {
            const node = Audio.streams.find(n => Audio.appName(n) === app);
            if (node)
                Audio.setStreamVolume(node, v);
        }
        function toggleStreamMute(app: string): void {
            const node = Audio.streams.find(n => Audio.appName(n) === app);
            if (node)
                Audio.toggleStreamMute(node);
        }
        // the id of an installed app that runs in a terminal, or ""
        function terminalApp(): string { return Apps.list.find(a => a.runInTerminal)?.id ?? ""; }
        function launch(id: string): void {
            const app = Apps.list.find(a => a.id === id);
            if (app)
                Apps.launch(app);
        }
    }

    IpcHandler {
        target: "notifs"

        function state(): string {
            return JSON.stringify({
                summaries: Notifs.notifications.map(n => n.summary),
                popups: Notifs.popups.map(n => n.summary),
                counts: Notifs.popups.map(n => Notifs.popupCounts[n.id] ?? 1), // how many each toast stands for
                unread: Notifs.unread,
                dnd: Notifs.dnd
            });
        }
        function setDnd(on: bool): void { Notifs.setDnd(on); }
        function markSeen(): void { Notifs.markSeen(); }
        function clearAll(): void { Notifs.clearAll(); }
    }
}
