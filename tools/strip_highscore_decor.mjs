import fs from "fs"
import { PNG } from "pngjs"

const srcPath = "assets/source/highscore_overlay_full.png"
const outPath = "assets/sprites/highscore_overlay.png"
const png = PNG.sync.read(fs.readFileSync(srcPath))
const { width, height, data } = png

function inRoundedRect(x, y, rx, ry, rw, rh, rad) {
	if (x < rx || x > rx + rw || y < ry || y > ry + rh) {
		return false
	}
	const lx = x - rx
	const ly = y - ry
	if (lx >= rad && lx <= rw - rad) {
		return true
	}
	if (ly >= rad && ly <= rh - rad) {
		return true
	}
	const cx = lx < rad ? rad : rw - rad
	const cy = ly < rad ? rad : rh - rad
	const dx = lx - cx
	const dy = ly - cy
	return dx * dx + dy * dy <= rad * rad
}

function inBack(x, y) {
	return inRoundedRect(x, y, 318, 1166, 514, 152, 74)
}

function isWater(r, g, b, a) {
	return a > 40 && r < 160 && b > 160 && g > 100 && b - r > 50 && b - g > 8
}

function isBackArt(r, g, b, a) {
	if (a < 40) {
		return false
	}
	if (r > 200 && g > 200 && b > 200) {
		return true
	}
	if (r > 90 && g > 35 && b < 90 && r > g && r - b > 35) {
		return true
	}
	if (r < 60 && g < 50 && b < 55 && a > 180) {
		return true
	}
	if (r > 180 && g > 140 && b > 80 && b < 170 && r > b) {
		return true
	}
	return false
}

function isBottomDecor(r, g, b, a) {
	if (a < 40) {
		return false
	}
	if (g > r + 20 && g > 55 && b < g + 50) {
		return true
	}
	if (r > 70 && b > 70 && g < Math.min(r, b) - 8) {
		return true
	}
	if (r > 90 && g < 55 && b < 80) {
		return true
	}
	if (Math.abs(r - g) < 28 && Math.abs(g - b) < 34 && r > 50 && r < 210 && Math.max(r, g, b) - Math.min(r, g, b) < 48) {
		return true
	}
	return false
}

for (let y = 0; y < height; y++) {
	for (let x = 0; x < width; x++) {
		const i = (y * width + x) * 4
		const r = data[i]
		const g = data[i + 1]
		const b = data[i + 2]
		const a = data[i + 3]
		if (y < 1110) {
			if (y > 990 && isBottomDecor(r, g, b, a) && !isWater(r, g, b, a)) {
				data[i] = 0
				data[i + 1] = 0
				data[i + 2] = 0
				data[i + 3] = 0
			}
			continue
		}
		if (inBack(x, y) && isBackArt(r, g, b, a)) {
			continue
		}
		if (y < 1152 && isWater(r, g, b, a)) {
			continue
		}
		data[i] = 0
		data[i + 1] = 0
		data[i + 2] = 0
		data[i + 3] = 0
	}
}

fs.writeFileSync(outPath, PNG.sync.write(png))
console.log("wrote", outPath)
