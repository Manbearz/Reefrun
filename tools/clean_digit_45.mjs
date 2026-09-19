import fs from "fs"
import { PNG } from "pngjs"

const N8 = [
	[-1, -1], [0, -1], [1, -1],
	[-1, 0], [1, 0],
	[-1, 1], [0, 1], [1, 1],
]

function clean(file, outlinePad) {
	const png = PNG.sync.read(fs.readFileSync(file))
	const { width, height, data } = png
	const luma = (i) => 0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2]
	const alpha = (i) => data[i + 3]
	const idx = (x, y) => (y * width + x) * 4

	const body = new Uint8Array(width * height)
	for (let y = 0; y < height; y++) {
		for (let x = 0; x < width; x++) {
			const i = idx(x, y)
			if (alpha(i) >= 50 && luma(i) >= 90) body[y * width + x] = 1
		}
	}

	const label = new Int32Array(width * height)
	const sizes = [0]
	let next = 1
	for (let y = 0; y < height; y++) {
		for (let x = 0; x < width; x++) {
			const p = y * width + x
			if (!body[p] || label[p]) continue
			const stack = [p]
			label[p] = next
			let n = 0
			while (stack.length) {
				const cur = stack.pop()
				n++
				const cx = cur % width
				const cy = (cur / width) | 0
				for (const [dx, dy] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
					const nx = cx + dx
					const ny = cy + dy
					if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue
					const np = ny * width + nx
					if (!body[np] || label[np]) continue
					label[np] = next
					stack.push(np)
				}
			}
			sizes[next] = n
			next++
		}
	}
	let best = 1
	for (let id = 2; id < next; id++) if (sizes[id] > sizes[best]) best = id

	const dist = new Int16Array(width * height)
	dist.fill(-1)
	const q = []
	let bodyMaxX = 0
	for (let y = 0; y < height; y++) {
		for (let x = 0; x < width; x++) {
			const p = y * width + x
			if (label[p] !== best) continue
			dist[p] = 0
			q.push(p)
			if (x > bodyMaxX) bodyMaxX = x
		}
	}

	for (let qi = 0; qi < q.length; qi++) {
		const cur = q[qi]
		const cx = cur % width
		const cy = (cur / width) | 0
		const cd = dist[cur]
		if (cd >= outlinePad) continue
		for (const [dx, dy] of N8) {
			const nx = cx + dx
			const ny = cy + dy
			if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue
			if (nx > bodyMaxX + outlinePad) continue
			const np = ny * width + nx
			if (dist[np] >= 0) continue
			if (alpha(idx(nx, ny)) < 8) continue
			dist[np] = cd + 1
			q.push(np)
		}
	}

	let minX = width
	let minY = height
	let maxX = -1
	let maxY = -1
	for (let y = 0; y < height; y++) {
		for (let x = 0; x < width; x++) {
			if (dist[y * width + x] < 0) continue
			if (x < minX) minX = x
			if (y < minY) minY = y
			if (x > maxX) maxX = x
			if (y > maxY) maxY = y
		}
	}
	const pad = 2
	minX = Math.max(0, minX - pad)
	minY = Math.max(0, minY - pad)
	maxX = Math.min(width - 1, maxX + pad)
	maxY = Math.min(height - 1, maxY + pad)
	const tw = maxX - minX + 1
	const th = maxY - minY + 1
	const out = new PNG({ width: tw, height: th })
	for (let y = 0; y < th; y++) {
		for (let x = 0; x < tw; x++) {
			const sx = minX + x
			const sy = minY + y
			if (dist[sy * width + sx] < 0) continue
			const si = idx(sx, sy)
			const di = (y * tw + x) * 4
			out.data[di] = data[si]
			out.data[di + 1] = data[si + 1]
			out.data[di + 2] = data[si + 2]
			out.data[di + 3] = data[si + 3]
		}
	}
	fs.writeFileSync(file, PNG.sync.write(out))
	console.log(file.split(/[/\\]/).pop(), `${width}x${height} -> ${tw}x${th} bodyMaxX=${bodyMaxX}`)
}

const pad = {
	"assets/sprites/num_gold_4.png": 12,
	"assets/sprites/num_gold_5.png": 16,
	"assets/sprites/num_white_4.png": 12,
	"assets/sprites/num_white_5.png": 16,
}
for (const [file, outlinePad] of Object.entries(pad)) clean(file, outlinePad)
