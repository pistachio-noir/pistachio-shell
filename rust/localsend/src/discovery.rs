//! Finding devices: announcements on the multicast group, and asking every address on the network
//! when nobody answers them.

use std::net::{Ipv4Addr, SocketAddrV4, UdpSocket};
use std::os::fd::FromRawFd;
use std::sync::atomic::AtomicUsize;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use pistachio_lines::{emit, log};
use serde_json::{json, Value};

use crate::receive::Slot;
use crate::{lock, truthy, App, MULTICAST_PORT};

const GROUP: Ipv4Addr = Ipv4Addr::new(224, 0, 0, 167);

/// The socket the announcements come and go on. Its address is shared (SO_REUSEPORT), so a second
/// helper (the tests' pair, beside the shell's) hears them too.
pub fn open_multicast() -> std::io::Result<UdpSocket> {
    // SAFETY: plain socket calls on a descriptor that is ours alone; it's handed to UdpSocket,
    // which closes it, or closed here when a step fails
    let socket = unsafe {
        let fd = libc::socket(libc::AF_INET, libc::SOCK_DGRAM | libc::SOCK_CLOEXEC, libc::IPPROTO_UDP);
        if fd < 0 {
            return Err(std::io::Error::last_os_error());
        }
        let socket = UdpSocket::from_raw_fd(fd);
        let on: libc::c_int = 1;
        for option in [libc::SO_REUSEADDR, libc::SO_REUSEPORT] {
            if libc::setsockopt(fd, libc::SOL_SOCKET, option, (&on as *const libc::c_int).cast(), std::mem::size_of::<libc::c_int>() as libc::socklen_t) != 0 {
                return Err(std::io::Error::last_os_error());
            }
        }
        let mut address: libc::sockaddr_in = std::mem::zeroed();
        address.sin_family = libc::AF_INET as libc::sa_family_t;
        address.sin_port = MULTICAST_PORT.to_be();
        address.sin_addr.s_addr = libc::INADDR_ANY;
        if libc::bind(fd, (&address as *const libc::sockaddr_in).cast(), std::mem::size_of::<libc::sockaddr_in>() as libc::socklen_t) != 0 {
            return Err(std::io::Error::last_os_error());
        }
        socket
    };
    socket.join_multicast_v4(&GROUP, &Ipv4Addr::UNSPECIFIED)?;
    Ok(socket)
}

/// Tells the group about this device; with `flag` the others answer.
pub fn announce(app: &App, flag: bool) {
    let Some(udp) = &app.udp else { return };
    let mut message = app.info();
    message["announce"] = json!(flag);
    if let Err(e) = udp.send_to(message.to_string().as_bytes(), SocketAddrV4::new(GROUP, MULTICAST_PORT)) {
        log(&format!("can't announce: {e}"));
    }
}

/// Hears the group's announcements, for as long as the helper runs.
pub fn listen(app: &Arc<App>) {
    let Some(udp) = &app.udp else { return };
    let mut buffer = vec![0u8; 65535];
    let answering = Arc::new(AtomicUsize::new(0));
    loop {
        let Ok((length, from)) = udp.recv_from(&mut buffer) else {
            thread::sleep(Duration::from_millis(50)); // an error that stays must not spin
            continue;
        };
        let Ok(message) = serde_json::from_slice::<Value>(&buffer[..length]) else { continue };
        if !message.is_object() || message["fingerprint"] == app.fingerprint.as_str() {
            continue;
        }
        let ip = from.ip().to_string();
        app.seen(&message, &ip);
        // answer only while others may send here
        if truthy(&message["announce"]) && lock(&app.server).is_some() {
            // a few at a time: a flood of announcements must not start a thread each
            let Some(slot) = Slot::take(&answering, 8) else { continue };
            let (app, device) = (Arc::clone(app), App::device(&message, &ip));
            let _ = thread::Builder::new().spawn(move || {
                if app.call(&device, "/register", Some(&app.info()), &[], Duration::from_secs(3)).is_err() {
                    announce(&app, false);
                }
                drop(slot);
            });
        }
    }
}

/// This machine's address on the network: the one a packet to the outside would leave from.
fn own_address() -> Option<Ipv4Addr> {
    let socket = UdpSocket::bind("0.0.0.0:0").ok()?;
    socket.connect("10.255.255.255:1").ok()?; // sends nothing; picks the outgoing interface
    match socket.local_addr().ok()?.ip() {
        std::net::IpAddr::V4(ip) => Some(ip),
        _ => None,
    }
}

fn probe(app: &App, ip: &str) {
    let device = json!({"ip": ip, "port": MULTICAST_PORT, "protocol": "https"});
    if let Ok((200, body)) = app.call(&device, "/register", Some(&app.info()), &[], Duration::from_millis(1500)) {
        if let Ok(data) = serde_json::from_slice::<Value>(&body) {
            if data.is_object() {
                app.seen(&data, ip);
            }
        }
    }
}

/// Looks for devices afresh. `legacy`: when nobody answers the announcements, ask every address
/// on the network.
pub fn scan(app: &Arc<App>, legacy: bool) {
    lock(&app.devices).clear();
    emit(&json!({"event": "clear"}));
    emit(&json!({"event": "scan", "running": true}));
    for wait in [0, 1, 2] {
        thread::sleep(Duration::from_secs(wait));
        announce(app, true);
    }
    if legacy && lock(&app.devices).is_empty() {
        if let Some(own) = own_address() {
            let [a, b, c, _] = own.octets();
            let addresses: Vec<String> = (1..255).map(|i| Ipv4Addr::new(a, b, c, i)).filter(|ip| *ip != own).map(|ip| ip.to_string()).collect();
            let queue = Arc::new(Mutex::new(addresses));
            let askers: Vec<_> = (0..64)
                .map(|_| {
                    let (app, queue) = (Arc::clone(app), Arc::clone(&queue));
                    thread::spawn(move || loop {
                        let Some(ip) = lock(&queue).pop() else { return };
                        probe(&app, &ip);
                    })
                })
                .collect();
            for asker in askers {
                let _ = asker.join();
            }
        }
    }
    emit(&json!({"event": "scan", "running": false}));
}
