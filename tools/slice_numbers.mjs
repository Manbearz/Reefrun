import fs from "fs"
import path from "path"
import { PNG } from "pngjs"
import { fileURLToPath } from "url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const srcPath = path.join(root, "assets", "source", "numbers.png")
const outDir = path.join(root, "assets", "sprites")
const sheetDir = path.join(root, "tools", "number_contact")

const png = PNG.sync.read(fs.readFileSync(srcPath))
const { width, height, data } = png
const PAD = 8

function alphaAt(x, y) {
	if (x < 0 || y < 0 || x >= width || y >= height) return 0
	return data[(y * width + x) * 4 + 3]
}

function topRanges(y0, y1) {
	const ink = new Uint8Array(width)
	for (let x = 0; x < width; x++) {
		for (let y = y0; y < y1; y++) {
			if (alphaAt(x, y) > 60) {
				ink[x] = 1
				break
			}
		}
	}
	const runs = []
	let on = false
	let start = 0
	for (let x = 0; x < width; x++) {
		if (ink[x] && !on) {
			on = true
			start = x
		} else if (!ink[x] && on) {
			on = false
			if (x - start > 8) runs.push([start, x - 1])
		}
	}
	if (on && width - start > 8) runs.push([start, width - 1])
	return runs
}

const DIRS = [
	[1, 0], [-1, 0], [0, 1], [0, -1],
	[1, 1], [1, -1], [-1, 1], [-1, -1],
]

function lumaAt(x, y) {
	const i = (y * width + x) * 4
	return 0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2]
}

function interiorSeeds(y0, y1) {
	let best = null
	for (let lumaMin = 30; lumaMin <= 180; lumaMin += 10) {
		const seen = new Uint8Array(width * (y1 - y0))
		const boxes = []
		for (let y = y0; y < y1; y++) {
			for (let x = 0; x < width; x++) {
				const s = (y - y0) * width + x
				if (seen[s]) continue
				if (alphaAt(x, y) < 160 || lumaAt(x, y) < lumaMin) continue
				let minX = x
				let maxX = x
				let n = 0
				const q = [x, y]
				seen[s] = 1
				for (let h = 0; h < q.length; ) {
					const cx = q[h++]
					const cy = q[h++]
					n++
					if (cx < minX) minX = cx
					if (cx > maxX) maxX = cx
					for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
						const nx = cx + dx
						const ny = cy + dy
						if (nx < 0 || nx >= width || ny < y0 || ny >= y1) continue
						const ns = (ny - y0) * width + nx
						if (seen[ns]) continue
						if (alphaAt(nx, ny) < 160 || lumaAt(nx, ny) < lumaMin) continue
						seen[ns] = 1
						q.push(nx, ny)
					}
				}
				if (n > 5000) boxes.push({ minX, maxX, n, lumaMin })
			}
		}
		boxes.sort((a, b) => a.minX - b.minX)
		if (boxes.length === 10) {
			best = { lumaMin, boxes, seen }
			break
		}
	}
	if (!best) throw new Error(`no separated interiors in y ${y0}-${y1}`)
	return best
}

function labelByInterior(y0, y1, seeds) {
	const h = y1 - y0
	const n = width * h
	const label = new Int16Array(n)
	label.fill(-1)
	const dist = new Uint16Array(n)
	dist.fill(65535)
	const order = seeds.boxes.map((box, index) => ({ box, index })).sort((a, b) => a.box.minX - b.box.minX)
	const digitOf = new Map()
	order.forEach((item, digit) => digitOf.set(item.index, digit))
	for (let y = y0; y < y1; y++) {
		for (let x = 0; x < width; x++) {
			const s = (y - y0) * width + x
			if (!seeds.seen[s]) continue
			let which = -1
			for (let i = 0; i < seeds.boxes.length; i++) {
				const box = seeds.boxes[i]
				if (x >= box.minX && x <= box.maxX) which = digitOf.get(i)
			}
			if (which < 0) continue
			label[s] = which
			dist[s] = 0
		}
	}
	const queue = []
	for (let y = y0; y < y1; y++) {
		for (let x = 0; x < width; x++) {
			if (dist[(y - y0) * width + x] === 0) queue.push(x, y)
		}
	}
	let head = 0
	while (head < queue.length) {
		const x = queue[head++]
		const y = queue[head++]
		const id = label[(y - y0) * width + x]
		for (const [dx, dy] of DIRS) {
			const nx = x + dx
			const ny = y + dy
			if (nx < 0 || nx >= width || ny < y0 || ny >= y1) continue
			if (alphaAt(nx, ny) < 8) continue
			const ni = (ny - y0) * width + nx
			if (label[ni] !== -1) continue
			label[ni] = id
			queue.push(nx, ny)
		}
	}
	let ambiguous = 0
	for (let i = 1; i < order.length; i++) {
		const left = order[i - 1].box.maxX
		const right = order[i].box.minX
		if (right - left < 2) ambiguous++
	}
	return { label, ambiguous, lumaMin: seeds.lumaMin }
}

function boundsOf(label, y0, digit) {
	let minX = width
	let minY = height
	let maxX = -1
	let maxY = -1
	let count = 0
	for (let y = 0; y < label.length / width; y++) {
		for (let x = 0; x < width; x++) {
			if (label[y * width + x] !== digit) continue
			count++
			if (x < minX) minX = x
			if (x > maxX) maxX = x
			const sy = y + y0
			if (sy < minY) minY = sy
			if (sy > maxY) maxY = sy
		}
	}
	return { minX, minY, maxX, maxY, count }
}

function writeDigit(label, y0, digit, globalMinY, globalMaxY, file) {
	const box = boundsOf(label, y0, digit)
	const outW = box.maxX - box.minX + 1 + PAD * 2
	const outH = globalMaxY - globalMinY + 1 + PAD * 2
	const out = new PNG({ width: outW, height: outH })
	out.data.fill(0)
	for (let y = 0; y < label.length / width; y++) {
		for (let x = 0; x < width; x++) {
			if (label[y * width + x] !== digit) continue
			const sy = y + y0
			const si = (sy * width + x) * 4
			const dx = x - box.minX + PAD
			const dy = sy - globalMinY + PAD
			const di = (dy * outW + dx) * 4
			out.data[di] = data[si]
			out.data[di + 1] = data[si + 1]
			out.data[di + 2] = data[si + 2]
			out.data[di + 3] = data[si + 3]
		}
	}
	fs.writeFileSync(file, PNG.sync.write(out))
	return { ...box, outW, outH, bottom: outH - (box.maxY - globalMinY + PAD) }
}

function nearest(src, scale) {
	const out = new PNG({ width: src.width * scale, height: src.height * scale })
	for (let y = 0; y < out.height; y++) {
		for (let x = 0; x < out.width; x++) {
			const sx = Math.min(src.width - 1, Math.floor(x / scale))
			const sy = Math.min(src.height - 1, Math.floor(y / scale))
			const si = (sy * src.width + sx) * 4
			const di = (y * out.width + x) * 4
			out.data[di] = src.data[si]
			out.data[di + 1] = src.data[si + 1]
			out.data[di + 2] = src.data[si + 2]
			out.data[di + 3] = src.data[si + 3]
		}
	}
	return out
}

function blit(dest, src, atX, atY) {
	for (let y = 0; y < src.height; y++) {
		if (atY + y < 0 || atY + y >= dest.height) continue
		for (let x = 0; x < src.width; x++) {
			if (atX + x < 0 || atX + x >= dest.width) continue
			const si = (y * src.width + x) * 4
			if (src.data[si + 3] === 0) continue
			const di = ((atY + y) * dest.width + atX + x) * 4
			const a = src.data[si + 3] / 255
			for (let c = 0; c < 3; c++) {
				dest.data[di + c] = Math.round(src.data[si + c] * a + dest.data[di + c] * (1 - a))
			}
			dest.data[di + 3] = 255
		}
	}
}

function loadPng(file) {
	return PNG.sync.read(fs.readFileSync(file))
}

function contact(files, dest, scale) {
	const glyphs = files.map(loadPng)
	const cellW = Math.max(...glyphs.map((g) => g.width)) * scale + 16
	const cellH = Math.max(...glyphs.map((g) => g.height)) * scale + 16
	const cols = 10
	const rows = Math.ceil(glyphs.length / cols)
	const sheet = new PNG({ width: cols * cellW, height: rows * cellH })
	for (let i = 0; i < sheet.data.length; i += 4) {
		const x = (i / 4) % sheet.width
		const y = Math.floor(i / 4 / sheet.width)
		const check = ((Math.floor(x / 8) + Math.floor(y / 8)) & 1) === 0
		sheet.data[i] = check ? 40 : 210
		sheet.data[i + 1] = check ? 16 : 48
		sheet.data[i + 2] = check ? 56 : 150
		sheet.data[i + 3] = 255
	}
	glyphs.forEach((glyph, i) => {
		const zoom = nearest(glyph, scale)
		const col = i % cols
		const row = Math.floor(i / cols)
		blit(sheet, zoom, col * cellW + Math.floor((cellW - zoom.width) / 2), row * cellH + 8)
	})
	fs.writeFileSync(dest, PNG.sync.write(sheet))
	console.log("sheet", dest, sheet.width, sheet.height)
}

function extract(name, y0, y1, seedY0, seedY1, prefix) {
	const ranges = topRanges(seedY0, seedY1)
	if (ranges.length !== 10) {
		throw new Error(`${name} found ${ranges.length} digits, expected 10`)
	}
	const seeds = interiorSeeds(y0, y1)
	const { label, ambiguous, lumaMin } = labelByInterior(y0, y1, seeds)
	console.log(name, "interior luma", lumaMin, "near gaps", ambiguous)
	let globalMinY = height
	let globalMaxY = -1
	const boxes = []
	for (let digit = 0; digit < 10; digit++) {
		const box = boundsOf(label, y0, digit)
		boxes.push(box)
		if (box.count < 100) throw new Error(`${name} ${digit} is empty`)
		globalMinY = Math.min(globalMinY, box.minY)
		globalMaxY = Math.max(globalMaxY, box.maxY)
		const [rx0, rx1] = ranges[digit]
		if (box.minX > rx0 + 6 || box.maxX < rx1 - 6) {
			console.log(`  ${name} ${digit} top band ${rx0}-${rx1} ink ${box.minX}-${box.maxX}`)
		}
	}
	console.log(name, "ambiguous halo", ambiguous, "baseline", globalMinY, globalMaxY)
	ranges.forEach((range, digit) => {
		console.log(`  ${digit} seed ${range[0]}-${range[1]} ink ${boxes[digit].minX}-${boxes[digit].maxX} y ${boxes[digit].minY}-${boxes[digit].maxY} px ${boxes[digit].count}`)
	})
	for (let digit = 0; digit < 10; digit++) {
		const saved = writeDigit(label, y0, digit, globalMinY, globalMaxY, path.join(outDir, `${prefix}_${digit}.png`))
		if (saved.bottom !== PAD) {
			console.log(`  ${prefix}_${digit} bottom pad ${saved.bottom}`)
		}
	}
	return { ranges, ambiguous }
}

fs.mkdirSync(sheetDir, { recursive: true })
const beforeSheet = path.join(sheetDir, "before_8x.png")
if (!fs.existsSync(beforeSheet)) {
	const beforeFiles = []
	for (const prefix of ["num_gold", "num_white"]) {
		for (let digit = 0; digit < 10; digit++) beforeFiles.push(path.join(outDir, `${prefix}_${digit}.png`))
	}
	contact(beforeFiles, beforeSheet, 8)
}

const gold = extract("gold", 50, 372, 90, 160, "num_gold")
const white = extract("white", 370, 700, 400, 470, "num_white")
const afterFiles = []
for (const prefix of ["num_gold", "num_white"]) {
	for (let digit = 0; digit < 10; digit++) afterFiles.push(path.join(outDir, `${prefix}_${digit}.png`))
}
contact(afterFiles, path.join(sheetDir, "after_8x.png"), 8)

const samples = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "22", "88", "99", "100", "300", "1000", "8888", "9999", "0/2", "1/2", "2/2", "0/10", "9/10", "10/10"]
const slash = loadPng(path.join(outDir, "alpha_slash.png"))
const whiteGlyphs = {}
for (let digit = 0; digit < 10; digit++) whiteGlyphs[String(digit)] = loadPng(path.join(outDir, `num_white_${digit}.png`))
const sampleHeight = whiteGlyphs["0"].height
let sampleW = 24
const rendered = samples.map((text) => {
	let w = 0
	for (const ch of text) w += ch === "/" ? slash.width : whiteGlyphs[ch].width
	sampleW = Math.max(sampleW, w + 32)
	return text
})
const sampleScale = 3
const sampleSheet = new PNG({ width: sampleW * sampleScale, height: (sampleHeight + 24) * rendered.length * sampleScale })
for (let i = 0; i < sampleSheet.data.length; i += 4) {
	sampleSheet.data[i] = 18
	sampleSheet.data[i + 1] = 28
	sampleSheet.data[i + 2] = 42
	sampleSheet.data[i + 3] = 255
}
rendered.forEach((text, row) => {
	let x = 16
	for (const ch of text) {
		const glyph = ch === "/" ? slash : whiteGlyphs[ch]
		const zoom = nearest(glyph, sampleScale)
		blit(sampleSheet, zoom, x * sampleScale, (row * (sampleHeight + 24) + 12) * sampleScale)
		x += glyph.width
	}
})
fs.writeFileSync(path.join(sheetDir, "samples_nearest.png"), PNG.sync.write(sampleSheet))
console.log("samples", sampleSheet.width, sampleSheet.height)
console.log("gold ambiguous", gold.ambiguous, "white ambiguous", white.ambiguous)
