const DT = 1 / 60
const GRAVITY = 1840
const FLAP = 573
const TERMINAL = 1040
const VIEW_H = 960
const PLAY_TOP = 53
const PLAY_BOTTOM = 803
const PIPE_SPEED = 200
const GAP = 211
const FIRST_PIPE = 1.8
const PIPE_INTERVAL = 1.5
const FISH_HIT = 18
const GHOST_COUNT = 99
const RISE = (FLAP * FLAP) / (2 * GRAVITY)
const SEEDS = [1, 17, 827361, 424242, 777001]

function mulberry32(a) {
	return function rand() {
		a |= 0
		a = (a + 0x6d2b79f5) | 0
		let t = Math.imul(a ^ (a >>> 15), 1 | a)
		t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296
	}
}

function clampf(v, lo, hi) {
	return Math.min(hi, Math.max(lo, v))
}

function makeLayout(seed) {
	const rand = mulberry32(seed >>> 0)
	const layout = []
	let x = PIPE_SPEED * FIRST_PIPE
	for (let i = 0; i < 80; i++) {
		const gap = GAP - Math.min(Math.floor(i / 18), 18)
		const slot = Math.floor(rand() * 5)
		const half = gap * 0.5
		const pad = FISH_HIT + 8
		const top = PLAY_TOP + half + pad
		const bottom = PLAY_BOTTOM - half - pad
		const gap_y = top + (bottom - top) * (slot / 4)
		layout.push({ x, gap_y, gap_h: gap })
		x += PIPE_SPEED * PIPE_INTERVAL
	}
	return layout
}

function randfn(rand) {
	const u = Math.max(1e-9, rand())
	const v = rand()
	return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v)
}

function flapsFor(layout, deathTick, rand) {
	const flaps = []
	let y = VIEW_H * 0.42
	let v = 0
	let cooldown = 0
	let pipeI = 0
	const skill = clampf(randfn(rand) * 0.18 + 0.58, 0.18, 0.92)
	for (let t = 0; t <= deathTick; t++) {
		while (pipeI + 1 < layout.length && layout[pipeI].x < PIPE_SPEED * t * DT - 20) {
			pipeI++
		}
		const gapY = pipeI < layout.length ? layout[pipeI].gap_y : VIEW_H * 0.42
		const bias = (0.5 - skill) * 24
		const target = gapY + bias
		const want = t === 0 || (cooldown <= 0 && wantFlap(y, v, target))
		if (want) {
			v = -FLAP
			flaps.push(t)
			cooldown = 18 + Math.round((1 - skill) * 10)
		} else {
			cooldown = Math.max(0, cooldown - 1)
		}
		v = Math.min(v + GRAVITY * DT, TERMINAL)
		y += v * DT
	}
	return flaps
}

function wantFlap(y, v, target) {
	if (y - RISE < PLAY_TOP + 4) {
		return false
	}
	if (!(v > 0)) {
		return false
	}
	if (y > PLAY_BOTTOM - 72) {
		return true
	}
	return y >= target + 8
}

function rollDeath(rand) {
	const u = rand()
	if (u < 0.2) return 0
	if (u < 0.45) return 1
	if (u < 0.66) return 2
	if (u < 0.8) return 3
	if (u < 0.9) return 4
	if (u < 0.96) return 5 + Math.floor(rand() * 4)
	return 9 + Math.floor(rand() * 20)
}

function simulate(flaps, deathTick) {
	let y = VIEW_H * 0.42
	let v = 0
	let fi = 0
	let minY = y
	let maxY = y
	const ys = [y]
	for (let t = 0; t <= deathTick; t++) {
		while (fi < flaps.length && flaps[fi] < t) {
			fi++
		}
		if (fi < flaps.length && flaps[fi] === t) {
			v = -FLAP
			fi++
		}
		v = Math.min(v + GRAVITY * DT, TERMINAL)
		y += v * DT
		minY = Math.min(minY, y)
		maxY = Math.max(maxY, y)
		ys.push(y)
	}
	return { minY, maxY, ys }
}

function hasClimb(flaps) {
	if (flaps.length < 5) return false
	const step = flaps[1] - flaps[0]
	if (step < 20 || step > 34) return false
	let same = 0
	for (let i = 1; i < flaps.length; i++) {
		if (Math.abs(flaps[i] - flaps[i - 1] - step) <= 1) same++
	}
	return same >= flaps.length - 2
}

function gapFollow(layout, ys, deathTick) {
	let checks = 0
	let hits = 0
	const deathX = PIPE_SPEED * deathTick * DT
	for (const spec of layout) {
		if (spec.x + 40 >= deathX) break
		const t = Math.round(spec.x / (PIPE_SPEED * DT))
		if (t < 0 || t >= ys.length) continue
		checks++
		if (Math.abs(ys[t] - spec.gap_y) <= spec.gap_h * 0.5 + 18) hits++
	}
	return { checks, hits }
}

let ok = true
let runs = 0
let totalFlaps = 0
let worstMin = 9999
let worstMax = -9999
let boundHits = 0
let climbHits = 0
let gapChecks = 0
let gapHits = 0

for (const seed of SEEDS) {
	const layout = makeLayout(seed)
	for (let slot = 0; slot < GHOST_COUNT; slot++) {
		const rand = mulberry32((seed * 10007 + slot * 131 + 17) >>> 0)
		const deathPipe = rollDeath(rand)
		const first = Math.round(FIRST_PIPE * 60)
		const interval = Math.round(PIPE_INTERVAL * 60)
		const deathTick = Math.max(1, first + deathPipe * interval + 8 + Math.floor(rand() * 35))
		const flaps = flapsFor(layout, deathTick, rand)
		if (flaps[0] !== 0) {
			console.error("missing tick-0", seed, slot)
			ok = false
		}
		const path = simulate(flaps, deathTick)
		runs++
		totalFlaps += flaps.length
		worstMin = Math.min(worstMin, path.minY)
		worstMax = Math.max(worstMax, path.maxY)
		if (path.minY < PLAY_TOP || path.maxY > PLAY_BOTTOM) {
			boundHits++
			ok = false
			if (boundHits <= 8) {
				console.error("bounds", { seed, slot, minY: path.minY.toFixed(1), maxY: path.maxY.toFixed(1), flaps: flaps.length, deathTick })
			}
		}
		if (hasClimb(flaps) && path.minY < PLAY_TOP + 12) {
			climbHits++
			ok = false
			console.error("climb", { seed, slot, flaps: flaps.slice(0, 12), minY: path.minY.toFixed(1), maxY: path.maxY.toFixed(1) })
		}
		const gap = gapFollow(layout, path.ys, deathTick)
		gapChecks += gap.checks
		gapHits += gap.hits
	}
}

const gapRate = (100 * gapHits) / Math.max(1, gapChecks)
if (gapRate < 70) {
	console.error("gap follow too low", gapRate.toFixed(1))
	ok = false
}

console.log(
	`[fallback-js] runs=${runs} min_y=${worstMin.toFixed(1)} max_y=${worstMax.toFixed(1)} avg_flaps=${(totalFlaps / runs).toFixed(1)} bound_hits=${boundHits} climb_hits=${climbHits} gap=${gapHits}/${gapChecks} (${gapRate.toFixed(1)}%) ok=${ok}`
)
process.exit(ok ? 0 : 1)
