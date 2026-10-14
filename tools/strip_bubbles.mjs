import fs from "fs"
import path from "path"
import { PNG } from "pngjs"
import { fileURLToPath } from "url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const dir = path.join(root, "assets", "sprites")
const only = process.argv.slice(2)

function isBlue(r, g, b, a) {
	return a > 30 && r < 50 && b > 140 && g > 60 && b > r + 40 && b + 15 >= g
}

export function stripBubbles(png) {
	const w = png.width
	const h = png.height
	const blue = new Uint8Array(w * h)
	let blueCount = 0
	let opaque = 0
	for (let i = 0; i < w * h; i++) {
		const o = i * 4
		if (png.data[o + 3] > 20) opaque++
		if (isBlue(png.data[o], png.data[o + 1], png.data[o + 2], png.data[o + 3])) {
			blue[i] = 1
			blueCount++
		}
	}
	if (blueCount < 60) return 0
	const mostlyBlue = blueCount > opaque * 0.42
	const seen = new Uint8Array(w * h)
	let removed = 0
	for (let y = 0; y < h; y++) {
		for (let x = 0; x < w; x++) {
			const start = y * w + x
			if (seen[start] || !blue[start]) continue
			const stack = [[x, y]]
			seen[start] = 1
			const pixels = []
			let sx = 0
			let sy = 0
			while (stack.length) {
				const [cx, cy] = stack.pop()
				const p = cy * w + cx
				pixels.push(p)
				sx += cx
				sy += cy
				for (const [nx, ny] of [[cx - 1, cy], [cx + 1, cy], [cx, cy - 1], [cx, cy + 1]]) {
					if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue
					const ni = ny * w + nx
					if (seen[ni] || !blue[ni]) continue
					seen[ni] = 1
					stack.push([nx, ny])
				}
			}
			if (pixels.length < 70 || pixels.length > opaque * 0.34) continue
			const cx = sx / pixels.length
			const cy = sy / pixels.length
			const mark = new Uint8Array(w * h)
			for (const p of pixels) mark[p] = 1
			const near = mark.slice()
			for (let pass = 0; pass < 2; pass++) {
				const grow = []
				for (let py = 1; py < h - 1; py++) {
					for (let px = 1; px < w - 1; px++) {
						const pi = py * w + px
						if (near[pi]) continue
						if (!near[pi - 1] && !near[pi + 1] && !near[pi - w] && !near[pi + w]) continue
						const o = pi * 4
						const r = png.data[o]
						const g = png.data[o + 1]
						const b = png.data[o + 2]
						const a = png.data[o + 3]
						if (a < 20) continue
						const dark = Math.max(r, g, b) < 120 && r < 80
						const cyan = r < 80 && b > r + 15 && b > 60 && b + 40 > g
						if (dark || cyan) grow.push(pi)
					}
				}
				for (const pi of grow) near[pi] = 1
			}
			let open = 0
			for (let a = 0; a < 16; a++) {
				const ang = (a / 16) * Math.PI * 2
				const dx = Math.cos(ang)
				const dy = Math.sin(ang)
				for (let t = 1; t < 90; t++) {
					const px = Math.round(cx + dx * t)
					const py = Math.round(cy + dy * t)
					if (px < 0 || py < 0 || px >= w || py >= h) {
						open++
						break
					}
					const pi = py * w + px
					if (near[pi]) continue
					if (png.data[pi * 4 + 3] < 20) open++
					break
				}
			}
			let probeAir = 0
			let probeBody = 0
			for (const p of pixels) {
				const x = p % w
				const y = (p - x) / w
				let edge = false
				for (const [nx, ny] of [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]]) {
					if (nx < 0 || ny < 0 || nx >= w || ny >= h || !blue[ny * w + nx]) edge = true
				}
				if (!edge) continue
				const vx = x - cx
				const vy = y - cy
				const len = Math.hypot(vx, vy) || 1
				const px = Math.round(x + (vx / len) * 7)
				const py = Math.round(y + (vy / len) * 7)
				if (px < 0 || py < 0 || px >= w || py >= h || png.data[(py * w + px) * 4 + 3] < 20) probeAir++
				else probeBody++
			}
			const poking = pixels.length < 500 && probeAir > 25 && probeAir > probeBody * 0.3 && (!mostlyBlue || pixels.length < 220)
			if (open < 4 && !poking) continue
			for (let pass = 0; pass < 4; pass++) {
				const grow = []
				for (let py = 1; py < h - 1; py++) {
					for (let px = 1; px < w - 1; px++) {
						const pi = py * w + px
						if (near[pi]) continue
						if (!near[pi - 1] && !near[pi + 1] && !near[pi - w] && !near[pi + w]) continue
						const o = pi * 4
						const r = png.data[o]
						const g = png.data[o + 1]
						const b = png.data[o + 2]
						const a = png.data[o + 3]
						if (a < 20 || r > 90) continue
						if (Math.max(r, g, b) < 150 && b > r + 10) grow.push(pi)
					}
				}
				for (const pi of grow) near[pi] = 1
			}
			for (let i = 0; i < near.length; i++) {
				if (!near[i]) continue
				png.data[i * 4 + 3] = 0
				removed++
			}
		}
	}
	return removed
}

export function trimHat(png) {
	let minX = png.width
	let minY = png.height
	let maxX = 0
	let maxY = 0
	let any = false
	for (let y = 0; y < png.height; y++) {
		for (let x = 0; x < png.width; x++) {
			if (png.data[(y * png.width + x) * 4 + 3] < 8) continue
			any = true
			if (x < minX) minX = x
			if (y < minY) minY = y
			if (x > maxX) maxX = x
			if (y > maxY) maxY = y
		}
	}
	if (!any) return png
	minX = Math.max(0, minX - 2)
	minY = Math.max(0, minY - 2)
	maxX = Math.min(png.width - 1, maxX + 2)
	maxY = Math.min(png.height - 1, maxY + 2)
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

const isMain = process.argv[1] && process.argv[1].replaceAll("\\", "/").endsWith("strip_bubbles.mjs")
if (isMain) {
	const files = fs.readdirSync(dir).filter((f) => /^hat_\d+\.png$/.test(f)).sort()
	for (const file of files) {
		const base = file.replace(".png", "")
		if (only.length && !only.includes(base) && !only.includes(file)) continue
		const png = PNG.sync.read(fs.readFileSync(path.join(dir, file)))
		const removed = stripBubbles(png)
		const trimmed = trimHat(png)
		fs.writeFileSync(path.join(dir, file), PNG.sync.write(trimmed))
		if (removed) console.log(`${file} removed ${removed}px -> ${trimmed.width}x${trimmed.height}`)
	}
}
