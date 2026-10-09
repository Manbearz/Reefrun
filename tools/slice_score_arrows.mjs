import fs from "fs"
import { PNG } from "pngjs"

const src = PNG.sync.read(fs.readFileSync("assets/source/scoreboard overlay buttons.png"))
const { width, height, data } = src
const mid = Math.floor(width / 2)
console.log("sheet", width, height)

function crop(x0, x1, name) {
	let minX = x1
	let minY = height
	let maxX = x0
	let maxY = 0
	for (let y = 0; y < height; y++) {
		for (let x = x0; x < x1; x++) {
			if (data[(y * width + x) * 4 + 3] < 10) {
				continue
			}
			minX = Math.min(minX, x)
			minY = Math.min(minY, y)
			maxX = Math.max(maxX, x)
			maxY = Math.max(maxY, y)
		}
	}
	const pad = 4
	minX = Math.max(x0, minX - pad)
	minY = Math.max(0, minY - pad)
	maxX = Math.min(x1 - 1, maxX + pad)
	maxY = Math.min(height - 1, maxY + pad)
	const w = maxX - minX + 1
	const h = maxY - minY + 1
	const out = new PNG({ width: w, height: h })
	for (let y = 0; y < h; y++) {
		for (let x = 0; x < w; x++) {
			const si = ((minY + y) * width + (minX + x)) * 4
			const di = (y * w + x) * 4
			out.data[di] = data[si]
			out.data[di + 1] = data[si + 1]
			out.data[di + 2] = data[si + 2]
			out.data[di + 3] = data[si + 3]
		}
	}
	const dest = `assets/sprites/${name}.png`
	fs.writeFileSync(dest, PNG.sync.write(out))
	console.log(name, w, h, "from", minX, minY)
}

crop(0, mid, "btn_score_left")
crop(mid, width, "btn_score_right")
