import fs from "fs"
import path from "path"
import { PNG } from "pngjs"
import { fileURLToPath } from "url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const srcPath = path.join(root, "assets", "source", "cosmetic1.png")
const outDir = path.join(root, "assets", "sprites")
const COLS = 8
const ROWS = 5

const png = PNG.sync.read(fs.readFileSync(srcPath))
const { width, height, data } = png
const cellW = Math.floor(width / COLS)
const cellH = Math.floor(height / ROWS)
console.log(`sheet ${width}x${height} cell ${cellW}x${cellH}`)

function isSolid(x, y) {
	if (x < 0 || y < 0 || x >= width || y >= height) return false
	const i = (y * width + x) * 4
	if (data[i + 3] < 24) return false
	const r = data[i]
	const g = data[i + 1]
	const b = data[i + 2]
	if (r < 32 && g < 32 && b < 32) return false
	return true
}

function cropCell(col, row) {
	const inset = 8
	const x0 = col * cellW + inset
	const y0 = row * cellH + inset
	const x1 = (col + 1) * cellW - 1 - inset
	const y1 = (row + 1) * cellH - 1 - inset
	let minX = x1
	let minY = y1
	let maxX = x0
	let maxY = y0
	let found = false
	for (let y = y0; y <= y1; y++) {
		for (let x = x0; x <= x1; x++) {
			if (!isSolid(x, y)) continue
			found = true
			if (x < minX) minX = x
			if (y < minY) minY = y
			if (x > maxX) maxX = x
			if (y > maxY) maxY = y
		}
	}
	if (!found) return null
	const pad = 2
	minX = Math.max(0, minX - pad)
	minY = Math.max(0, minY - pad)
	maxX = Math.min(width - 1, maxX + pad)
	maxY = Math.min(height - 1, maxY + pad)
	const w = maxX - minX + 1
	const h = maxY - minY + 1
	const out = new PNG({ width: w, height: h })
	for (let y = 0; y < h; y++) {
		for (let x = 0; x < w; x++) {
			const sx = minX + x
			const sy = minY + y
			const si = (sy * width + sx) * 4
			const di = (y * w + x) * 4
			if (!isSolid(sx, sy)) {
				out.data[di] = 0
				out.data[di + 1] = 0
				out.data[di + 2] = 0
				out.data[di + 3] = 0
				continue
			}
			out.data[di] = data[si]
			out.data[di + 1] = data[si + 1]
			out.data[di + 2] = data[si + 2]
			out.data[di + 3] = data[si + 3]
		}
	}
	return { png: out, w, h, col, row }
}

for (const file of fs.readdirSync(outDir)) {
	if (/^hat_\d+\.png$/.test(file)) fs.unlinkSync(path.join(outDir, file))
}

let n = 0
for (let row = 0; row < ROWS; row++) {
	for (let col = 0; col < COLS; col++) {
		const piece = cropCell(col, row)
		if (!piece) continue
		const name = `hat_${String(n).padStart(2, "0")}`
		fs.writeFileSync(path.join(outDir, `${name}.png`), PNG.sync.write(piece.png))
		console.log(`${name} ${piece.w}x${piece.h} cell ${col},${row}`)
		n++
	}
}
console.log(`sliced ${n} hats`)
