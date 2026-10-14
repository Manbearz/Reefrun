import fs from "fs"
import path from "path"
import { PNG } from "pngjs"
import { fileURLToPath } from "url"
import { stripBubbles, trimHat } from "./strip_bubbles.mjs"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const srcPath = path.join(root, "assets", "source", "cosmetic1.png")
const outDir = path.join(root, "assets", "sprites")
const COLS = 8
const ROWS = 5
const ALPHA = 10
const PAD = 3

const png = PNG.sync.read(fs.readFileSync(srcPath))
const { width, height, data } = png
const cellW = Math.floor(width / COLS)
const cellH = Math.floor(height / ROWS)
console.log(`sheet ${width}x${height} cell ${cellW}x${cellH}`)

function alpha(x, y) {
	if (x < 0 || y < 0 || x >= width || y >= height) return 0
	return data[(y * width + x) * 4 + 3]
}

function flood(sx, sy, visited, ownerMap, id) {
	const stack = [[sx, sy]]
	visited[sy * width + sx] = 1
	ownerMap[sy * width + sx] = id
	let minX = sx
	let minY = sy
	let maxX = sx
	let maxY = sy
	let sumX = 0
	let sumY = 0
	let count = 0
	while (stack.length) {
		const [x, y] = stack.pop()
		count++
		sumX += x
		sumY += y
		if (x < minX) minX = x
		if (y < minY) minY = y
		if (x > maxX) maxX = x
		if (y > maxY) maxY = y
		const next = [
			[x - 1, y],
			[x + 1, y],
			[x, y - 1],
			[x, y + 1],
		]
		for (const [nx, ny] of next) {
			if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue
			const idx = ny * width + nx
			if (visited[idx]) continue
			if (alpha(nx, ny) < ALPHA) continue
			visited[idx] = 1
			ownerMap[idx] = id
			stack.push([nx, ny])
		}
	}
	return {
		minX,
		minY,
		maxX,
		maxY,
		count,
		cx: sumX / count,
		cy: sumY / count,
		id,
	}
}

const visited = new Uint8Array(width * height)
const owner = new Int16Array(width * height)
owner.fill(-1)
const blobs = []
let nextBlobId = 0
for (let y = 0; y < height; y++) {
	for (let x = 0; x < width; x++) {
		const idx = y * width + x
		if (visited[idx]) continue
		if (alpha(x, y) < ALPHA) continue
		const blob = flood(x, y, visited, owner, nextBlobId)
		nextBlobId++
		if (blob.count < 8) continue
		blobs.push(blob)
	}
}

const cells = Array.from({ length: ROWS * COLS }, () => [])
for (const blob of blobs) {
	const col = Math.min(COLS - 1, Math.max(0, Math.floor(blob.cx / cellW)))
	const row = Math.min(ROWS - 1, Math.max(0, Math.floor(blob.cy / cellH)))
	cells[row * COLS + col].push(blob)
}

function cropOwned(src, srcOwner, ids, pad) {
	const sw = src.width
	const sh = src.height
	const wanted = new Set(ids)
	let minX = sw
	let minY = sh
	let maxX = 0
	let maxY = 0
	let any = false
	for (let y = 0; y < sh; y++) {
		for (let x = 0; x < sw; x++) {
			if (!wanted.has(srcOwner[y * sw + x])) continue
			any = true
			if (x < minX) minX = x
			if (y < minY) minY = y
			if (x > maxX) maxX = x
			if (y > maxY) maxY = y
		}
	}
	if (!any) return null
	minX = Math.max(0, minX - pad)
	minY = Math.max(0, minY - pad)
	maxX = Math.min(sw - 1, maxX + pad)
	maxY = Math.min(sh - 1, maxY + pad)
	const w = maxX - minX + 1
	const h = maxY - minY + 1
	const out = new PNG({ width: w, height: h })
	for (let y = 0; y < h; y++) {
		for (let x = 0; x < w; x++) {
			const sx = minX + x
			const sy = minY + y
			if (!keepPixel(src, srcOwner, wanted, sx, sy)) continue
			const si = (sy * sw + sx) * 4
			const di = (y * w + x) * 4
			out.data[di] = src.data[si]
			out.data[di + 1] = src.data[si + 1]
			out.data[di + 2] = src.data[si + 2]
			out.data[di + 3] = src.data[si + 3]
		}
	}
	return { png: out, w, h }
}

function keepPixel(src, srcOwner, wanted, x, y) {
	const sw = src.width
	const id = srcOwner[y * sw + x]
	if (wanted.has(id)) return src.data[(y * sw + x) * 4 + 3] > 0
	if (id !== -1) return false
	if (src.data[(y * sw + x) * 4 + 3] < 1) return false
	for (let dy = -2; dy <= 2; dy++) {
		for (let dx = -2; dx <= 2; dx++) {
			const nx = x + dx
			const ny = y + dy
			if (nx < 0 || ny < 0 || nx >= sw || ny >= src.height) continue
			if (wanted.has(srcOwner[ny * sw + nx])) return true
		}
	}
	return false
}

function crop(blobsForCell) {
	if (!blobsForCell.length) return null
	return cropOwned(png, owner, blobsForCell.map((blob) => blob.id), PAD)
}

for (const file of fs.readdirSync(outDir)) {
	if (/^hat_\d+\.png$/.test(file)) fs.unlinkSync(path.join(outDir, file))
}

let n = 0
for (let row = 0; row < ROWS; row++) {
	for (let col = 0; col < COLS; col++) {
		const piece = crop(cells[row * COLS + col])
		if (!piece) {
			console.log(`empty cell ${col},${row}`)
			continue
		}
		const name = `hat_${String(n).padStart(2, "0")}`
		fs.writeFileSync(path.join(outDir, `${name}.png`), PNG.sync.write(piece.png))
		console.log(`${name} ${piece.w}x${piece.h} cell ${col},${row} blobs ${cells[row * COLS + col].length}`)
		n++
	}
}
console.log(`sliced ${n} sheet1 hats`)

// Sheet 2 repeats some sheet 1 hats (Santa, leprechaun, helmet, and so on).
// Those cells are skipped so each hat exists once. New hats keep going after sheet 1.
const sheet2 = PNG.sync.read(fs.readFileSync(path.join(root, "assets", "source", "cosmetic 2.png")))
const BANDS = [0, 184, 330, 464, 601, 734, 864, sheet2.height]
const SKIP = new Set([
	2, 3, 4, 5, 7, 8,
	10, 11, 13, 14, 15,
	19, 21, 22, 23,
	32, 33,
	39, 44,
	50,
	68,
])

function bandPieces(y0, y1) {
	const h = y1 - y0
	const visited = new Uint8Array(sheet2.width * h)
	const blobs = []
	const sample = (x, y) => sheet2.data[((y0 + y) * sheet2.width + x) * 4 + 3]
	for (let y = 0; y < h; y++) {
		for (let x = 0; x < sheet2.width; x++) {
			const idx = y * sheet2.width + x
			if (visited[idx] || sample(x, y) < ALPHA) continue
			const stack = [[x, y]]
			visited[idx] = 1
			let minX = x
			let maxX = x
			let minY = y
			let maxY = y
			let count = 0
			while (stack.length) {
				const [cx, cy] = stack.pop()
				count++
				if (cx < minX) minX = cx
				if (cx > maxX) maxX = cx
				if (cy < minY) minY = cy
				if (cy > maxY) maxY = cy
				for (const [nx, ny] of [[cx - 1, cy], [cx + 1, cy], [cx, cy - 1], [cx, cy + 1]]) {
					if (nx < 0 || ny < 0 || nx >= sheet2.width || ny >= h) continue
					const ni = ny * sheet2.width + nx
					if (visited[ni] || sample(nx, ny) < ALPHA) continue
					visited[ni] = 1
					stack.push([nx, ny])
				}
			}
			if (count > 400) blobs.push({ minX, maxX, minY: minY + y0, maxY: maxY + y0 })
		}
	}
	blobs.sort((a, b) => a.minX - b.minX)
	const pieces = []
	for (const blob of blobs) pieces.push(...splitWide(blob))
	return pieces.filter((box) => box.maxX - box.minX >= 100)
}

function splitWide(blob) {
	const span = blob.maxX - blob.minX
	if (span < 230) return [blob]
	let best = -1
	let bestN = 1e9
	const margin = 70
	for (let x = blob.minX + margin; x <= blob.maxX - margin; x++) {
		let total = 0
		for (let k = -4; k <= 4; k++) {
			const sx = x + k
			if (sx < blob.minX || sx > blob.maxX) continue
			for (let y = blob.minY; y <= blob.maxY; y++) {
				if (sheet2.data[(y * sheet2.width + sx) * 4 + 3] > ALPHA) total++
			}
		}
		if (total < bestN) {
			bestN = total
			best = x
		}
	}
	return [
		...splitWide({ ...blob, maxX: best - 1 }),
		...splitWide({ ...blob, minX: best }),
	]
}

const pieces = []
for (let band = 0; band < BANDS.length - 1; band++) {
	for (const box of bandPieces(BANDS[band], BANDS[band + 1])) pieces.push(box)
}

const comp = new Int32Array(sheet2.width * sheet2.height)
comp.fill(-1)
const compSize = []
let nextComp = 0
for (let y = 0; y < sheet2.height; y++) {
	for (let x = 0; x < sheet2.width; x++) {
		const start = y * sheet2.width + x
		if (comp[start] !== -1) continue
		if (sheet2.data[start * 4 + 3] < ALPHA) continue
		const stack = [[x, y]]
		comp[start] = nextComp
		let count = 0
		while (stack.length) {
			const [cx, cy] = stack.pop()
			count++
			for (const [nx, ny] of [[cx - 1, cy], [cx + 1, cy], [cx, cy - 1], [cx, cy + 1]]) {
				if (nx < 0 || ny < 0 || nx >= sheet2.width || ny >= sheet2.height) continue
				const ni = ny * sheet2.width + nx
				if (comp[ni] !== -1) continue
				if (sheet2.data[ni * 4 + 3] < ALPHA) continue
				comp[ni] = nextComp
				stack.push([nx, ny])
			}
		}
		compSize.push(count)
		nextComp++
	}
}

function findSeed(box) {
	const counts = new Map()
	let fallback = null
	const cx = (box.minX + box.maxX) * 0.5
	const cy = (box.minY + box.maxY) * 0.5
	let fallbackD = Infinity
	for (let y = box.minY; y <= box.maxY; y++) {
		for (let x = box.minX; x <= box.maxX; x++) {
			if (sheet2.data[(y * sheet2.width + x) * 4 + 3] < ALPHA) continue
			const id = comp[y * sheet2.width + x]
			counts.set(id, (counts.get(id) || 0) + 1)
			const dx = x - cx
			const dy = y - cy
			const d = dx * dx + dy * dy
			if (d < fallbackD) {
				fallbackD = d
				fallback = { x, y, id }
			}
		}
	}
	let bestId = fallback ? fallback.id : -1
	let bestN = 0
	for (const [id, n] of counts) {
		if (n > bestN) {
			bestN = n
			bestId = id
		}
	}
	let seed = null
	let seedD = Infinity
	for (let y = box.minY; y <= box.maxY; y++) {
		for (let x = box.minX; x <= box.maxX; x++) {
			if (comp[y * sheet2.width + x] !== bestId) continue
			const dx = x - cx
			const dy = y - cy
			const d = dx * dx + dy * dy
			if (d < seedD) {
				seedD = d
				seed = { id: bestId, x, y }
			}
		}
	}
	return seed || { id: -1, x: 0, y: 0 }
}

const centers = []
for (let index = 0; index < pieces.length; index++) {
	const seed = findSeed(pieces[index])
	centers.push({
		index,
		x: (pieces[index].minX + pieces[index].maxX) * 0.5,
		y: (pieces[index].minY + pieces[index].maxY) * 0.5,
		comp: seed.id,
		sx: seed.x,
		sy: seed.y,
	})
}

const sheetOwner = new Int16Array(sheet2.width * sheet2.height)
sheetOwner.fill(-1)
const queue = []
for (const center of centers) {
	if (center.comp < 0) continue
	const idx = center.sy * sheet2.width + center.sx
	if (sheetOwner[idx] !== -1) continue
	sheetOwner[idx] = center.index
	queue.push(idx)
}
let qi = 0
while (qi < queue.length) {
	const idx = queue[qi++]
	const x = idx % sheet2.width
	const y = (idx - x) / sheet2.width
	const id = comp[idx]
	const ownerId = sheetOwner[idx]
	const next = [
		idx - 1,
		idx + 1,
		idx - sheet2.width,
		idx + sheet2.width,
	]
	for (const ni of next) {
		if (ni < 0 || ni >= comp.length) continue
		if (x === 0 && ni === idx - 1) continue
		if (x === sheet2.width - 1 && ni === idx + 1) continue
		if (comp[ni] !== id || sheetOwner[ni] !== -1) continue
		sheetOwner[ni] = ownerId
		queue.push(ni)
	}
}

for (let y = 0; y < sheet2.height; y++) {
	for (let x = 0; x < sheet2.width; x++) {
		const idx = y * sheet2.width + x
		const ownerId = sheetOwner[idx]
		if (ownerId < 0) continue
		const box = pieces[ownerId]
		if (x >= box.minX && x <= box.maxX && y >= box.minY && y <= box.maxY) continue
		let blocked = false
		for (let index = 0; index < pieces.length; index++) {
			if (index === ownerId) continue
			const other = pieces[index]
			if (x >= other.minX && x <= other.maxX && y >= other.minY && y <= other.maxY) {
				blocked = true
				break
			}
		}
		if (blocked) continue
		let best = ownerId
		const ox = x - centers[ownerId].x
		const oy = y - centers[ownerId].y
		const ownerD = ox * ox + oy * oy
		let bestD = ownerD
		for (let index = 0; index < centers.length; index++) {
			const dest = pieces[index]
			if (x < dest.minX - 18 || x > dest.maxX + 18 || y < dest.minY - 18 || y > dest.maxY + 18) continue
			const dx = x - centers[index].x
			const dy = y - centers[index].y
			const d = dx * dx + dy * dy
			if (d < bestD) {
				bestD = d
				best = index
			}
		}
		if (best !== ownerId && bestD < ownerD * 0.8) sheetOwner[idx] = best
	}
}

const claimed = new Set(centers.map((center) => center.comp))
const extraSum = new Map()
for (let y = 0; y < sheet2.height; y++) {
	for (let x = 0; x < sheet2.width; x++) {
		const id = comp[y * sheet2.width + x]
		if (id < 0 || claimed.has(id) || compSize[id] < 8) continue
		let acc = extraSum.get(id)
		if (!acc) {
			acc = { x: 0, y: 0, n: 0 }
			extraSum.set(id, acc)
		}
		acc.x += x
		acc.y += y
		acc.n++
	}
}
const extra = new Map()
for (const [id, acc] of extraSum) {
	const cx = acc.x / acc.n
	const cy = acc.y / acc.n
	let best = -1
	let bestD = 96 * 96
	for (let index = 0; index < pieces.length; index++) {
		const dx = cx - centers[index].x
		const dy = cy - centers[index].y
		const d = dx * dx + dy * dy
		if (d < bestD) {
			bestD = d
			best = index
		}
	}
	if (best !== -1) extra.set(id, best)
}
for (let y = 0; y < sheet2.height; y++) {
	for (let x = 0; x < sheet2.width; x++) {
		const id = comp[y * sheet2.width + x]
		if (!extra.has(id)) continue
		sheetOwner[y * sheet2.width + x] = extra.get(id)
	}
}

function trimImage(png) {
	let minX = png.width
	let minY = png.height
	let maxX = 0
	let maxY = 0
	for (let y = 0; y < png.height; y++) {
		for (let x = 0; x < png.width; x++) {
			if (png.data[(y * png.width + x) * 4 + 3] < 1) continue
			if (x < minX) minX = x
			if (y < minY) minY = y
			if (x > maxX) maxX = x
			if (y > maxY) maxY = y
		}
	}
	minX = Math.max(0, minX - PAD)
	minY = Math.max(0, minY - PAD)
	maxX = Math.min(png.width - 1, maxX + PAD)
	maxY = Math.min(png.height - 1, maxY + PAD)
	const w = maxX - minX + 1
	const h = maxY - minY + 1
	const out = new PNG({ width: w, height: h })
	for (let y = 0; y < h; y++) {
		for (let x = 0; x < w; x++) {
			const si = ((minY + y) * png.width + (minX + x)) * 4
			const di = (y * w + x) * 4
			out.data[di] = png.data[si]
			out.data[di + 1] = png.data[si + 1]
			out.data[di + 2] = png.data[si + 2]
			out.data[di + 3] = png.data[si + 3]
		}
	}
	return out
}

function dropSeparated(png) {
	const w = png.width
	const h = png.height
	const seen = new Uint8Array(w * h)
	const parts = []
	for (let y = 0; y < h; y++) {
		for (let x = 0; x < w; x++) {
			const start = y * w + x
			if (seen[start] || png.data[start * 4 + 3] < ALPHA) continue
			const stack = [start]
			seen[start] = 1
			const pixels = []
			let minX = x
			let minY = y
			let maxX = x
			let maxY = y
			while (stack.length) {
				const cur = stack.pop()
				pixels.push(cur)
				const cx = cur % w
				const cy = (cur - cx) / w
				if (cx < minX) minX = cx
				if (cy < minY) minY = cy
				if (cx > maxX) maxX = cx
				if (cy > maxY) maxY = cy
				const next = [cur - 1, cur + 1, cur - w, cur + w]
				for (const ni of next) {
					if (ni < 0 || ni >= seen.length) continue
					if (cx === 0 && ni === cur - 1) continue
					if (cx === w - 1 && ni === cur + 1) continue
					if (seen[ni] || png.data[ni * 4 + 3] < ALPHA) continue
					seen[ni] = 1
					stack.push(ni)
				}
			}
			parts.push({ pixels, minX, minY, maxX, maxY })
		}
	}
	if (parts.length < 2) return
	parts.sort((a, b) => b.pixels.length - a.pixels.length)
	const main = parts[0]
	for (const part of parts.slice(1)) {
		const gapX = Math.max(0, Math.max(main.minX - part.maxX, part.minX - main.maxX) - 1)
		const gapY = Math.max(0, Math.max(main.minY - part.maxY, part.minY - main.maxY) - 1)
		if (gapX === 0 && gapY === 0) continue
		for (const p of part.pixels) {
			png.data[p * 4 + 3] = 0
		}
	}
}

let added = 0
for (let index = 0; index < pieces.length; index++) {
	if (SKIP.has(index)) {
		console.log(`skip sheet2 #${index}`)
		continue
	}
	const image = cropOwned(sheet2, sheetOwner, [index], PAD)
	if (!image) continue
	dropSeparated(image.png)
	const trimmed = trimImage(image.png)
	const name = `hat_${String(n).padStart(2, "0")}`
	fs.writeFileSync(path.join(outDir, `${name}.png`), PNG.sync.write(trimmed))
	console.log(`${name} from sheet2 #${index} ${trimmed.width}x${trimmed.height}`)
	n++
	added++
}
console.log(`added ${added} new hats, total ${n}`)
for (const file of fs.readdirSync(outDir)) {
	if (!/^hat_\d+\.png$/.test(file)) continue
	const png = PNG.sync.read(fs.readFileSync(path.join(outDir, file)))
	const removed = stripBubbles(png)
	if (!removed) continue
	fs.writeFileSync(path.join(outDir, file), PNG.sync.write(trimHat(png)))
}
