const fs = require("fs"), path = require("path"), assert = require("assert");
const { place } = new Function(fs.readFileSync(path.join(__dirname, "../src/popups/recording.js"), "utf8") + "\nreturn {place};")();
function overlaps(a, b) {
    return a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y;
}
const width = 1920, height = 1080, pillWidth = 240, pillHeight = 44;
for (const area of [
    {x:400,y:300,width:640,height:360},
    {x:400,y:0,width:640,height:360},
    {x:400,y:720,width:640,height:360},
    {x:0,y:0,width:640,height:1080},
    {x:1280,y:0,width:640,height:1080},
    {x:0,y:0,width:1920,height:1000},
    {x:0,y:80,width:1920,height:1000}
]) {
    const point = place(area, width, height, pillWidth, pillHeight);
    assert(point, JSON.stringify(area));
    const pill = {...point,width:pillWidth,height:pillHeight};
    assert(!overlaps(area,pill), JSON.stringify({area,pill}));
    assert(pill.x>=8 && pill.y>=8 && pill.x+pill.width<=width-8 && pill.y+pill.height<=height-8);
}
assert.strictEqual(place({x:0,y:0,width,height},width,height,pillWidth,pillHeight),null);
assert.strictEqual(place({x:10,y:10,width:1900,height:1060},width,height,pillWidth,pillHeight),null);
assert.strictEqual(place({x:0,y:0,width:50,height:50},100,100,pillWidth,pillHeight),null);
console.log("recording placement: all passed");
