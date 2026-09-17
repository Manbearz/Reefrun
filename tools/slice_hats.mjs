import fs from "fs"
import path from "path"
import { PNG } from "pngjs"
import { fileURLToPath } from "url"

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

function flood(sx, sy, visited) {
	const stack = [[sx, sy]]
	visited[sy * width + sx] = 1
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
	}
}

const visited = new Uint8Array(width * height)
const blobs = []
for (let y = 0; y < height; y++) {
	for (let x = 0; x < width; x++) {
		const idx = y * width + x
		if (visited[idx]) continue
		if (alpha(x, y) < ALPHA) continue
		const blob = flood(x, y, visited)
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

function crop(blobsForCell) {
	if (!blobsForCell.length) return null
	let minX = width
	let minY = height
	let maxX = 0
	let maxY = 0
	for (const blob of blobsForCell) {
		if (blob.minX < minX) minX = blob.minX
		if (blob.minY < minY) minY = blob.minY
		if (blob.maxX > maxX) maxX = blob.maxX
		if (blob.maxY > maxY) maxY = blob.maxY
	}
	minX = Math.max(0, minX - PAD)
	minY = Math.max(0, minY - PAD)
	maxX = Math.min(width - 1, maxX + PAD)
	maxY = Math.min(height - 1, maxY + PAD)
	const w = maxX - minX + 1
	const h = maxY - minY + 1
	const out = new PNG({ width: w, height: h })
	for (let y = 0; y < h; y++) {
		for (let x = 0; x < w; x++) {
			const si = ((minY + y) * width + (minX + x)) * 4
			const di = (y * w + x) * 4
			out.data[di] = data[si]
			out.data[di + 1] = data[si + 1]
			out.data[di + 2] = data[si + 2]
			out.data[di + 3] = data[si + 3]
		}
	}
	return { png: out, w, h }
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
console.log(`sliced ${n} hats`)
