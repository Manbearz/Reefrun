import fs from "fs"
import path from "path"
import { PNG } from "pngjs"
import { fileURLToPath } from "url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const srcPath = path.join(root, "asset sheet.png")
const outDir = path.join(root, "assets", "sprites")
fs.mkdirSync(outDir, { recursive: true })

const png = PNG.sync.read(fs.readFileSync(srcPath))
const { width, height, data } = png

function cropRect(name, x, y, w, h, trim = true) {
	x = Math.max(0, Math.floor(x))
	y = Math.max(0, Math.floor(y))
	w = Math.min(width - x, Math.ceil(w))
	h = Math.min(height - y, Math.ceil(h))
	let minX = w
	let minY = h
	let maxX = -1
	let maxY = -1
	const raw = Buffer.alloc(w * h * 4)
	for (let yy = 0; yy < h; yy++) {
		for (let xx = 0; xx < w; xx++) {
			const si = ((y + yy) * width + (x + xx)) * 4
			const di = (yy * w + xx) * 4
			raw[di] = data[si]
			raw[di + 1] = data[si + 1]
			raw[di + 2] = data[si + 2]
			raw[di + 3] = data[si + 3]
			if (data[si + 3] >= 16) {
				if (xx < minX) minX = xx
				if (yy < minY) minY = yy
				if (xx > maxX) maxX = xx
				if (yy > maxY) maxY = yy
			}
		}
	}
	if (maxX < 0) {
		console.log("empty", name)
		return
	}
	if (!trim) {
		minX = 0
		minY = 0
		maxX = w - 1
		maxY = h - 1
	}
	const tw = maxX - minX + 1
	const th = maxY - minY + 1
	const out = new PNG({ width: tw, height: th })
	for (let yy = 0; yy < th; yy++) {
		for (let xx = 0; xx < tw; xx++) {
			const si = ((minY + yy) * w + (minX + xx)) * 4
			const di = (yy * tw + xx) * 4
			out.data[di] = raw[si]
			out.data[di + 1] = raw[si + 1]
			out.data[di + 2] = raw[si + 2]
			out.data[di + 3] = raw[si + 3]
		}
	}
	const file = path.join(outDir, `${name}.png`)
	fs.writeFileSync(file, PNG.sync.write(out))
	console.log(`${name.padEnd(18)} ${tw}x${th}`)
}

const crops = [
	["fish_blue", 52, 86, 108, 108],
	["fish_clown", 172, 86, 118, 108],
	["fish_yellow", 300, 86, 118, 108],
	["fish_green", 52, 218, 108, 110],
	["fish_pink", 170, 218, 122, 110],
	["fish_purple", 300, 218, 124, 110],
	["pipe_coral", 437, 16, 99, 381],
	["pipe_blue", 555, 17, 95, 382],
	["pipe_wood", 674, 16, 102, 381],
	["pipe_moss", 796, 15, 101, 382],
	["flag_warn", 917, 24, 100, 156],
	["flag_stop", 1034, 24, 109, 156],
	["flag_alert", 1157, 24, 112, 156],
	["spear_short", 980, 170, 315, 95],
	["spear_mid", 900, 268, 395, 100],
	["spear_long", 789, 430, 506, 85],
	["coin", 37, 422, 88, 99],
	["pearl", 148, 423, 92, 94],
	["shell_mystery", 258, 405, 124, 132],
	["bubbles_small", 400, 413, 120, 140],
	["power_shield", 14, 551, 119, 123],
	["power_magnet", 136, 552, 123, 123],
	["power_fish", 258, 551, 116, 123],
	["power_bubble", 376, 557, 107, 109],
	["puffer", 495, 553, 135, 139],
	["jelly", 632, 510, 120, 218],
	["shark", 740, 530, 145, 200],
	["mine", 884, 523, 130, 196],
	["coral_cluster", 1010, 523, 300, 196],
	["btn_play", 16, 711, 118, 115],
	["btn_settings", 136, 711, 118, 115],
	["btn_trophy", 256, 711, 116, 115],
	["btn_close", 371, 711, 119, 115],
	["crown_bronze", 527, 753, 100, 87],
	["crown_silver", 635, 753, 100, 87],
	["crown_gold", 744, 753, 101, 87],
	["splash_a", 860, 730, 90, 90],
	["splash_b", 926, 730, 140, 130],
	["splash_c", 1070, 720, 160, 150],
	["ground", 16, 868, 1280, 158],
	["shell_pink", 16, 1042, 66, 60],
	["shell_blue", 96, 1040, 85, 72],
	["shell_conch", 188, 1035, 76, 69],
	["rock", 286, 1036, 87, 74],
	["chest", 399, 1032, 100, 78],
	["anchor", 520, 1028, 75, 84],
	["skull", 620, 1026, 118, 75],
	["dolphin", 754, 1031, 132, 81],
	["school_a", 900, 1048, 180, 50],
	["shark_far", 1154, 1035, 139, 69],
	["wave", 12, 1116, 400, 80],
	["weed_a", 905, 1116, 88, 72],
	["weed_b", 1010, 1117, 60, 73],
	["coral_purple", 1088, 1115, 71, 76],
	["coral_pink", 1179, 1111, 57, 79],
	["coral_orange", 1248, 1103, 50, 90],
	["weed_c", 607, 1113, 86, 80],
	["weed_d", 517, 1119, 82, 69],
]

for (const [name, x, y, w, h] of crops) {
	cropRect(name, x, y, w, h)
}

cropRect("pipe_coral_body", 456, 80, 60, 24, false)
cropRect("pipe_blue_body", 572, 80, 60, 24, false)
cropRect("pipe_wood_body", 694, 80, 60, 24, false)
cropRect("pipe_moss_body", 816, 80, 60, 24, false)

for (const file of fs.readdirSync(outDir)) {
	if (file.startsWith("sprite_")) {
		fs.unlinkSync(path.join(outDir, file))
	}
}
