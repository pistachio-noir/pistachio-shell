// Keep the entire control outside both the capture and the screen edges.
function place(area, screenWidth, screenHeight, pillWidth, pillHeight) {
    const margin = 8, gap = 8;
    if (pillWidth > screenWidth - margin * 2 || pillHeight > screenHeight - margin * 2)
        return null;
    const x = Math.round(Math.max(margin, Math.min(screenWidth - pillWidth - margin, area.x + (area.width - pillWidth) / 2)));
    const y = Math.round(Math.max(margin, Math.min(screenHeight - pillHeight - margin, area.y + (area.height - pillHeight) / 2)));
    const candidates = [
        { x: x, y: area.y - gap - pillHeight },
        { x: x, y: area.y + area.height + gap },
        { x: area.x + area.width + gap, y: y },
        { x: area.x - gap - pillWidth, y: y }
    ];
    return candidates.find(p => p.x >= margin && p.y >= margin
        && p.x + pillWidth <= screenWidth - margin && p.y + pillHeight <= screenHeight - margin) || null;
}
