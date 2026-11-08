pragma Singleton

import Quickshell
import QtQuick

// Cider (Apple Music) beyond MPRIS (owner's picks, 8 November 2026): its queue for the media card's
// Up next, and Apple Music search for the launcher, through Cider's local API (port 10767). Cider
// wants an app token: made in Cider (Settings → Connectivity → Manage External Application Access)
// and pasted into the launcher's Shell settings; nothing is sent without one.
Singleton {
    id: root

    readonly property bool installed: Apps.list.some(a => a.id === "cider")
    readonly property string token: Store.saved.ciderToken ?? ""
    readonly property bool usable: installed && token !== ""
    property bool reachable // the last call got an answer
    property var queue: [] // after the current track: { index, name, artist, art }
    property var results: [] // { type, id, name, detail, art }
    property string searched
    property bool searching
    property string storefront: "us" // the account's country, asked once

    function art(url, size: int): string {
        return (url ?? "").replace("{w}", size).replace("{h}", size).replace("{f}", "jpg");
    }

    function call(method: string, path: string, body, then, withToken) {
        const r = new XMLHttpRequest();
        r.onreadystatechange = () => {
            if (r.readyState !== XMLHttpRequest.DONE)
                return;
            let data = null;
            try {
                data = JSON.parse(r.responseText);
            } catch (e) {}
            const ok = r.status >= 200 && r.status < 300 && !(data?.error);
            if (withToken === undefined)
                reachable = ok;
            then?.(ok, data);
        };
        r.open(method, "http://localhost:10767/api/v1" + path);
        r.setRequestHeader("apptoken", withToken ?? token);
        if (body)
            r.setRequestHeader("Content-Type", "application/json");
        r.send(body ? JSON.stringify(body) : null);
    }

    // for the Shell setting: does Cider take this token?
    function check(candidate: string, then) {
        call("GET", "/playback/active", null, (ok, d) => then(ok ? candidate : null, ok ? "" : "Cider didn't take it: is Cider open, and the token copied whole?"), candidate);
    }

    function setToken(t: string) {
        Store.saved.ciderToken = t;
        askStorefront();
    }

    function refreshQueue() {
        if (!usable)
            return;
        call("GET", "/playback/queue", null, (ok, d) => {
            if (!ok || !Array.isArray(d)) {
                queue = [];
                return;
            }
            const current = d.findIndex(i => i?._state?.current === 2);
            const next = d.map((i, n) => ({ index: n, name: i?.attributes?.name ?? "", artist: i?.attributes?.artistName ?? "", art: art(i?.attributes?.artwork?.url, 96) }))
                .slice(current + 1, current + 6).filter(i => i.name);
            if (JSON.stringify(next) !== JSON.stringify(queue)) // the same queue: keep the rows (and their covers) as they are
                queue = next;
        });
    }

    function refreshSoon() {
        later.restart();
    }

    function jump(index: int) {
        call("POST", "/playback/queue/change-to-index", { index: index }, () => later.restart());
    }

    function search(term: string) {
        term = term.trim();
        if (!usable || term === searched)
            return;
        searched = term;
        results = [];
        if (!term)
            return;
        searching = true;
        typing.restart();
    }

    // plays it now, next, or at the end of the queue ("now", "next", "later")
    function play(item, when: string) {
        call("POST", when === "now" ? "/playback/play-item" : when === "next" ? "/playback/play-next" : "/playback/play-later", { type: item.type, id: item.id }, () => later.restart());
    }

    function askStorefront() {
        if (usable)
            call("POST", "/amapi/run-v3", { path: "/v1/me/storefront" }, (ok, d) => {
                const id = d?.data?.data?.[0]?.id ?? d?.data?.[0]?.id;
                if (id)
                    storefront = id;
            });
    }

    Component.onCompleted: askStorefront()

    // the queue a moment after a change, as Cider updates it
    Timer {
        id: later
        interval: 600
        onTriggered: root.refreshQueue()
    }

    // a search once typing pauses
    Timer {
        id: typing
        interval: 300
        onTriggered: {
            const term = root.searched;
            root.call("POST", "/amapi/run-v3", { path: `/v1/catalog/${root.storefront}/search?term=${encodeURIComponent(term)}&types=songs,albums,playlists&limit=5` }, (ok, d) => {
                if (term !== root.searched)
                    return; // typed on meanwhile
                root.searching = false;
                const res = d?.data?.results ?? d?.results ?? {};
                const out = [];
                for (const [kind, label] of [["songs", "Song"], ["albums", "Album"], ["playlists", "Playlist"]])
                    for (const i of res[kind]?.data ?? [])
                        out.push({ type: i.type ?? kind, id: String(i.id), name: i.attributes?.name ?? "", detail: [label, i.attributes?.artistName ?? i.attributes?.curatorName ?? ""].filter(x => x).join(" · "), art: root.art(i.attributes?.artwork?.url, 96) });
                root.results = out;
            });
        }
    }
}
