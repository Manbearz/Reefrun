import fs from "fs"
import path from "path"
import { PNG } from "pngjs"
import { fileURLToPath } from "url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const srcPath = path.join(root, "assets", "sprites", "main_daily_missions.png")
const outPath = path.join(root, "assets", "sprites", "main_daily_missions_board.png")
const src = PNG.sync.read(fs.readFileSync(srcPath))
const { width: W, height: H, data } = src
const original = Buffer.from(data)
const mask = new Uint8Array(W * H)

function at(x, y) {
	const i = (y * W + x) * 4
	return [data[i], data[i + 1], data[i + 2], data[i + 3]]
}

function setPix(x, y, c) {
	const i = (y * W + x) * 4
	data[i] = c[0]
	data[i + 1] = c[1]
	data[i + 2] = c[2]
	data[i + 3] = 255
}

function mark(x, y) {
	if (x < 0 || y < 0 || x >= W || y >= H) return
	mask[y * W + x] = 1
}

function rimScore(cx, cy, r) {
	let bright = 0
	const steps = 90
	for (let i = 0; i < steps; i++) {
		const a = (i / steps) * Math.PI * 2
		const x = Math.round(cx + Math.cos(a) * r)
		const y = Math.round(cy + Math.sin(a) * r)
		const p = at(x, y)
		if (p[2] > 200 && p[1] > 130 && p[0] < 190) bright++
	}
	return bright
}

function bestCircle(y0, y1) {
	let best = { s: -1, cx: 0, cy: 0, r: 0 }
	for (let cy = y0; cy <= y1; cy += 2) {
		for (let cx = 145; cx <= 195; cx += 2) {
			for (let r = 52; r <= 68; r += 2) {
				const s = rimScore(cx, cy, r)
				if (s > best.s) best = { s, cx, cy, r }
			}
		}
	}
	return best
}

function isCardBlue(p) {
	const lum = (p[0] + p[1] + p[2]) / 3
	return p[2] > 80 && p[2] > p[0] + 30 && p[2] > p[1] && p[0] < 70 && p[1] < 140 && lum > 55 && lum < 155
}

function isGreen(p) {
	return p[1] > 110 && p[1] > p[0] + 15 && p[1] > p[2] - 10 && p[2] < 190 && p[0] < 230
}

function isGold(p) {
	return p[0] > 130 && p[0] > p[2] + 35 && p[1] > 50 && p[2] < 170
}

function isPaper(p) {
	const lum = (p[0] + p[1] + p[2]) / 3
	return lum > 168 && p[2] > 120
}

function isDark(p) {
	return (p[0] + p[1] + p[2]) / 3 < 88
}

function dilateDark(x0, y0, x1, y1, rounds) {
	for (let n = 0; n < rounds; n++) {
		const add = []
		for (let y = y0; y < y1; y++) {
			for (let x = x0; x < x1; x++) {
				if (mask[y * W + x]) continue
				const p = at(x, y)
				if (!isDark(p)) continue
				let touch = false
				for (let dy = -1; dy <= 1 && !touch; dy++) {
					for (let dx = -1; dx <= 1; dx++) {
						const nx = x + dx
						const ny = y + dy
						if (nx < x0 || ny < y0 || nx >= x1 || ny >= y1) continue
						if (mask[ny * W + nx]) touch = true
					}
				}
				if (touch) add.push([x, y])
			}
		}
		for (const [x, y] of add) mark(x, y)
	}
}

const circles = [
	bestCircle(700, 800),
	bestCircle(860, 960),
	bestCircle(1020, 1120),
]
console.log("circles", circles)

function fillDisk(cx, cy, inner, ring0, ring1) {
	let sr = 0
	let sg = 0
	let sb = 0
	let n = 0
	for (let y = Math.round(cy - ring1); y <= cy + ring1; y++) {
		for (let x = Math.round(cx - ring1); x <= cx + ring1; x++) {
			const dist = Math.hypot(x - cx, y - cy)
			if (dist < ring0 || dist > ring1) continue
			const p = at(x, y)
			if (!isCardBlue(p)) continue
			sr += p[0]
			sg += p[1]
			sb += p[2]
			n++
		}
	}
	if (n < 8) {
		console.log("disk skipped", cx, cy, n)
		return
	}
	const color = [Math.round(sr / n), Math.round(sg / n), Math.round(sb / n)]
	for (let y = Math.round(cy - inner); y <= cy + inner; y++) {
		for (let x = Math.round(cx - inner); x <= cx + inner; x++) {
			if (Math.hypot(x - cx, y - cy) <= inner) setPix(x, y, color)
		}
	}
	console.log("disk", cx, cy, "inner", inner, "color", color, "samples", n)
}

function rowFill(x0, y0, x1, y1) {
	const lefts = []
	const rights = []
	for (let y = y0; y < y1; y++) {
		let left = null
		for (let x = x0 - 1; x >= x0 - 36; x--) {
			const p = at(x, y)
			if (isCardBlue(p)) {
				left = p
				break
			}
		}
		let right = null
		for (let x = x1; x < x1 + 36; x++) {
			const p = at(x, y)
			if (isCardBlue(p)) {
				right = p
				break
			}
		}
		lefts.push(left)
		rights.push(right)
	}
	const blur = (samples, index) => {
		let sr = 0
		let sg = 0
		let sb = 0
		let n = 0
		for (let k = index - 4; k <= index + 4; k++) {
			if (k < 0 || k >= samples.length || !samples[k]) continue
			sr += samples[k][0]
			sg += samples[k][1]
			sb += samples[k][2]
			n++
		}
		return n ? [sr / n, sg / n, sb / n] : null
	}
	for (let i = 0; i < lefts.length; i++) {
		const a = blur(lefts, i) || blur(rights, i)
		const b = blur(rights, i) || a
		if (!a || !b) continue
		const span = Math.max(1, x1 - x0 - 1)
		const y = y0 + i
		for (let x = x0; x < x1; x++) {
			const t = (x - x0) / span
			setPix(x, y, [
				Math.round(a[0] + (b[0] - a[0]) * t),
				Math.round(a[1] + (b[1] - a[1]) * t),
				Math.round(a[2] + (b[2] - a[2]) * t),
				255,
			])
		}
	}
}

for (const circle of circles) {
	fillDisk(circle.cx, circle.cy, circle.r - 5, circle.r - 14, circle.r - 6)
}

const bars = [
	[236, 748, 540, 812],
	[236, 908, 540, 972],
	[236, 1066, 540, 1132],
]
for (const [x0, y0, x1, y1] of bars) {
	let sr = 0
	let sg = 0
	let sb = 0
	let n = 0
	for (let y = y0; y < y1; y++) {
		for (let x = x0; x < x1; x++) {
			const p = at(x, y)
			if (!isGreen(p) && p[2] > p[0] + 20 && p[0] < 40 && (p[0] + p[1] + p[2]) / 3 < 48) {
				sr += p[0]
				sg += p[1]
				sb += p[2]
				n++
			}
		}
	}
	const track = n > 0 ? [Math.round(sr / n), Math.round(sg / n), Math.round(sb / n)] : [0, 32, 72]
	console.log("track", track, "samples", n)
	for (let y = y0; y < y1; y++) {
		for (let x = x0; x < x1; x++) {
			const p = at(x, y)
			if (isGreen(p) || (p[1] > 90 && p[0] > 70 && p[2] < 160)) setPix(x, y, track)
		}
	}
}

const papers = [
	[240, 700, 640, 756],
	[240, 848, 655, 916],
	[240, 1004, 655, 1074],
	[530, 748, 650, 812],
	[530, 900, 650, 980],
	[530, 1060, 650, 1140],
]
function eraseContent(x0, y0, x1, y1) {
	for (let pass = 0; pass < 10; pass++) {
		let changed = 0
		for (let y = y0; y < y1; y++) {
			for (let x = x0; x < x1; x++) {
				if (isCardBlue(at(x, y))) continue
				let found = null
				for (let rad = 1; rad <= 20 && !found; rad++) {
					for (let dy = -rad; dy <= rad && !found; dy++) {
						for (const dx of [-rad, rad]) {
							const nx = x + dx
							const ny = y + dy
							if (nx < 0 || ny < 0 || nx >= W || ny >= H) continue
							const p = at(nx, ny)
							if (isCardBlue(p)) found = p
						}
					}
					for (let dx = -rad; dx <= rad && !found; dx++) {
						for (const dy of [-rad, rad]) {
							const nx = x + dx
							const ny = y + dy
							if (nx < 0 || ny < 0 || nx >= W || ny >= H) continue
							const p = at(nx, ny)
							if (isCardBlue(p)) found = p
						}
					}
				}
				if (!found) continue
				setPix(x, y, found)
				changed++
			}
		}
		if (changed === 0) break
	}
}

function patchAverage(x0, y0, x1, y1) {
	const samples = []
	for (let y = y0; y < y1; y++) {
		for (let x = x0; x < x1; x++) {
			const p = at(x, y)
			if (isCardBlue(p)) samples.push(p)
		}
	}
	if (samples.length < 12) {
		rowFill(x0, y0, x1, y1)
		return
	}
	let sr = 0
	let sg = 0
	let sb = 0
	for (const p of samples) {
		sr += p[0]
		sg += p[1]
		sb += p[2]
	}
	const color = [Math.round(sr / samples.length), Math.round(sg / samples.length), Math.round(sb / samples.length), 255]
	for (let y = y0; y < y1; y++) {
		for (let x = x0; x < x1; x++) {
			if (!isCardBlue(at(x, y))) setPix(x, y, color)
		}
	}
}

for (const rect of papers) rowFill(...rect)

function originalAt(x, y) {
	const i = (y * W + x) * 4
	return [original[i], original[i + 1], original[i + 2]]
}

function cardRef(y) {
	let sr = 0
	let sg = 0
	let sb = 0
	let n = 0
	for (let x = 590; x <= 640; x++) {
		const p = originalAt(x, y)
		if (p[0] < 40 && p[2] > p[0] + 40 && p[2] < 180 && p[1] < 150) {
			sr += p[0]
			sg += p[1]
			sb += p[2]
			n++
		}
	}
	return n ? [sr / n, sg / n, sb / n] : null
}

function isRewardBody(p, ref) {
	if (!ref || p[0] > 70) return false
	const db = p[2] - ref[2]
	const dg = p[1] - ref[1]
	if (db < -12 || db > 14) return false
	if (dg < -12 || dg > 16) return false
	return true
}

const wellSeeds = [
	[752, 753],
	[750, 915],
	[752, 1073],
	[754, 1235],
]
const wellMask = new Uint8Array(W * H)
for (const [sx, sy] of wellSeeds) {
	const stack = [[sx, sy]]
	wellMask[sy * W + sx] = 1
	while (stack.length) {
		const [x, y] = stack.pop()
		for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
			const nx = x + dx
			const ny = y + dy
			if (nx < 656 || nx > 852 || ny < sy - 88 || ny > sy + 92) continue
			if (wellMask[ny * W + nx]) continue
			const p = originalAt(nx, ny)
			if (isRewardBody(p, cardRef(ny))) continue
			if (nx > 828 && p[1] > 155 && p[2] > 210) continue
			wellMask[ny * W + nx] = 1
			stack.push([nx, ny])
		}
	}
}
for (let pass = 0; pass < 2; pass++) {
	const add = []
	for (let y = 660; y < 1340; y++) {
		for (let x = 656; x <= 848; x++) {
			if (wellMask[y * W + x]) continue
			let touch = false
			for (let dy = -1; dy <= 1 && !touch; dy++) {
				for (let dx = -1; dx <= 1; dx++) {
					if (wellMask[(y + dy) * W + (x + dx)]) touch = true
				}
			}
			if (!touch) continue
			const p = originalAt(x, y)
			if (p[1] > 170 && p[2] > 220) continue
			add.push(y * W + x)
		}
	}
	for (const index of add) wellMask[index] = 1
}
function currentRef(y) {
	let sr = 0
	let sg = 0
	let sb = 0
	let n = 0
	for (let x = 610; x <= 648; x++) {
		const p = at(x, y)
		if (p[0] < 50 && p[2] > p[0] + 30 && p[1] < 180) {
			sr += p[0]
			sg += p[1]
			sb += p[2]
			n++
		}
	}
	return n ? [sr / n, sg / n, sb / n] : cardRef(y)
}

for (let y = 0; y < H; y++) {
	for (let x = 0; x < W; x++) {
		if (!wellMask[y * W + x]) continue
		const i = (y * W + x) * 4
		data[i] = original[i]
		data[i + 1] = original[i + 1]
		data[i + 2] = original[i + 2]
		data[i + 3] = original[i + 3]
	}
}
function isFrame(p) {
	return p[0] < 90 && p[1] > 100 && p[2] > 155
}
const innerWell = new Uint8Array(W * H)
for (const [sx, sy] of wellSeeds) {
	const stack = [[sx, sy]]
	innerWell[sy * W + sx] = 1
	while (stack.length) {
		const [x, y] = stack.pop()
		for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
			const nx = x + dx
			const ny = y + dy
			if (nx < 668 || nx > 838 || ny < sy - 78 || ny > sy + 78) continue
			if (innerWell[ny * W + nx]) continue
			if (isFrame(originalAt(nx, ny))) continue
			innerWell[ny * W + nx] = 1
			stack.push([nx, ny])
		}
	}
}
for (let pass = 0; pass < 2; pass++) {
	const add = []
	for (let y = 1; y < H - 1; y++) {
		for (let x = 668; x <= 838; x++) {
			if (innerWell[y * W + x]) continue
			let touch = false
			for (const n of [1, -1, W, -W]) {
				if (innerWell[y * W + x + n]) touch = true
			}
			if (!touch || isFrame(originalAt(x, y))) continue
			add.push(y * W + x)
		}
	}
	for (const index of add) innerWell[index] = 1
}
function isWellBlue(p) {
	return p[0] < 40 && p[2] > 95 && p[2] > p[1] + 25 && p[1] > 40 && p[1] < 110
}
const wellFill = new Map()
for (const [sx, sy] of wellSeeds) {
	let sr = 0
	let sg = 0
	let sb = 0
	let n = 0
	for (let y = sy - 70; y < sy + 70; y++) {
		for (let x = sx - 70; x < sx + 70; x++) {
			if (!innerWell[y * W + x]) continue
			const p = originalAt(x, y)
			if (!isWellBlue(p)) continue
			sr += p[0]
			sg += p[1]
			sb += p[2]
			n++
		}
	}
	wellFill.set(sy, n > 400 ? [Math.round(sr / n), Math.round(sg / n), Math.round(sb / n)] : [1, 62, 114])
	console.log("well interior", sy, wellFill.get(sy), "samples", n)
}
let clearedContents = 0
let lastRow = null
for (let y = 0; y < H; y++) {
	let sr = 0
	let sg = 0
	let sb = 0
	let n = 0
	for (let x = 0; x < W; x++) {
		if (!innerWell[y * W + x]) continue
		const p = originalAt(x, y)
		if (!isWellBlue(p)) continue
		sr += p[0]
		sg += p[1]
		sb += p[2]
		n++
	}
	const rowColor = n > 8 ? [Math.round(sr / n), Math.round(sg / n), Math.round(sb / n)] : lastRow
	if (rowColor) lastRow = rowColor
	if (!rowColor) continue
	for (let x = 0; x < W; x++) {
		if (!innerWell[y * W + x]) continue
		setPix(x, y, rowColor)
		clearedContents++
	}
}
console.log("cleared reward contents", clearedContents)

// The first tracker circle is baked with a check. Copy the empty middle circle's interior over it.
const circle1 = [299, 1252]
const circleDx = 141
for (let y = circle1[1] - 28; y <= circle1[1] + 28; y++) {
	for (let x = circle1[0] - 28; x <= circle1[0] + 28; x++) {
		if (Math.hypot(x - circle1[0], y - circle1[1]) > 25) continue
		setPix(x, y, originalAt(x + circleDx, y))
	}
}
fs.writeFileSync(outPath, PNG.sync.write(src))
console.log("wrote", outPath)

function crop(name, x, y, w, h) {
	const out = new PNG({ width: w, height: h })
	PNG.bitblt(src, out, x, y, w, h, 0, 0)
	fs.writeFileSync(path.join(root, "tools", name), PNG.sync.write(out))
}
crop("probe_clean_c1.png", 90, 680, 180, 160)
crop("probe_clean_row.png", 80, 680, 800, 160)
crop("probe_clean_row2.png", 80, 840, 800, 160)
crop("probe_clean_row3.png", 80, 1000, 800, 160)
crop("probe_clean_rewards.png", 630, 680, 250, 640)
crop("probe_clean_bonus.png", 80, 1140, 800, 190)
crop("probe_clean_bars.png", 220, 740, 460, 80)
