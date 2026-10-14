import fs from "fs"
import path from "path"
import { PNG } from "pngjs"
import { fileURLToPath } from "url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const srcPath = path.join(root, "assets", "source", "characters 1.png")
const outDir = path.join(root, "assets", "sprites")

// Row-major order on the sheet. These match the six fish already in the game.
const SKIP = new Set([1, 2, 3, 4, 5, 9])
const ALPHA = 16
const FRINGE = 2
const PAD = 4
const FIRST_ID = 6

const png = PNG.sync.read(fs.readFileSync(srcPath))
const { width, height, data } = png
console.log(`sheet ${width}x${height}`)

function flood(sx, sy, visited, owner, id) {
	const stack = [[sx, sy]]
	visited[sy * width + sx] = 1
	owner[sy * width + sx] = id
	let minX = sx
	let minY = sy
	let maxX = sx
	let maxY = sy
	let count = 0
	let sumX = 0
	let sumY = 0
	while (stack.length) {
		const [x, y] = stack.pop()
		count++
		sumX += x
		sumY += y
		if (x < minX) minX = x
		if (y < minY) minY = y
		if (x > maxX) maxX = x
		if (y > maxY) maxY = y
		for (const [nx, ny] of [
			[x - 1, y],
			[x + 1, y],
			[x, y - 1],
			[x, y + 1],
		]) {
			if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue
			const idx = ny * width + nx
			if (visited[idx]) continue
			if (data[idx * 4 + 3] < ALPHA) continue
			visited[idx] = 1
			owner[idx] = id
			stack.push([nx, ny])
		}
	}
	return { minX, minY, maxX, maxY, count, cx: sumX / count, cy: sumY / count, id }
}

const visited = new Uint8Array(width * height)
const owner = new Int16Array(width * height)
owner.fill(-1)
const blobs = []
let nextId = 0
for (let y = 0; y < height; y++) {
	for (let x = 0; x < width; x++) {
		if (visited[y * width + x]) continue
		if (data[(y * width + x) * 4 + 3] < ALPHA) continue
		const id = nextId++
		const blob = flood(x, y, visited, owner, id)
		if (blob.count < 80) continue
		blobs.push(blob)
	}
}
blobs.sort((a, b) => {
	const rowA = Math.round(a.cy / 140)
	const rowB = Math.round(b.cy / 140)
	if (rowA !== rowB) return rowA - rowB
	return a.cx - b.cx
})

let fileIndex = FIRST_ID
let written = 0
for (let n = 0; n < blobs.length; n++) {
	if (SKIP.has(n)) {
		console.log(`skip ${n}`)
		continue
	}
	const b = blobs[n]
	const x0 = Math.max(0, b.minX - FRINGE - 2)
	const y0 = Math.max(0, b.minY - FRINGE - 2)
	const x1 = Math.min(width - 1, b.maxX + FRINGE + 2)
	const y1 = Math.min(height - 1, b.maxY + FRINGE + 2)
	const pixels = []
	for (let y = y0; y <= y1; y++) {
		for (let x = x0; x <= x1; x++) {
			const idx = y * width + x
			if (data[idx * 4 + 3] === 0) continue
			const owned = owner[idx]
			if (owned === b.id) {
				pixels.push(idx)
				continue
			}
			if (owned !== -1) continue
			let near = false
			for (let oy = -FRINGE; oy <= FRINGE && !near; oy++) {
				for (let ox = -FRINGE; ox <= FRINGE && !near; ox++) {
					const nx = x + ox
					const ny = y + oy
					if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue
					if (owner[ny * width + nx] === b.id) near = true
				}
			}
			if (near) pixels.push(idx)
		}
	}
	let minX = width
	let minY = height
	let maxX = 0
	let maxY = 0
	for (const idx of pixels) {
		const x = idx % width
		const y = (idx - x) / width
		if (x < minX) minX = x
		if (y < minY) minY = y
		if (x > maxX) maxX = x
		if (y > maxY) maxY = y
	}
	const w = maxX - minX + 1 + PAD * 2
	const h = maxY - minY + 1 + PAD * 2
	const out = new PNG({ width: w, height: h })
	for (const idx of pixels) {
		const x = idx % width
		const y = (idx - x) / width
		const dx = x - minX + PAD
		const dy = y - minY + PAD
		const di = (dy * w + dx) * 4
		const si = idx * 4
		out.data[di] = data[si]
		out.data[di + 1] = data[si + 1]
		out.data[di + 2] = data[si + 2]
		out.data[di + 3] = data[si + 3]
	}
	let edge = 0
	for (let x = 0; x < w; x++) {
		if (out.data[(x) * 4 + 3] > 20) edge++
		if (out.data[((h - 1) * w + x) * 4 + 3] > 20) edge++
	}
	for (let y = 0; y < h; y++) {
		if (out.data[(y * w) * 4 + 3] > 20) edge++
		if (out.data[(y * w + w - 1) * 4 + 3] > 20) edge++
	}
	const name = `fish_${String(fileIndex).padStart(2, "0")}.png`
	fs.writeFileSync(path.join(outDir, name), PNG.sync.write(out))
	console.log(`${name} from #${n} ${w}x${h} edge=${edge}`)
	fileIndex++
	written++
}
console.log(`wrote ${written}, next id ${fileIndex}, sheet ${blobs.length}`)
