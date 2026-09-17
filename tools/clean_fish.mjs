import fs from "fs"
import path from "path"
import { PNG } from "pngjs"
import { fileURLToPath } from "url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const srcPath = path.join(root, "assets", "source", "asset-sheet.png")
const outDir = path.join(root, "assets", "sprites")

const sheet = PNG.sync.read(fs.readFileSync(srcPath))
const { width, height, data } = sheet

const fishes = [
	["fish_blue", 56, 80, 108, 120],
	["fish_clown", 168, 80, 130, 120],
	["fish_yellow", 296, 80, 130, 120],
	["fish_green", 14, 214, 150, 120],
	["fish_pink", 166, 214, 130, 120],
	["fish_purple", 296, 214, 134, 120],
]

function idx(x, y, w) {
	return (y * w + x) * 4
}

function crop(x, y, w, h) {
	const out = new PNG({ width: w, height: h })
	for (let yy = 0; yy < h; yy++) {
		for (let xx = 0; xx < w; xx++) {
			const sx = x + xx
			const sy = y + yy
			const di = idx(xx, yy, w)
			if (sx < 0 || sy < 0 || sx >= width || sy >= height) continue
			const si = idx(sx, sy, width)
			out.data[di] = data[si]
			out.data[di + 1] = data[si + 1]
			out.data[di + 2] = data[si + 2]
			out.data[di + 3] = data[si + 3]
		}
	}
	return out
}

function maskFrom(png, cutoff) {
	const { width: w, height: h, data: d } = png
	const mask = new Uint8Array(w * h)
	for (let i = 0; i < w * h; i++) {
		mask[i] = d[i * 4 + 3] >= cutoff ? 1 : 0
	}
	return mask
}

function morph(mask, w, h, dilate) {
	const next = new Uint8Array(w * h)
	for (let y = 0; y < h; y++) {
		for (let x = 0; x < w; x++) {
			let keep = false
			for (let oy = -1; oy <= 1 && !keep; oy++) {
				for (let ox = -1; ox <= 1 && !keep; ox++) {
					const nx = x + ox
					const ny = y + oy
					if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue
					const on = mask[ny * w + nx] === 1
					if (dilate) {
						if (on) keep = true
					} else if (ox === 0 && oy === 0) {
						keep = on
					} else if (!on) {
						keep = false
						ox = 2
						oy = 2
					}
				}
			}
			if (!dilate) {
				keep = true
				for (let oy = -1; oy <= 1 && keep; oy++) {
					for (let ox = -1; ox <= 1 && keep; ox++) {
						const nx = x + ox
						const ny = y + oy
						if (nx < 0 || ny < 0 || nx >= w || ny >= h || mask[ny * w + nx] === 0) {
							keep = false
						}
					}
				}
			}
			next[y * w + x] = keep ? 1 : 0
		}
	}
	return next
}

function largestComponent(mask, w, h) {
	const seen = new Uint8Array(w * h)
	let best = []
	for (let i = 0; i < w * h; i++) {
		if (!mask[i] || seen[i]) continue
		const stack = [i]
		seen[i] = 1
		const cells = []
		while (stack.length) {
			const p = stack.pop()
			cells.push(p)
			const x = p % w
			const y = (p / w) | 0
			const n = [
				[x - 1, y],
				[x + 1, y],
				[x, y - 1],
				[x, y + 1],
			]
			for (const [nx, ny] of n) {
				if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue
				const ni = ny * w + nx
				if (!mask[ni] || seen[ni]) continue
				seen[ni] = 1
				stack.push(ni)
			}
		}
		if (cells.length > best.length) best = cells
	}
	const out = new Uint8Array(w * h)
	for (const p of best) out[p] = 1
	return out
}

function applyMask(png, mask) {
	const { width: w, height: h, data: d } = png
	for (let i = 0; i < w * h; i++) {
		if (!mask[i]) {
			d[i * 4] = 0
			d[i * 4 + 1] = 0
			d[i * 4 + 2] = 0
			d[i * 4 + 3] = 0
		}
	}
}

function removeSmallBlobs(png) {
	const { width: w, height: h, data: d } = png
	const seen = new Uint8Array(w * h)
	const blobs = []
	for (let i = 0; i < w * h; i++) {
		if (d[i * 4 + 3] < 90 || seen[i]) continue
		const stack = [i]
		seen[i] = 1
		const cells = []
		let minX = w
		while (stack.length) {
			const p = stack.pop()
			cells.push(p)
			const x = p % w
			const y = (p / w) | 0
			if (x < minX) minX = x
			for (const [ox, oy] of [[-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [1, -1], [-1, 1], [1, 1]]) {
				const nx = x + ox
				const ny = y + oy
				if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue
				const ni = ny * w + nx
				if (d[ni * 4 + 3] < 90 || seen[ni]) continue
				seen[ni] = 1
				stack.push(ni)
			}
		}
		blobs.push({ cells, minX, area: cells.length })
	}
	if (blobs.length < 2) return
	blobs.sort((a, b) => b.area - a.area)
	const main = blobs[0]
	for (const blob of blobs.slice(1)) {
		if (blob.area > main.area * 0.2) continue
		for (const p of blob.cells) {
			d[p * 4] = 0
			d[p * 4 + 1] = 0
			d[p * 4 + 2] = 0
			d[p * 4 + 3] = 0
		}
		// also clear faint pixels around the dropped blob
		for (const p of blob.cells) {
			const x = p % w
			const y = (p / w) | 0
			for (let oy = -2; oy <= 2; oy++) {
				for (let ox = -2; ox <= 2; ox++) {
					const nx = x + ox
					const ny = y + oy
					if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue
					const ni = ny * w + nx
					if (d[ni * 4 + 3] > 0 && d[ni * 4 + 3] < 140) {
						d[ni * 4] = 0
						d[ni * 4 + 1] = 0
						d[ni * 4 + 2] = 0
						d[ni * 4 + 3] = 0
					}
				}
			}
		}
	}
}

function trim(png) {
	const { width: w, height: h, data: d } = png
	let minX = w
	let minY = h
	let maxX = -1
	let maxY = -1
	for (let y = 0; y < h; y++) {
		for (let x = 0; x < w; x++) {
			if (d[idx(x, y, w) + 3] < 16) continue
			if (x < minX) minX = x
			if (y < minY) minY = y
			if (x > maxX) maxX = x
			if (y > maxY) maxY = y
		}
	}
	if (maxX < 0) return png
	minX = Math.max(0, minX - 1)
	minY = Math.max(0, minY - 1)
	maxX = Math.min(w - 1, maxX + 1)
	maxY = Math.min(h - 1, maxY + 1)
	const tw = maxX - minX + 1
	const th = maxY - minY + 1
	const out = new PNG({ width: tw, height: th })
	for (let y = 0; y < th; y++) {
		for (let x = 0; x < tw; x++) {
			const si = idx(minX + x, minY + y, w)
			const di = idx(x, y, tw)
			out.data[di] = d[si]
			out.data[di + 1] = d[si + 1]
			out.data[di + 2] = d[si + 2]
			out.data[di + 3] = d[si + 3]
		}
	}
	return out
}

for (const [name, x, y, w, h] of fishes) {
	const png = crop(x, y, w, h)
	let mask = maskFrom(png, 110)
	mask = morph(mask, w, h, false)
	mask = morph(mask, w, h, false)
	mask = morph(mask, w, h, false)
	mask = largestComponent(mask, w, h)
	mask = morph(mask, w, h, true)
	mask = morph(mask, w, h, true)
	mask = morph(mask, w, h, true)
	mask = morph(mask, w, h, true)
	const original = maskFrom(png, 18)
	for (let i = 0; i < w * h; i++) {
		if (mask[i] && !original[i]) mask[i] = 0
	}
	applyMask(png, mask)
	removeSmallBlobs(png)
	const cleaned = trim(png)
	fs.writeFileSync(path.join(outDir, `${name}.png`), PNG.sync.write(cleaned))
	console.log(name, `${cleaned.width}x${cleaned.height}`)
}
