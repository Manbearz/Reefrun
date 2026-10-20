import fs from "fs"
import path from "path"
import { PNG } from "pngjs"
import { fileURLToPath } from "url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const srcPath = path.join(root, "assets", "source", "asset-sheet-2.png")
const outDir = path.join(root, "assets", "deep_dive")

// Tight bounds from an alpha flood fill of asset-sheet-2.png (1536x1024, real transparency).
const CROPS = [
	["banner_deep_dive", 49, 18, 452, 192],
	["banner_seconds", 555, 27, 419, 181],
	["count_3", 1037, 27, 117, 183],
	["count_2", 1208, 26, 118, 184],
	["count_1", 1375, 27, 115, 184],
	["net_a", 30, 215, 247, 183],
	["net_b", 284, 215, 241, 224],
	["net_c", 542, 215, 227, 178],
	["net_d", 793, 216, 177, 210],
	["mine_chain_a", 978, 216, 122, 256],
	["mine_a", 1118, 215, 109, 111],
	["mine_b", 1241, 223, 101, 102],
	["mine_chain_b", 1338, 224, 176, 290],
	["mine_c", 1101, 342, 134, 129],
	["mine_d", 1241, 392, 88, 88],
	["rock_a", 30, 360, 126, 262],
	["rock_b", 156, 402, 132, 223],
	["rock_c", 300, 408, 118, 213],
	["rock_d", 423, 450, 74, 139],
	["rock_e", 494, 377, 110, 277],
	["rock_f", 606, 401, 127, 245],
	["rock_g", 746, 389, 92, 213],
	["rock_h", 881, 386, 116, 125],
	["arch", 809, 527, 284, 308],
	["planks", 1258, 454, 252, 228],
	["spears", 1200, 647, 306, 268],
	["jelly_purple", 46, 630, 89, 176],
	["jelly_blue", 154, 646, 79, 158],
	["jelly_orange", 262, 634, 83, 176],
	["jelly_small", 374, 667, 64, 138],
	["bubbles_a", 474, 645, 53, 104],
	["bubbles_b", 554, 666, 46, 132],
	["bubbles_c", 637, 655, 54, 178],
	["bubbles_d", 721, 669, 45, 158],
	["seaweed_a", 30, 817, 92, 100],
	["coral_a", 133, 815, 76, 101],
	["coral_b", 219, 825, 71, 92],
	["coral_c", 302, 817, 64, 102],
	["coral_d", 377, 817, 67, 98],
	["seaweed_b", 512, 826, 57, 103],
	["seaweed_c", 581, 815, 75, 114],
	["seaweed_d", 672, 816, 66, 112],
	["seaweed_e", 752, 815, 66, 107],
]

const png = PNG.sync.read(fs.readFileSync(srcPath))
fs.mkdirSync(outDir, { recursive: true })

const labels = new Int32Array(png.width * png.height)
let nextLabel = 1

function alphaAt(x, y) {
	return png.data[(y * png.width + x) * 4 + 3]
}

function flood(sx, sy, label) {
	const stack = [[sx, sy]]
	labels[sy * png.width + sx] = label
	while (stack.length) {
		const [x, y] = stack.pop()
		const nbs = [
			[x - 1, y],
			[x + 1, y],
			[x, y - 1],
			[x, y + 1],
		]
		for (const [nx, ny] of nbs) {
			if (nx < 0 || ny < 0 || nx >= png.width || ny >= png.height) continue
			const idx = ny * png.width + nx
			if (labels[idx] || alphaAt(nx, ny) < 16) continue
			labels[idx] = label
			stack.push([nx, ny])
		}
	}
}

for (let y = 0; y < png.height; y++) {
	for (let x = 0; x < png.width; x++) {
		const idx = y * png.width + x
		if (labels[idx] || alphaAt(x, y) < 16) continue
		flood(x, y, nextLabel++)
	}
}

function cropOf(rect) {
	const [name, x, y, w, h] = rect
	const votes = new Map()
	for (let yy = 0; yy < h; yy++) {
		for (let xx = 0; xx < w; xx++) {
			const label = labels[(y + yy) * png.width + (x + xx)]
			if (!label) continue
			votes.set(label, (votes.get(label) || 0) + 1)
		}
	}
	let best = 0
	let bestN = 0
	for (const [label, count] of votes) {
		if (count > bestN) {
			best = label
			bestN = count
		}
	}
	if (!best) throw new Error(`empty crop ${name}`)
	let minX = png.width
	let minY = png.height
	let maxX = 0
	let maxY = 0
	for (let sy = 0; sy < png.height; sy++) {
		for (let sx = 0; sx < png.width; sx++) {
			if (labels[sy * png.width + sx] !== best) continue
			if (sx < minX) minX = sx
			if (sy < minY) minY = sy
			if (sx > maxX) maxX = sx
			if (sy > maxY) maxY = sy
		}
	}
	const tw = maxX - minX + 1
	const th = maxY - minY + 1
	const out = new PNG({ width: tw, height: th })
	for (let yy = 0; yy < th; yy++) {
		for (let xx = 0; xx < tw; xx++) {
			const sx = minX + xx
			const sy = minY + yy
			if (labels[sy * png.width + sx] !== best) continue
			const src = (sy * png.width + sx) * 4
			const dst = (yy * tw + xx) * 4
			out.data[dst] = png.data[src]
			out.data[dst + 1] = png.data[src + 1]
			out.data[dst + 2] = png.data[src + 2]
			out.data[dst + 3] = png.data[src + 3]
		}
	}
	return { name, png: out, w: tw, h: th }
}

const sprites = CROPS.map(cropOf)
for (const sprite of sprites) {
	const file = path.join(outDir, `${sprite.name}.png`)
	fs.writeFileSync(file, PNG.sync.write(sprite.png))
	console.log(`${sprite.name}\t${sprite.w}x${sprite.h}`)
}

const cols = 8
const cell = 180
const rows = Math.ceil(sprites.length / cols)
const sheet = new PNG({ width: cols * cell, height: rows * cell })
for (let i = 0; i < sheet.data.length; i += 4) {
	sheet.data[i] = 18
	sheet.data[i + 1] = 24
	sheet.data[i + 2] = 36
	sheet.data[i + 3] = 255
}
sprites.forEach((sprite, index) => {
	const col = index % cols
	const row = Math.floor(index / cols)
	const scale = Math.min((cell - 12) / sprite.w, (cell - 12) / sprite.h)
	const dw = Math.max(1, Math.round(sprite.w * scale))
	const dh = Math.max(1, Math.round(sprite.h * scale))
	const ox = col * cell + Math.floor((cell - dw) / 2)
	const oy = row * cell + Math.floor((cell - dh) / 2)
	for (let yy = 0; yy < dh; yy++) {
		for (let xx = 0; xx < dw; xx++) {
			const sx = Math.min(sprite.w - 1, Math.floor(xx / scale))
			const sy = Math.min(sprite.h - 1, Math.floor(yy / scale))
			const src = (sy * sprite.w + sx) * 4
			const a = sprite.png.data[src + 3] / 255
			if (a <= 0) continue
			const dst = ((oy + yy) * sheet.width + (ox + xx)) * 4
			sheet.data[dst] = Math.round(sprite.png.data[src] * a + sheet.data[dst] * (1 - a))
			sheet.data[dst + 1] = Math.round(sprite.png.data[src + 1] * a + sheet.data[dst + 1] * (1 - a))
			sheet.data[dst + 2] = Math.round(sprite.png.data[src + 2] * a + sheet.data[dst + 2] * (1 - a))
			sheet.data[dst + 3] = 255
		}
	}
})
const preview = path.join(root, "tools", "_deep_dive_preview.png")
fs.writeFileSync(preview, PNG.sync.write(sheet))
console.log(`preview ${preview} ${sprites.length}`)
