// Connect after pairing, for services/Bluetooth.qml. Pairing alone brings up only the link, so
// headphones paired from the shell had no audio until a second click. `waiting` holds the addresses
// the shell paired; `devices` the adapter's devices ({ address, paired, connected }). Returns the
// addresses to connect now and the ones still waiting. A device that left the adapter is dropped.
function afterPairing(waiting, devices) {
    const connect = [], still = [];
    for (const address of waiting) {
        const device = devices.find(d => d.address.toUpperCase() === address.toUpperCase());
        if (!device)
            continue;
        if (!device.paired)
            still.push(address);
        else if (!device.connected)
            connect.push(device.address);
    }
    return { connect: connect, waiting: still };
}
