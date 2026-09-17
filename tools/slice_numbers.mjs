import fs from "fs"
import path from "path"
import { PNG } from "pngjs"
import { fileURLToPath } from "url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const srcPath = path.join(root, "assets", "source", "numbers.png")
const outDir = path.join(root, "assets", "sprites")

const png = PNG.sync.read(fs.readFileSync(srcPath))
const { width, height, data } = png

function alphaAt(x, y) {
	return data[(y * width + x) * 4 + 3]
}

function lumaAt(x, y) {
	const i = (y * width + x) * 4
	return 0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2]
}

function colSum(y0, y1) {
	const s = new Float64Array(width)
	for (let y = y0; y < y1; y++) {
		for (let x = 0; x < width; x++) s[x] += alphaAt(x, y)
	}
	return s
}

function smooth(s, r = 12) {
	const o = new Float64Array(s.length)
	for (let i = 0; i < s.length; i++) {
		let a = 0
		let n = 0
		for (let k = i - r; k <= i + r; k++) {
			if (k < 0 || k >= s.length) continue
			a += s[k]
			n++
		}
		o[i] = a / n
	}
	return o
}

function peaks(s) {
	let max = 0
	for (const v of s) if (v > max) max = v
	const p = []
	for (let x = 30; x < s.length - 30; x++) {
		if (s[x] < max * 0.45) continue
		if (s[x] >= s[x - 1] && s[x] >= s[x + 1] && s[x] >= s[x - 25] && s[x] >= s[x + 25]) {
			if (!p.length || x - p[p.length - 1].x > 80) p.push({ x, v: s[x] })
			else if (s[x] > p[p.length - 1].v) p[p.length - 1] = { x, v: s[x] }
		}
	}
	return p
}

function valleys(p, s) {
	const cuts = [0]
	for (let i = 0; i < p.length - 1; i++) {
		let minX = p[i].x
		let minV = Infinity
		for (let x = p[i].x + 20; x < p[i + 1].x - 20; x++) {
			if (s[x] < minV) {
				minV = s[x]
				minX = x
			}
		}
		cuts.push(minX)
	}
	cuts.push(width)
	return cuts
}

const N8 = [
	[-1, -1], [0, -1], [1, -1],
	[-1, 0], [1, 0],
	[-1, 1], [0, 1], [1, 1],
]

function extractDigit(peakX, y0, y1, x0, x1) {
	const pad = 22
	const rx0 = Math.max(0, x0 - pad)
	const rx1 = Math.min(width, x1 + pad)
	const ry0 = Math.max(0, y0 - 4)
	const ry1 = Math.min(height, y1 + 4)
	const w = rx1 - rx0
	const h = ry1 - ry0
	const keep = new Uint8Array(w * h)

	let seedY = ((y0 + y1) / 2) | 0
	let seedX = peakX
	if (alphaAt(seedX, seedY) < 20) {
		outer: for (let y = y0; y < y1; y++) {
			if (alphaAt(peakX, y) >= 20) {
				seedY = y
				break outer
			}
		}
	}

	const stack = [[seedX, seedY]]
	while (stack.length) {
		const [x, y] = stack.pop()
		if (x < x0 || y < y0 || x >= x1 || y >= y1) continue
		if (x < rx0 || y < ry0 || x >= rx1 || y >= ry1) continue
		const idx = (y - ry0) * w + (x - rx0)
		if (keep[idx]) continue
		if (alphaAt(x, y) < 8) continue
		keep[idx] = 1
		for (const [dx, dy] of N8) stack.push([x + dx, y + dy])
	}

	for (let pass = 0; pass < 5; pass++) {
		const extra = []
		for (let y = ry0; y < ry1; y++) {
			for (let x = rx0; x < rx1; x++) {
				const idx = (y - ry0) * w + (x - rx0)
				if (keep[idx] || alphaAt(x, y) < 1) continue
				let near = false
				for (const [dx, dy] of N8) {
					const nx = x + dx
					const ny = y + dy
					if (nx < rx0 || ny < ry0 || nx >= rx1 || ny >= ry1) continue
					if (keep[(ny - ry0) * w + (nx - rx0)]) {
						near = true
						break
					}
				}
				if (!near) continue
				const luma = lumaAt(x, y)
				const inside = x >= x0 && x < x1
				if (!inside) {
					if (x < x0 - 7 || x >= x1 + 7) continue
					if (luma >= 72) continue
				}
				if (pass < 4) {
					if (luma < 92) extra.push(idx)
				} else if (luma < 130) {
					extra.push(idx)
				}
			}
		}
		for (const idx of extra) keep[idx] = 1
	}

	let minX = w
	let minY = h
	let maxX = -1
	let maxY = -1
	for (let y = 0; y < h; y++) {
		for (let x = 0; x < w; x++) {
			if (!keep[y * w + x]) continue
			if (x < minX) minX = x
			if (y < minY) minY = y
			if (x > maxX) maxX = x
			if (y > maxY) maxY = y
		}
	}
	if (maxX < minX) return null

	const border = 3
	minX = Math.max(0, minX - border)
	minY = Math.max(0, minY - border)
	maxX = Math.min(w - 1, maxX + border)
	maxY = Math.min(h - 1, maxY + border)
	const tw = maxX - minX + 1
	const th = maxY - minY + 1
	const out = new PNG({ width: tw, height: th })
	for (let y = 0; y < th; y++) {
		for (let x = 0; x < tw; x++) {
			const gx = rx0 + minX + x
			const gy = ry0 + minY + y
			const ki = (ry0 + minY + y - ry0) * w + (minX + x)
			if (!keep[ki]) continue
			const si = (gy * width + gx) * 4
			const di = (y * tw + x) * 4
			out.data[di] = data[si]
			out.data[di + 1] = data[si + 1]
			out.data[di + 2] = data[si + 2]
			out.data[di + 3] = data[si + 3]
		}
	}
	return { png: out, w: tw, h: th }
}

function sliceRow(prefix, y0, y1) {
	const s = smooth(colSum(y0, y1))
	const p = peaks(s)
	if (p.length !== 10) {
		throw new Error(`${prefix} expected 10 peaks, got ${p.length}: ${p.map((q) => q.x)}`)
	}
	const cuts = valleys(p, s)
	for (let d = 0; d < 10; d++) {
		const piece = extractDigit(p[d].x, y0, y1, cuts[d], cuts[d + 1])
		if (!piece) throw new Error(`empty ${prefix} ${d}`)
		const name = `${prefix}_${d}`
		fs.writeFileSync(path.join(outDir, `${name}.png`), PNG.sync.write(piece.png))
		console.log(`${name} ${piece.w}x${piece.h}`)
	}
}

fs.mkdirSync(outDir, { recursive: true })
sliceRow("num_gold", 0, 360)
sliceRow("num_white", 360, height)
