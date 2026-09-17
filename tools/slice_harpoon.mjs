import fs from "fs"
import path from "path"
import { PNG } from "pngjs"
import { fileURLToPath } from "url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const srcPath = path.join(root, "assets", "source", "14537d0a-a0a6-482b-a8bf-bb99f4409e91.png")
const outDir = path.join(root, "assets", "sprites")

const png = PNG.sync.read(fs.readFileSync(srcPath))
const { width, height, data } = png
const labels = new Int32Array(width * height)

function alpha(x, y) {
	return data[(y * width + x) * 4 + 3]
}

const blobs = []
let nextLabel = 1

function flood(sx, sy, label) {
	const stack = [[sx, sy]]
	labels[sy * width + sx] = label
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
		for (const [nx, ny] of [
			[x - 1, y],
			[x + 1, y],
			[x, y - 1],
			[x, y + 1],
		]) {
			if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue
			const idx = ny * width + nx
			if (labels[idx]) continue
			if (alpha(nx, ny) < 12) continue
			labels[idx] = label
			stack.push([nx, ny])
		}
	}
	return { minX, minY, maxX, maxY, count, label }
}

for (let y = 0; y < height; y++) {
	for (let x = 0; x < width; x++) {
		const idx = y * width + x
		if (labels[idx] || alpha(x, y) < 12) continue
		const blob = flood(x, y, nextLabel++)
		const w = blob.maxX - blob.minX + 1
		const h = blob.maxY - blob.minY + 1
		if (blob.count < 5000 || w < 120 || h < 160) continue
		blobs.push(blob)
	}
}

const top = blobs.filter((b) => b.minY < 300).sort((a, b) => a.minX - b.minX)
const bot = blobs.filter((b) => b.minY >= 300).sort((a, b) => a.minX - b.minX)
if (top.length !== 6 || bot.length !== 5) {
	throw new Error(`expected 6 top + 5 bottom harpoons, got ${top.length} + ${bot.length}`)
}
const ordered = [
	top[0],
	top[1],
	top[2],
	bot[1],
	bot[0],
	bot[2],
	top[4],
	top[3],
	bot[3],
	top[5],
	bot[4],
]

function crop(blob, pad = 1) {
	const x0 = Math.max(0, blob.minX - pad)
	const y0 = Math.max(0, blob.minY - pad)
	const x1 = Math.min(width - 1, blob.maxX + pad)
	const y1 = Math.min(height - 1, blob.maxY + pad)
	const w = x1 - x0 + 1
	const h = y1 - y0 + 1
	const raw = Buffer.alloc(w * h * 4)
	for (let y = 0; y < h; y++) {
		for (let x = 0; x < w; x++) {
			const gx = x0 + x
			const gy = y0 + y
			const gi = gy * width + gx
			const keep = labels[gi] === blob.label
			const near =
				!keep &&
				((gx > 0 && labels[gi - 1] === blob.label) ||
					(gx + 1 < width && labels[gi + 1] === blob.label) ||
					(gy > 0 && labels[gi - width] === blob.label) ||
					(gy + 1 < height && labels[gi + width] === blob.label))
			if (!keep && !near) continue
			const si = gi * 4
			const di = (y * w + x) * 4
			raw[di] = data[si]
			raw[di + 1] = data[si + 1]
			raw[di + 2] = data[si + 2]
			raw[di + 3] = data[si + 3]
		}
	}
	let minX = w
	let minY = h
	let maxX = -1
	let maxY = -1
	for (let y = 0; y < h; y++) {
		for (let x = 0; x < w; x++) {
			if (raw[(y * w + x) * 4 + 3] < 12) continue
			if (x < minX) minX = x
			if (y < minY) minY = y
			if (x > maxX) maxX = x
			if (y > maxY) maxY = y
		}
	}
	const tw = maxX - minX + 1
	const th = maxY - minY + 1
	const out = new PNG({ width: tw, height: th })
	for (let y = 0; y < th; y++) {
		for (let x = 0; x < tw; x++) {
			const si = ((minY + y) * w + (minX + x)) * 4
			const di = (y * tw + x) * 4
			out.data[di] = raw[si]
			out.data[di + 1] = raw[si + 1]
			out.data[di + 2] = raw[si + 2]
			out.data[di + 3] = raw[si + 3]
		}
	}
	return { png: out, w: tw, h: th }
}

ordered.forEach((blob, i) => {
	const name = `harpoon_${String(i).padStart(2, "0")}`
	const piece = crop(blob)
	fs.writeFileSync(path.join(outDir, `${name}.png`), PNG.sync.write(piece.png))
	console.log(`${name}  #${i + 1}  ${piece.w}x${piece.h}`)
})
