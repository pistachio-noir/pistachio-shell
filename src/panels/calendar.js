.pragma library

// The calendar's month grid: always six weeks from a Monday, so the panel keeps its height.
// days(2026, 9) → 42 Dates, Monday 28 September to Sunday 8 November 2026 (months count from 0).
function days(year, month) {
    const before = (new Date(year, month, 1).getDay() + 6) % 7; // days of the week before the 1st
    const out = [];
    for (let i = 0; i < 42; i++)
        out.push(new Date(year, month, 1 - before + i));
    return out;
}

// the month `by` months away: shift(2026, 11, 1) → { year: 2027, month: 0 }
function shift(year, month, by) {
    const d = new Date(year, month + by, 1);
    return { year: d.getFullYear(), month: d.getMonth() };
}

function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}
