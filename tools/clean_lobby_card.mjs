import fs from "fs"
import path from "path"
import { PNG } from "pngjs"
import { fileURLToPath } from "url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const srcPath = path.join(root, "assets", "sprites", "daily_missions_card.png")
const outPath = path.join(root, "assets", "sprites", "daily_missions_card_board.png")
const src = PNG.sync.read(fs.readFileSync(srcPath))
const { width: W, height: H, data } = src

function at(x, y) {
	const i = (y * W + x) * 4
	return [data[i], data[i + 1], data[i + 2], data[i + 3]]
}

function setPix(x, y, c) {
	if (x < 0 || y < 0 || x >= W || y >= H) return
	const i = (y * W + x) * 4
	data[i] = c[0]
	data[i + 1] = c[1]
	data[i + 2] = c[2]
	data[i + 3] = c[3]
}

function cardBlue(y) {
	if (y >= 890) return at(780, y)
	return at(322, y)
}

const lightBars = [
	[336, 480, 642, 522],
	[336, 622, 642, 666],
	[336, 768, 642, 812],
]
for (const [x0, y0, x1, y1] of lightBars) {
	for (let y = y0; y <= y1; y++) {
		const blue = cardBlue(y)
		for (let x = x0; x <= x1; x++) setPix(x, y, blue)
	}
}

function isGreen(p) {
	return p[1] > 110 && p[1] > p[0] + 15 && p[1] > p[2] - 10 && p[2] < 190 && p[0] < 230
}

function isGold(p) {
	return p[3] > 160 && p[0] > 160 && p[1] > 70 && p[2] < 200 && p[0] > p[2] + 25
}

function extractCoin(x0, y0, x1, y1, fileName) {
	const w = x1 - x0 + 1
	const h = y1 - y0 + 1
	const mask = new Uint8Array(w * h)
	for (let y = y0; y <= y1; y++) {
		for (let x = x0; x <= x1; x++) {
			if (isGold(at(x, y))) mask[(y - y0) * w + (x - x0)] = 1
		}
	}
	for (let n = 0; n < 4; n++) {
		const add = []
		for (let y = y0; y <= y1; y++) {
			for (let x = x0; x <= x1; x++) {
				const i = (y - y0) * w + (x - x0)
				if (mask[i]) continue
				let touch = false
				for (let dy = -1; dy <= 1 && !touch; dy++) {
					for (let dx = -1; dx <= 1; dx++) {
						const nx = x + dx
						const ny = y + dy
						if (nx < x0 || ny < y0 || nx > x1 || ny > y1) continue
						if (mask[(ny - y0) * w + (nx - x0)]) touch = true
					}
				}
				if (!touch) continue
				const p = at(x, y)
				const lum = (p[0] + p[1] + p[2]) / 3
				if (lum < 80 || (lum > 165 && p[0] > 150)) add.push(i)
			}
		}
		for (const i of add) mask[i] = 1
	}
	let minx = w
	let miny = h
	let maxx = 0
	let maxy = 0
	let count = 0
	for (let y = 0; y < h; y++) {
		for (let x = 0; x < w; x++) {
			if (!mask[y * w + x]) continue
			count++
			if (x < minx) minx = x
			if (y < miny) miny = y
			if (x > maxx) maxx = x
			if (y > maxy) maxy = y
		}
	}
	const cw = maxx - minx + 1
	const ch = maxy - miny + 1
	const out = new PNG({ width: cw, height: ch })
	for (let y = 0; y < ch; y++) {
		for (let x = 0; x < cw; x++) {
			const sx = x0 + minx + x
			const sy = y0 + miny + y
			const o = (y * cw + x) * 4
			if (!mask[(miny + y) * w + (minx + x)]) {
				out.data[o + 3] = 0
				continue
			}
			const p = at(sx, sy)
			out.data[o] = p[0]
			out.data[o + 1] = p[1]
			out.data[o + 2] = p[2]
			out.data[o + 3] = 255
			setPix(sx, sy, cardBlue(sy))
		}
	}
	const outFile = path.join(root, "assets", "sprites", fileName)
	fs.writeFileSync(outFile, PNG.sync.write(out))
	console.log(fileName, { x: x0 + minx, y: y0 + miny, w: cw, h: ch, count })
}

extractCoin(790, 460, 874, 580, "lobby_coin_1.png")
extractCoin(790, 605, 874, 725, "lobby_coin_2.png")
extractCoin(790, 750, 874, 875, "lobby_coin_3.png")
extractCoin(790, 900, 878, 1020, "lobby_coin_bonus.png")

const grooves = [
	[330, 528, 660, 578, 553],
	[330, 673, 660, 723, 698],
	[330, 818, 660, 868, 843],
]
for (const [x0, y0, x1, y1, sy] of grooves) {
	const track = at(580, sy)
	for (let y = y0; y <= y1; y++) {
		for (let x = x0; x <= x1; x++) {
			const p = at(x, y)
			if (isGreen(p) || (p[1] > 90 && p[0] > 70 && p[2] < 160)) setPix(x, y, track)
		}
	}
}

const pills = [
	[686, 540, 752, 566, 670, 553],
	[686, 685, 752, 711, 670, 698],
	[686, 830, 752, 856, 670, 843],
]
for (const [x0, y0, x1, y1, sx, sy] of pills) {
	const ink = at(sx, sy)
	for (let y = y0; y <= y1; y++) {
		for (let x = x0; x <= x1; x++) setPix(x, y, ink)
	}
}

const digits = [
	[876, 496, 952, 560],
	[876, 641, 952, 705],
	[876, 788, 952, 852],
	[878, 928, 972, 1004],
]
for (const [x0, y0, x1, y1] of digits) {
	for (let y = y0; y <= y1; y++) {
		const blue = cardBlue(y)
		for (let x = x0; x <= x1; x++) setPix(x, y, blue)
	}
}

for (let y = 912; y <= 950; y++) {
	const blue = cardBlue(y)
	for (let x = 360; x <= 760; x++) setPix(x, y, blue)
}

function scrub(x0, y0, x1, y1) {
	for (let y = y0; y <= y1; y++) {
		const blue = at(792, y)
		for (let x = x0; x <= x1; x++) {
			const p = at(x, y)
			const far = Math.abs(p[0] - blue[0]) + Math.abs(p[1] - blue[1]) + Math.abs(p[2] - blue[2]) > 14
			if (far) setPix(x, y, blue)
		}
	}
}
scrub(798, 470, 880, 574)
scrub(798, 616, 880, 720)
scrub(798, 762, 880, 868)
scrub(798, 904, 884, 1014)

fs.writeFileSync(outPath, PNG.sync.write(src))
console.log("wrote", outPath)
