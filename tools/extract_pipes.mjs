import fs from "fs"
import path from "path"
import { PNG } from "pngjs"
import { fileURLToPath } from "url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const srcPath = path.join(root, "assets", "source", "pipes.png")
const outDir = path.join(root, "assets", "sprites")

const png = PNG.sync.read(fs.readFileSync(srcPath))
const { width, height, data } = png
const names = ["pipe_kelp", "pipe_blue", "pipe_wood", "pipe_metal", "pipe_sand", "pipe_purple"]

function alpha(x, y) {
	return data[(y * width + x) * 4 + 3]
}

const seen = new Uint8Array(width * height)
const blobs = []

function flood(sx, sy) {
	const stack = [[sx, sy]]
	seen[sy * width + sx] = 1
	let minX = sx
	let minY = sy
	let maxX = sx
	let maxY = sy
	while (stack.length) {
		const [x, y] = stack.pop()
		if (x < minX) minX = x
		if (y < minY) minY = y
		if (x > maxX) maxX = x
		if (y > maxY) maxY = y
		for (const [nx, ny] of [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]]) {
			if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue
			const i = ny * width + nx
			if (seen[i] || alpha(nx, ny) < 16) continue
			seen[i] = 1
			stack.push([nx, ny])
		}
	}
	return { minX, minY, maxX, maxY }
}

for (let y = 0; y < height; y++) {
	for (let x = 0; x < width; x++) {
		if (seen[y * width + x] || alpha(x, y) < 16) continue
		const blob = flood(x, y)
		if (blob.maxX - blob.minX < 40 || blob.maxY - blob.minY < 80) continue
		blobs.push(blob)
	}
}

blobs.sort((a, b) => a.minX - b.minX)
console.log("found", blobs.length)

for (let i = 0; i < blobs.length; i++) {
	const b = blobs[i]
	const pad = 1
	const x0 = Math.max(0, b.minX - pad)
	const y0 = Math.max(0, b.minY - pad)
	const x1 = Math.min(width - 1, b.maxX + pad)
	const y1 = Math.min(height - 1, b.maxY + pad)
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
	const name = names[i] || `pipe_${i}`
	fs.writeFileSync(path.join(outDir, `${name}.png`), PNG.sync.write(out))
	console.log(name, `${w}x${h} at ${x0},${y0}`)
}
