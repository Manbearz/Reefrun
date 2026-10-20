import fs from "fs"
import path from "path"
import { PNG } from "pngjs"
import { fileURLToPath } from "url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const src = PNG.sync.read(fs.readFileSync(path.join(root, "assets", "source", "mission icons.png")))
const { width, height, data } = src
const outDir = path.join(root, "assets", "ui", "mission_icons")
fs.rmSync(outDir, { recursive: true, force: true })
fs.mkdirSync(outDir, { recursive: true })

function alphaAt(x, y) {
	if (x < 0 || y < 0 || x >= width || y >= height) return 0
	return data[(y * width + x) * 4 + 3]
}

function columnRuns(y0, y1) {
	const counts = new Array(width).fill(0)
	for (let y = y0; y < y1; y++) {
		for (let x = 0; x < width; x++) {
			if (alphaAt(x, y) > 30) counts[x]++
		}
	}
	const runs = []
	let start = -1
	for (let x = 0; x <= width; x++) {
		const on = x < width && counts[x] > 3
		if (on && start < 0) start = x
		if (!on && start >= 0) {
			runs.push([start, x - 1])
			start = -1
		}
	}
	return runs
}

function tightBounds(x0, x1, y0, y1) {
	let minX = x1
	let minY = y1
	let maxX = x0
	let maxY = y0
	for (let y = y0; y < y1; y++) {
		for (let x = x0; x <= x1; x++) {
			if (alphaAt(x, y) <= 20) continue
			if (x < minX) minX = x
			if (x > maxX) maxX = x
			if (y < minY) minY = y
			if (y > maxY) maxY = y
		}
	}
	if (maxX < minX) return null
	return { minX, minY, maxX, maxY }
}

function keepArrowColor(name, side) {
	const file = path.join(outDir, name + ".png")
	const icon = PNG.sync.read(fs.readFileSync(file))
	const maxChannel = (y, channel) => {
		let max = 0
		for (let x = 0; x < icon.width; x++) {
			const i = (y * icon.width + x) * 4
			if (icon.data[i + 3] > 20 && icon.data[i + channel] > max) max = icon.data[i + channel]
		}
		return max
	}
	if (side === "left") {
		for (let y = 0; y < icon.height; y++) {
			if (maxChannel(y, 0) > 160) break
			for (let x = 0; x < icon.width; x++) icon.data[(y * icon.width + x) * 4 + 3] = 0
		}
	} else {
		for (let y = icon.height - 1; y >= 0; y--) {
			if (maxChannel(y, 2) > 160) break
			for (let x = 0; x < icon.width; x++) icon.data[(y * icon.width + x) * 4 + 3] = 0
		}
	}
	for (let i = 0; i < icon.data.length; i += 4) {
		const r = icon.data[i]
		const b = icon.data[i + 2]
		if (side === "left" ? b > r + 8 : r > b + 8) icon.data[i + 3] = 0
	}
	let minX = icon.width
	let minY = icon.height
	let maxX = 0
	let maxY = 0
	for (let y = 0; y < icon.height; y++) {
		for (let x = 0; x < icon.width; x++) {
			if (icon.data[(y * icon.width + x) * 4 + 3] <= 20) continue
			if (x < minX) minX = x
			if (x > maxX) maxX = x
			if (y < minY) minY = y
			if (y > maxY) maxY = y
		}
	}
	const pad = 2
	const w = maxX - minX + 1 + pad * 2
	const h = maxY - minY + 1 + pad * 2
	const trimmed = new PNG({ width: w, height: h })
	for (let y = 0; y < h; y++) {
		for (let x = 0; x < w; x++) {
			const sx = minX - pad + x
			const sy = minY - pad + y
			const di = (y * w + x) * 4
			if (sx < 0 || sy < 0 || sx >= icon.width || sy >= icon.height) continue
			const si = (sy * icon.width + sx) * 4
			trimmed.data[di] = icon.data[si]
			trimmed.data[di + 1] = icon.data[si + 1]
			trimmed.data[di + 2] = icon.data[si + 2]
			trimmed.data[di + 3] = icon.data[si + 3]
		}
	}
	fs.writeFileSync(file, PNG.sync.write(trimmed))
	console.log("trimmed", name, `${w}x${h}`)
}

function writeIcon(name, bounds) {
	const pad = 2
	const w = bounds.maxX - bounds.minX + 1 + pad * 2
	const h = bounds.maxY - bounds.minY + 1 + pad * 2
	const png = new PNG({ width: w, height: h })
	for (let y = 0; y < h; y++) {
		for (let x = 0; x < w; x++) {
			const sx = bounds.minX - pad + x
			const sy = bounds.minY - pad + y
			const di = (y * w + x) * 4
			if (sx < 0 || sy < 0 || sx >= width || sy >= height) {
				png.data[di + 3] = 0
				continue
			}
			const si = (sy * width + sx) * 4
			png.data[di] = data[si]
			png.data[di + 1] = data[si + 1]
			png.data[di + 2] = data[si + 2]
			png.data[di + 3] = data[si + 3]
		}
	}
	fs.writeFileSync(path.join(outDir, name + ".png"), PNG.sync.write(png))
	console.log(name, `${w}x${h}`, "from", bounds.minX, bounds.minY, bounds.maxX, bounds.maxY)
	return png
}

function splitArrows(bounds) {
	const rows = []
	for (let y = bounds.minY; y <= bounds.maxY; y++) {
		let count = 0
		for (let x = bounds.minX; x <= bounds.maxX; x++) {
			if (alphaAt(x, y) > 30) count++
		}
		rows.push(count)
	}
	let bestAt = -1
	let bestCount = Infinity
	const from = Math.floor(rows.length * 0.35)
	const to = Math.floor(rows.length * 0.65)
	for (let i = from; i < to; i++) {
		if (rows[i] < bestCount) {
			bestCount = rows[i]
			bestAt = i
		}
	}
	if (bestAt < 0) throw new Error("arrows did not split")
	const cut = bounds.minY + bestAt
	const top = tightBounds(bounds.minX, bounds.maxX, bounds.minY, cut)
	const bottom = tightBounds(bounds.minX, bounds.maxX, cut + 1, bounds.maxY + 1)
	return { top, bottom }
}

const bands = [
	{
		y0: 100,
		y1: 310,
		names: ["pipes", "complete_runs", "high_score", "earn_score", "top_score", "collect_coins", "collect_x_coins", "find_treasure"],
	},
	{
		y0: 320,
		y1: 530,
		names: ["enter_deep_dive", "time_in_deep_dive", "complete_deep_dives", "change_lanes", "mine", "pass_jellyfish", "pass_coral", "pass_rocks", "pass_seaweed"],
	},
	{
		y0: 545,
		y1: 730,
		names: ["collect_magnets", "collect_pearls", "collect_special_items", "use_bubble_shields", "use_boosts", "use_power_ups", "time_survival", "find_secrets", "any_fish"],
	},
	{
		y0: 760,
		y1: 960,
		names: ["play_daily", "survive_x_seconds", "swim_distance", "survive_without_hitting", "explore", "mystery_mission", "ocean_exploration"],
	},
]

const written = new Map()
for (const band of bands) {
	const runs = columnRuns(band.y0, band.y1)
	if (runs.length !== band.names.length) {
		throw new Error(`row ${band.y0} found ${runs.length} icons, expected ${band.names.length}`)
	}
	runs.forEach((run, index) => {
		const name = band.names[index]
		const bounds = tightBounds(run[0], run[1], band.y0, band.y1)
		written.set(name, writeIcon(name, bounds))
		if (name === "change_lanes") {
			const parts = splitArrows(bounds)
			written.set("move_right", writeIcon("move_right", parts.top))
			written.set("move_left", writeIcon("move_left", parts.bottom))
			keepArrowColor("move_right", "right")
			keepArrowColor("move_left", "left")
		}
	})
}

const aliases = {
	dodge_obstacles: "mine",
	jellyfish_scene: "pass_jellyfish",
	bubbles: "complete_deep_dives",
	use_magnets: "collect_magnets",
	change_lanes_pair: "change_lanes",
	complete_special_goals: "find_secrets",
	time_in_deep_dive: "time_in_deep_dive",
}
for (const [alias, source] of Object.entries(aliases)) {
	if (alias === source) continue
	fs.copyFileSync(path.join(outDir, source + ".png"), path.join(outDir, alias + ".png"))
	console.log("alias", alias, "<-", source)
}

const sheet = new PNG({ width: 8 * 180, height: 5 * 180 })
for (let i = 0; i < sheet.data.length; i += 4) {
	sheet.data[i] = 255
	sheet.data[i + 1] = 0
	sheet.data[i + 2] = 255
	sheet.data[i + 3] = 255
}
const order = [
	"pipes", "complete_runs", "high_score", "earn_score", "top_score", "collect_coins", "collect_x_coins", "find_treasure",
	"enter_deep_dive", "time_in_deep_dive", "complete_deep_dives", "change_lanes", "move_left", "move_right", "mine", "pass_jellyfish",
	"pass_coral", "pass_rocks", "pass_seaweed", "collect_magnets", "collect_pearls", "collect_special_items", "use_bubble_shields", "use_boosts",
	"use_power_ups", "time_survival", "find_secrets", "any_fish", "play_daily", "survive_x_seconds", "swim_distance", "survive_without_hitting",
	"explore", "mystery_mission", "ocean_exploration", "dodge_obstacles",
]
order.forEach((name, index) => {
	const icon = PNG.sync.read(fs.readFileSync(path.join(outDir, name + ".png")))
	const col = index % 8
	const row = Math.floor(index / 8)
	const dx = col * 180 + Math.floor((180 - icon.width) / 2)
	const dy = row * 180 + Math.floor((180 - icon.height) / 2)
	for (let y = 0; y < icon.height; y++) {
		for (let x = 0; x < icon.width; x++) {
			const si = (y * icon.width + x) * 4
			const a = icon.data[si + 3] / 255
			const di = ((dy + y) * sheet.width + (dx + x)) * 4
			sheet.data[di] = Math.round(icon.data[si] * a + sheet.data[di] * (1 - a))
			sheet.data[di + 1] = Math.round(icon.data[si + 1] * a + sheet.data[di + 1] * (1 - a))
			sheet.data[di + 2] = Math.round(icon.data[si + 2] * a + sheet.data[di + 2] * (1 - a))
		}
	}
})
fs.writeFileSync(path.join(root, "tools", "probe_icon_sheet.png"), PNG.sync.write(sheet))
console.log("icons", fs.readdirSync(outDir).filter((name) => name.endsWith(".png")).length)
