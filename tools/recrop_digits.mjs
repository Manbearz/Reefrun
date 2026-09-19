import fs from "fs"
import path from "path"
import { PNG } from "pngjs"
import { fileURLToPath } from "url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const dir = path.join(root, "assets", "sprites")
const N4 = [[-1, 0], [1, 0], [0, -1], [0, 1]]

function edgeValley(col, colMax, fromLeft) {
	const n = col.length
	const start = fromLeft ? 4 : Math.floor(n * 0.72)
	const end = fromLeft ? Math.floor(n * 0.28) : n - 4
	let bestX = -1
	let bestV = Infinity
	for (let x = start; x < end; x++) {
		if (col[x] > col[x - 1] || col[x] > col[x + 1]) continue
		if (col[x] > colMax * 0.22) continue
		let sideMax = 0
		if (fromLeft) {
			for (let k = 0; k < x; k++) if (col[k] > sideMax) sideMax = col[k]
		} else {
			for (let k = x + 1; k < n; k++) if (col[k] > sideMax) sideMax = col[k]
		}
		if (sideMax <= col[x] * 1.08 || sideMax > colMax * 0.45) continue
		if (col[x] < bestV) {
			bestV = col[x]
			bestX = x
		}
	}
	return bestX
}

function recrop(file) {
	const png = PNG.sync.read(fs.readFileSync(file))
	const { width, height, data } = png
	const label = new Int32Array(width * height)
	const sizes = [0]
	let next = 1
	for (let y = 0; y < height; y++) {
		for (let x = 0; x < width; x++) {
			const i = y * width + x
			if (label[i] || data[i * 4 + 3] < 24) continue
			const stack = [i]
			label[i] = next
			let n = 0
			while (stack.length) {
				const cur = stack.pop()
				n++
				const cx = cur % width
				const cy = (cur / width) | 0
				for (const [dx, dy] of N4) {
					const nx = cx + dx
					const ny = cy + dy
					if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue
					const ni = ny * width + nx
					if (label[ni] || data[ni * 4 + 3] < 24) continue
					label[ni] = next
					stack.push(ni)
				}
			}
			sizes[next] = n
			next++
		}
	}
	let best = 1
	for (let id = 2; id < next; id++) {
		if (sizes[id] > sizes[best]) best = id
	}
	let minX = width
	let minY = height
	let maxX = -1
	let maxY = -1
	for (let y = 0; y < height; y++) {
		for (let x = 0; x < width; x++) {
			const i = y * width + x
			if (label[i] !== best) continue
			if (x < minX) minX = x
			if (y < minY) minY = y
			if (x > maxX) maxX = x
			if (y > maxY) maxY = y
		}
	}
	if (maxX < minX) return
	const col = new Float64Array(width)
	for (let y = 0; y < height; y++) {
		for (let x = 0; x < width; x++) {
			if (label[y * width + x] === best) col[x] += data[(y * width + x) * 4 + 3]
		}
	}
	let colMax = 0
	for (const v of col) if (v > colMax) colMax = v
	const cutRight = edgeValley(col, colMax, false)
	const cutLeft = edgeValley(col, colMax, true)
	if (cutRight >= 0) maxX = Math.min(maxX, cutRight)
	if (cutLeft >= 0) minX = Math.max(minX, cutLeft)
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
			const si = sy * width + sx
			if (label[si] !== best) continue
			const di = (y * tw + x) * 4
			const so = si * 4
			out.data[di] = data[so]
			out.data[di + 1] = data[so + 1]
			out.data[di + 2] = data[so + 2]
			out.data[di + 3] = data[so + 3]
		}
	}
	fs.writeFileSync(file, PNG.sync.write(out))
	console.log(`${path.basename(file)} ${width}x${height} -> ${tw}x${th}`)
}

for (const name of fs.readdirSync(dir)) {
	if (!/^num_(gold|white)_\d\.png$/.test(name)) continue
	recrop(path.join(dir, name))
}
