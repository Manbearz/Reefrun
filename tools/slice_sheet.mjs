import fs from "fs"
import path from "path"
import { PNG } from "pngjs"
import { fileURLToPath } from "url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const srcPath = path.join(root, "asset sheet.png")
const outDir = path.join(root, "assets", "sprites")
const atlasPath = path.join(root, "assets", "atlas.json")

fs.mkdirSync(outDir, { recursive: true })

const png = PNG.sync.read(fs.readFileSync(srcPath))
const { width, height, data } = png

function alpha(x, y) {
	const i = (y * width + x) * 4
	return data[i + 3]
}

const visited = new Uint8Array(width * height)
const blobs = []

function flood(sx, sy) {
	const stack = [[sx, sy]]
	visited[sy * width + sx] = 1
	let minX = sx
	let minY = sy
	let maxX = sx
	let maxY = sy
	let count = 0
	while (stack.length) {
		const [x, y] = stack.pop()
		count++
		if (x < minX) minX = x
		if (y < minY) minY = y
		if (x > maxX) maxX = x
		if (y > maxY) maxY = y
		const n = [
			[x - 1, y],
			[x + 1, y],
			[x, y - 1],
			[x, y + 1],
		]
		for (const [nx, ny] of n) {
			if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue
			const idx = ny * width + nx
			if (visited[idx]) continue
			if (alpha(nx, ny) < 12) continue
			visited[idx] = 1
			stack.push([nx, ny])
		}
	}
	return { minX, minY, maxX, maxY, count }
}

for (let y = 0; y < height; y++) {
	for (let x = 0; x < width; x++) {
		const idx = y * width + x
		if (visited[idx]) continue
		if (alpha(x, y) < 12) continue
		const blob = flood(x, y)
		const w = blob.maxX - blob.minX + 1
		const h = blob.maxY - blob.minY + 1
		if (blob.count < 40 || w < 6 || h < 6) continue
		blobs.push(blob)
	}
}

blobs.sort((a, b) => a.minY - b.minY || a.minX - b.minX)

function crop(blob, pad = 1) {
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
	return { png: out, x: x0, y: y0, w, h }
}

const named = []
for (let i = 0; i < blobs.length; i++) {
	const blob = blobs[i]
	const piece = crop(blob)
	const name = `sprite_${String(i).padStart(3, "0")}_${piece.w}x${piece.h}`
	const file = `${name}.png`
	fs.writeFileSync(path.join(outDir, file), PNG.sync.write(piece.png))
	named.push({
		index: i,
		file,
		x: piece.x,
		y: piece.y,
		w: piece.w,
		h: piece.h,
		cx: piece.x + piece.w / 2,
		cy: piece.y + piece.h / 2,
	})
}

fs.writeFileSync(atlasPath, JSON.stringify({ width, height, sprites: named }, null, 2))
console.log(`sheet ${width}x${height}`)
console.log(`extracted ${named.length} sprites`)
for (const s of named) {
	console.log(`${s.index.toString().padStart(3, " ")}  ${s.x},${s.y}  ${s.w}x${s.h}  ${s.file}`)
}
