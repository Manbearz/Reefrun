import fs from "fs"
import path from "path"
import { PNG } from "pngjs"
import { fileURLToPath } from "url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const srcPath = path.join(root, "assets", "source", "alphabet.png")
const outDir = path.join(root, "assets", "sprites")

const png = PNG.sync.read(fs.readFileSync(srcPath))
const { width, height, data } = png

function alphaAt(x, y) {
	return data[(y * width + x) * 4 + 3]
}

function components(y0, y1, minCount = 80) {
	const seen = new Uint8Array(width * (y1 - y0))
	const blobs = []
	for (let y = y0; y < y1; y++) {
		for (let x = 0; x < width; x++) {
			const li = (y - y0) * width + x
			if (seen[li] || alphaAt(x, y) < 16) continue
			const stack = [[x, y]]
			const pixels = []
			let minX = x
			let maxX = x
			let minY = y
			let maxY = y
			while (stack.length) {
				const [cx, cy] = stack.pop()
				const idx = (cy - y0) * width + cx
				if (cx < 0 || cy < y0 || cx >= width || cy >= y1 || seen[idx]) continue
				if (alphaAt(cx, cy) < 16) continue
				seen[idx] = 1
				pixels.push(cy * width + cx)
				if (cx < minX) minX = cx
				if (cx > maxX) maxX = cx
				if (cy < minY) minY = cy
				if (cy > maxY) maxY = cy
				stack.push([cx - 1, cy], [cx + 1, cy], [cx, cy - 1], [cx, cy + 1])
			}
			if (pixels.length < minCount) continue
			blobs.push(makeBlob(pixels, minX, minY, maxX, maxY))
		}
	}
	return blobs
}

function makeBlob(pixels, minX, minY, maxX, maxY) {
	return {
		pixels,
		minX,
		minY,
		maxX,
		maxY,
		w: maxX - minX + 1,
		h: maxY - minY + 1,
		cx: (minX + maxX) / 2,
		count: pixels.length,
	}
}

function overlapX(a, b) {
	const o = Math.min(a.maxX, b.maxX) - Math.max(a.minX, b.minX)
	return o / Math.min(a.w, b.w)
}

function mergeBlobs(a, b) {
	return makeBlob(
		a.pixels.concat(b.pixels),
		Math.min(a.minX, b.minX),
		Math.min(a.minY, b.minY),
		Math.max(a.maxX, b.maxX),
		Math.max(a.maxY, b.maxY),
	)
}

function mergeVertical(blobs) {
	const used = new Array(blobs.length).fill(false)
	const out = []
	for (let i = 0; i < blobs.length; i++) {
		if (used[i]) continue
		let g = blobs[i]
		used[i] = true
		let changed = true
		while (changed) {
			changed = false
			for (let j = 0; j < blobs.length; j++) {
				if (used[j]) continue
				if (overlapX(g, blobs[j]) > 0.35) {
					g = mergeBlobs(g, blobs[j])
					used[j] = true
					changed = true
				}
			}
		}
		out.push(g)
	}
	return out.sort((a, b) => a.cx - b.cx)
}

function valleyX(blob) {
	const sums = new Float64Array(blob.w)
	for (const idx of blob.pixels) {
		const x = idx % width
		sums[x - blob.minX] += 1
	}
	const lo = Math.floor(blob.w * 0.32)
	const hi = Math.ceil(blob.w * 0.68)
	let minV = Infinity
	let minX = blob.minX + ((blob.w / 2) | 0)
	for (let i = lo; i < hi; i++) {
		if (sums[i] < minV) {
			minV = sums[i]
			minX = blob.minX + i
		}
	}
	return minX
}

function splitBlob(blob) {
	const cut = valleyX(blob)
	const left = []
	const right = []
	for (const idx of blob.pixels) {
		const x = idx % width
		if (x <= cut) left.push(idx)
		else right.push(idx)
	}
	if (left.length < 80 || right.length < 80) return null
	const inset = 5
	const leftKeep = left.filter((idx) => (idx % width) <= cut - inset)
	const rightKeep = right.filter((idx) => (idx % width) >= cut + inset)
	if (leftKeep.length < 80 || rightKeep.length < 80) return null
	const bounds = (pixels) => {
		let minX = width
		let minY = height
		let maxX = 0
		let maxY = 0
		for (const idx of pixels) {
			const x = idx % width
			const y = (idx / width) | 0
			if (x < minX) minX = x
			if (x > maxX) maxX = x
			if (y < minY) minY = y
			if (y > maxY) maxY = y
		}
		return makeBlob(pixels, minX, minY, maxX, maxY)
	}
	return [bounds(leftKeep), bounds(rightKeep)]
}

function splitUntil(blobs, expected) {
	const out = blobs.slice()
	while (out.length < expected) {
		let wide = 0
		for (let i = 1; i < out.length; i++) {
			if (out[i].w > out[wide].w) wide = i
		}
		const parts = splitBlob(out[wide])
		if (!parts) break
		out.splice(wide, 1, parts[0], parts[1])
		out.sort((a, b) => a.cx - b.cx)
	}
	return out
}

function writeGlyph(name, blob) {
	const pad = 1
	const minX = Math.max(0, blob.minX - pad)
	const minY = Math.max(0, blob.minY - pad)
	const maxX = Math.min(width - 1, blob.maxX + pad)
	const maxY = Math.min(height - 1, blob.maxY + pad)
	const keep = new Set(blob.pixels)
	const w = maxX - minX + 1
	const h = maxY - minY + 1
	const out = new PNG({ width: w, height: h })
	for (let y = 0; y < h; y++) {
		for (let x = 0; x < w; x++) {
			const gx = minX + x
			const gy = minY + y
			const srcIdx = gy * width + gx
			const di = (y * w + x) * 4
			if (!keep.has(srcIdx)) continue
			const si = srcIdx * 4
			out.data[di] = data[si]
			out.data[di + 1] = data[si + 1]
			out.data[di + 2] = data[si + 2]
			out.data[di + 3] = data[si + 3]
		}
	}
	fs.writeFileSync(path.join(outDir, `${name}.png`), PNG.sync.write(out))
	console.log(`${name} ${w}x${h}`)
}

function sliceRow(y0, y1, names) {
	let blobs = mergeVertical(components(y0, y1)).filter((b) => b.h > 20 && b.count > 200)
	blobs = splitUntil(blobs, names.length)
	if (blobs.length !== names.length) {
		throw new Error(`row ${names[0]} expected ${names.length}, got ${blobs.length}: ${blobs.map((b) => Math.round(b.cx) + ":" + b.w).join(" ")}`)
	}
	for (let i = 0; i < names.length; i++) writeGlyph(names[i], blobs[i])
}

fs.mkdirSync(outDir, { recursive: true })
sliceRow(10, 187, [..."ABCDEFGHI"].map((ch) => `alpha_${ch}`))
sliceRow(195, 368, [..."JKLMNOPQR"].map((ch) => `alpha_${ch}`))
sliceRow(377, 550, [..."STUVWXYZ"].map((ch) => `alpha_${ch}`))
sliceRow(742, 888, [
	"alpha_excl",
	"alpha_at",
	"alpha_hash",
	"alpha_dollar",
	"alpha_pct",
	"alpha_caret",
	"alpha_amp",
	"alpha_star",
	"alpha_lparen",
	"alpha_rparen",
	"alpha_quest",
])
sliceRow(888, 1012, [
	"alpha_colon",
	"alpha_semi",
	"alpha_tilde",
	"alpha_slash",
	"alpha_bslash",
	"alpha_comma",
	"alpha_hyphen",
	"alpha_dash",
	"alpha_plus",
	"alpha_eq",
])
