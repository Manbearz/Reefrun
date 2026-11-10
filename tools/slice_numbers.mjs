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

// Split halfway between glyph centers. The darkest column sits inside the
// wider glyph's outline, so a valley cut was shaving 3, 5, and 7.
function splits(p) {
	const cuts = [0]
	for (let i = 0; i < p.length - 1; i++) {
		cuts.push(Math.round((p[i].x + p[i + 1].x) / 2))
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
	const ry0 = y0
	const ry1 = y1
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

	// A neighbor's outline sometimes crosses the midpoint. Drop a small piece
	// that does not overlap the main digit.
	const seen = new Uint8Array(w * h)
	const parts = []
	for (let y = 0; y < h; y++) {
		for (let x = 0; x < w; x++) {
			const start = y * w + x
			if (seen[start] || !keep[start]) continue
			const stack = [start]
			seen[start] = 1
			const cells = []
			let minCX = x
			let maxCX = x
			while (stack.length) {
				const cur = stack.pop()
				cells.push(cur)
				const cx = cur % w
				if (cx < minCX) minCX = cx
				if (cx > maxCX) maxCX = cx
				for (const [dx, dy] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
					const nx = cx + dx
					const ny = (cur / w | 0) + dy
					if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue
					const ni = ny * w + nx
					if (seen[ni] || !keep[ni]) continue
					seen[ni] = 1
					stack.push(ni)
				}
			}
			parts.push({ cells, minCX, maxCX })
		}
	}
	let main = parts[0]
	for (const part of parts) {
		if (!main || part.cells.length > main.cells.length) main = part
	}
	if (main) {
		for (const part of parts) {
			if (part === main || part.cells.length >= 400) continue
			const thin = part.maxCX - part.minCX < 14
			const sticksOut = part.minCX >= main.maxCX - 1 || part.maxCX <= main.minCX + 1
			if (thin && sticksOut) {
				for (const ni of part.cells) keep[ni] = 0
			}
		}
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

	// Always leave transparent padding, including when the ink reaches the
	// edge of the source window. Those extra pixels stay empty.
	const border = 8
	const tw = maxX - minX + 1 + border * 2
	const th = maxY - minY + 1 + border * 2
	const out = new PNG({ width: tw, height: th })
	for (let y = 0; y < th; y++) {
		for (let x = 0; x < tw; x++) {
			const lx = minX + x - border
			const ly = minY + y - border
			if (lx < 0 || ly < 0 || lx >= w || ly >= h) continue
			if (!keep[ly * w + lx]) continue
			const gx = rx0 + lx
			const gy = ry0 + ly
			if (gx < 0 || gy < 0 || gx >= width || gy >= height) continue
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

function stripSlivers(png) {
	const { width, height, data } = png
	const label = new Int32Array(width * height)
	const sizes = [0]
	let next = 1
	const alphaOf = (i) => data[i * 4 + 3]
	for (let y = 0; y < height; y++) {
		for (let x = 0; x < width; x++) {
			const i = y * width + x
			if (label[i] || alphaOf(i) < 24) continue
			const stack = [i]
			label[i] = next
			let n = 0
			let minX = x
			let maxX = x
			while (stack.length) {
				const cur = stack.pop()
				n++
				const cx = cur % width
				const cy = (cur / width) | 0
				if (cx < minX) minX = cx
				if (cx > maxX) maxX = cx
				for (const [dx, dy] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
					const nx = cx + dx
					const ny = cy + dy
					if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue
					const ni = ny * width + nx
					if (label[ni] || alphaOf(ni) < 24) continue
					label[ni] = next
					stack.push(ni)
				}
			}
			sizes[next] = n
			next++
		}
	}
	let main = 1
	for (let id = 2; id < next; id++) if (sizes[id] > sizes[main]) main = id
	for (let id = 1; id < next; id++) {
		if (id === main || sizes[id] === 0 || sizes[id] >= 400) continue
		let minX = width
		let maxX = 0
		for (let i = 0; i < label.length; i++) {
			if (label[i] !== id) continue
			const x = i % width
			if (x < minX) minX = x
			if (x > maxX) maxX = x
		}
		if (maxX - minX >= 16) continue
		let dist = 99
		for (let y = 0; y < height && dist > 2; y++) {
			for (let x = 0; x < width; x++) {
				if (label[y * width + x] !== id) continue
				for (let dy = -6; dy <= 6; dy++) {
					for (let dx = -6; dx <= 6; dx++) {
						const nx = x + dx
						const ny = y + dy
						if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue
						if (label[ny * width + nx] !== main) continue
						dist = Math.min(dist, Math.max(Math.abs(dx), Math.abs(dy)))
					}
				}
			}
		}
		if (dist < 3) continue
		for (let i = 0; i < label.length; i++) {
			if (label[i] !== id) continue
			const cx = i % width
			const cy = (i / width) | 0
			for (let dy = -2; dy <= 2; dy++) {
				for (let dx = -2; dx <= 2; dx++) {
					const nx = cx + dx
					const ny = cy + dy
					if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue
					const ni = ny * width + nx
					if (label[ni] === main) continue
					data[ni * 4 + 3] = 0
				}
			}
		}
	}
}

function sliceRow(prefix, y0, y1) {
	const s = smooth(colSum(y0, y1))
	const p = peaks(s)
	if (p.length !== 10) {
		throw new Error(`${prefix} expected 10 peaks, got ${p.length}: ${p.map((q) => q.x)}`)
	}
	const cuts = splits(p)
	for (let d = 0; d < 10; d++) {
		const piece = extractDigit(p[d].x, y0, y1, cuts[d], cuts[d + 1])
		if (!piece) throw new Error(`empty ${prefix} ${d}`)
		const name = `${prefix}_${d}`
		stripSlivers(piece.png)
		fs.writeFileSync(path.join(outDir, `${name}.png`), PNG.sync.write(piece.png))
		console.log(`${name} ${piece.w}x${piece.h}`)
	}
}

fs.mkdirSync(outDir, { recursive: true })
// The two rows are separated by an empty band. Gold's shadow ends in that
// band, and white begins after it.
sliceRow("num_gold", 0, 370)
sliceRow("num_white", 370, height)
