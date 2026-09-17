import fs from "fs"
import path from "path"
import { PNG } from "pngjs"
import { fileURLToPath } from "url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const srcPath = path.join(root, "assets", "source", "asset-sheet.png")
const outDir = path.join(root, "assets", "sprites")

const regions = [
	[0, 70, 55, 280],
	[400, 413, 120, 140],
	[820, 720, 80, 90],
	[12, 1116, 400, 80],
]

const png = PNG.sync.read(fs.readFileSync(srcPath))
const { width, height, data } = png

function alphaAt(x, y) {
	return data[(y * width + x) * 4 + 3]
}

function flood(sx, sy, visited, x0, y0, x1, y1) {
	const stack = [[sx, sy]]
	visited[sy * width + sx] = 1
	let minX = sx
	let minY = sy
	let maxX = sx
	let maxY = sy
	let count = 0
	let r = 0
	let g = 0
	let b = 0
	while (stack.length) {
		const [x, y] = stack.pop()
		const i = (y * width + x) * 4
		count++
		r += data[i]
		g += data[i + 1]
		b += data[i + 2]
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
			if (nx < x0 || ny < y0 || nx > x1 || ny > y1) continue
			const idx = ny * width + nx
			if (visited[idx] || alphaAt(nx, ny) < 18) continue
			visited[idx] = 1
			stack.push([nx, ny])
		}
	}
	return { minX, minY, maxX, maxY, count, r: r / count, g: g / count, b: b / count }
}

function isBubble(blob) {
	const w = blob.maxX - blob.minX + 1
	const h = blob.maxY - blob.minY + 1
	if (blob.count < 8 || w < 3 || h < 3) return false
	if (w > 48 || h > 48) return false
	const ratio = w / h
	if (ratio < 0.7 || ratio > 1.4) return false
	const fill = blob.count / (w * h)
	if (fill < 0.32) return false
	if (blob.b < 150 || blob.b < blob.r + 18) return false
	return true
}

function cropBlob(blob, pad = 1) {
	const x0 = Math.max(0, blob.minX - pad)
	const y0 = Math.max(0, blob.minY - pad)
	const x1 = Math.min(width - 1, blob.maxX + pad)
	const y1 = Math.min(height - 1, blob.maxY + pad)
	const w = x1 - x0 + 1
	const h = y1 - y0 + 1
	const out = new PNG({ width: w, height: h })
	for (let y = 0; y < h; y++) {
		for (let x = 0; x < w; x++) {
			const si = ((y0 + y) * width + (x0 + x)) * 4
			const di = (y * w + x) * 4
			out.data[di] = data[si]
			out.data[di + 1] = data[si + 1]
			out.data[di + 2] = data[si + 2]
			out.data[di + 3] = data[si + 3]
		}
	}
	return { png: out, w, h, x: x0, y: y0 }
}

function fingerprint(piece) {
	let sum = 0
	let n = 0
	const d = piece.png.data
	for (let i = 0; i < d.length; i += 4) {
		if (d[i + 3] < 16) continue
		sum += d[i] * 3 + d[i + 1] * 5 + d[i + 2] * 7 + d[i + 3]
		n++
	}
	return `${piece.w}x${piece.h}:${n}:${sum}`
}

const visited = new Uint8Array(width * height)
const kept = []
const seen = new Set()

for (const [rx, ry, rw, rh] of regions) {
	const x0 = Math.max(0, rx)
	const y0 = Math.max(0, ry)
	const x1 = Math.min(width - 1, rx + rw - 1)
	const y1 = Math.min(height - 1, ry + rh - 1)
	for (let y = y0; y <= y1; y++) {
		for (let x = x0; x <= x1; x++) {
			const idx = y * width + x
			if (visited[idx] || alphaAt(x, y) < 18) continue
			const blob = flood(x, y, visited, x0, y0, x1, y1)
			if (!isBubble(blob)) continue
			const piece = cropBlob(blob)
			const key = fingerprint(piece)
			if (seen.has(key)) continue
			seen.add(key)
			kept.push(piece)
		}
	}
}

kept.sort((a, b) => b.w * b.h - a.w * a.h || a.x - b.x)

for (const file of fs.readdirSync(outDir)) {
	if (/^bubble_\d+\.png$/.test(file)) {
		fs.unlinkSync(path.join(outDir, file))
	}
}

kept.forEach((piece, i) => {
	const name = `bubble_${String(i).padStart(2, "0")}`
	fs.writeFileSync(path.join(outDir, `${name}.png`), PNG.sync.write(piece.png))
	console.log(`${name}  ${piece.w}x${piece.h}  @${piece.x},${piece.y}`)
})

console.log(`sliced ${kept.length} bubbles from asset-sheet`)
