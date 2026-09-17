import fs from "fs"
import path from "path"
import { fileURLToPath } from "url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const outPath = path.join(root, "assets", "sfx", "ambient.wav")

const SR = 22050
const BPM = 104
const BARS = 8
const BEAT = 60 / BPM
const SECS = BARS * 4 * BEAT
const N = Math.floor(SR * SECS)
const TAU = Math.PI * 2

function midi(n) {
	return 440 * Math.pow(2, (n - 69) / 12)
}

function mulberry(seed) {
	let a = seed >>> 0
	return () => {
		a += 0x6d2b79f5
		let t = a
		t = Math.imul(t ^ (t >>> 15), t | 1)
		t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296
	}
}

const rand = mulberry(0xb0661e)

function envPluck(t, dur) {
	if (t < 0 || t > dur) return 0
	const a = Math.min(1, t / 0.012)
	return a * Math.exp(-t * 5.8)
}

function envBass(t, dur) {
	if (t < 0 || t > dur) return 0
	const a = Math.min(1, t / 0.02)
	return a * Math.exp(-t * 2.4)
}

function envPad(t, dur) {
	if (t < 0 || t > dur) return 0
	const a = Math.min(1, t / 0.18)
	const r = t > dur - 0.25 ? (dur - t) / 0.25 : 1
	return a * r
}

const L = new Float64Array(N)
const R = new Float64Array(N)

function add(i, sample, pan = 0) {
	if (i < 0 || i >= N) return
	L[i] += sample * (1 - pan) * 0.5
	R[i] += sample * (1 + pan) * 0.5
}

function note(startBeat, durBeats, midiNote, kind, amp, pan = 0) {
	const start = Math.floor(startBeat * BEAT * SR)
	const dur = durBeats * BEAT
	const len = Math.floor(dur * SR)
	const hz = midi(midiNote)
	for (let k = 0; k < len; k++) {
		const t = k / SR
		const phase = (TAU * hz * t)
		let s = 0
		let e = 0
		if (kind === "pluck") {
			e = envPluck(t, dur)
			s = Math.sin(phase) + Math.sin(phase * 2.01) * 0.18 * Math.exp(-t * 9)
			s += Math.sin(phase * 3.02) * 0.05 * Math.exp(-t * 14)
		} else if (kind === "bass") {
			e = envBass(t, dur)
			s = Math.sin(phase) * 0.9 + Math.sin(phase * 2) * 0.12
		} else {
			e = envPad(t, dur)
			s = Math.sin(phase) * 0.7 + Math.sin(phase * 2.005) * 0.12 + Math.sin(phase * 0.5) * 0.08
		}
		add(start + k, s * e * amp, pan)
	}
}

function bubble(startBeat, amp = 0.05) {
	const start = Math.floor((startBeat * BEAT + (rand() - 0.5) * 0.04) * SR)
	const len = Math.floor(SR * (0.09 + rand() * 0.16))
	const f0 = 680 + rand() * 920
	const f1 = 140 + rand() * 120
	const pan = rand() * 1.4 - 0.7
	for (let k = 0; k < len; k++) {
		const u = k / len
		const env = Math.pow(1 - u, 1.7) * (u < 0.07 ? u / 0.07 : 1)
		const hz = f0 + (f1 - f0) * Math.pow(u, 0.5)
		add(start + k, Math.sin((TAU * hz * k) / SR) * amp * env, pan)
	}
}

const hook = [74, 71, 67, 71, 69, 67, 64, 62]
const hook2 = [74, 76, 79, 76, 74, 71, 69, 67]
const bass = [43, 43, 47, 45, 48, 48, 50, 43]
const padRoot = [67, 64, 65, 62]

for (let bar = 0; bar < BARS; bar++) {
	const t0 = bar * 4
	const melody = bar % 4 < 2 ? hook : hook2
	for (let s = 0; s < 8; s++) {
		const beat = t0 + s * 0.5
		const n = melody[s]
		const pan = (s % 2 === 0 ? -0.22 : 0.22) + (bar % 2) * 0.06
		note(beat, 0.48, n, "pluck", 0.2, pan)
		if (s % 2 === 1) note(beat + 0.12, 0.28, n + 12, "pluck", 0.07, -pan)
	}
	note(t0, 1.9, bass[bar], "bass", 0.16, 0)
	note(t0 + 2, 1.7, bass[bar] + (bar % 2 === 0 ? 7 : 5), "bass", 0.11, 0.08)
	note(t0, 3.9, padRoot[bar % 4], "pad", 0.045, -0.15)
	note(t0, 3.9, padRoot[bar % 4] + 7, "pad", 0.03, 0.18)
	bubble(t0 + 0.5, 0.055)
	bubble(t0 + 1.5, 0.04)
	bubble(t0 + 2.75, 0.06)
	if (bar % 2 === 1) bubble(t0 + 3.25, 0.05)
}

for (let i = 0; i < 10; i++) bubble(rand() * BARS * 4, 0.03)

let n1 = 0
for (let i = 0; i < N; i++) {
	const white = rand() * 2 - 1
	n1 = n1 * 0.96 + white * 0.04
	const t = i / SR
	const wash = n1 * (0.035 + 0.02 * Math.sin((TAU * t) / 9))
	L[i] += wash * 0.55
	R[i] += wash * 0.45
}

function lowpass(samples, cutoff) {
	const rc = 1 / (TAU * cutoff)
	const dt = 1 / SR
	const a = dt / (rc + dt)
	let y = 0
	const out = new Float64Array(samples.length)
	for (let i = 0; i < samples.length; i++) {
		y += a * (samples[i] - y)
		out[i] = y
	}
	return out
}

const wetL = lowpass(L, 2400)
const wetR = lowpass(R, 2500)

const fade = Math.floor(SR * BEAT * 0.5)
for (let i = 0; i < fade; i++) {
	const a = i / fade
	const z = 1 - a
	const li = wetL[i]
	const ri = wetR[i]
	const lj = wetL[N - fade + i]
	const rj = wetR[N - fade + i]
	wetL[i] = lj * z + li * a
	wetR[i] = rj * z + ri * a
	wetL[N - fade + i] = lj * a + li * z
	wetR[N - fade + i] = rj * a + ri * z
}

let peak = 0.0001
for (let i = 0; i < N; i++) peak = Math.max(peak, Math.abs(wetL[i]), Math.abs(wetR[i]))
const gain = 0.28 / peak

const pcm = Buffer.alloc(N * 4)
for (let i = 0; i < N; i++) {
	const ls = Math.max(-1, Math.min(1, wetL[i] * gain))
	const rs = Math.max(-1, Math.min(1, wetR[i] * gain))
	pcm.writeInt16LE(Math.round(ls * 32767), i * 4)
	pcm.writeInt16LE(Math.round(rs * 32767), i * 4 + 2)
}

const dataSize = pcm.length
const header = Buffer.alloc(44)
header.write("RIFF", 0)
header.writeUInt32LE(36 + dataSize, 4)
header.write("WAVE", 8)
header.write("fmt ", 12)
header.writeUInt32LE(16, 16)
header.writeUInt16LE(1, 20)
header.writeUInt16LE(2, 22)
header.writeUInt32LE(SR, 24)
header.writeUInt32LE(SR * 4, 28)
header.writeUInt16LE(4, 32)
header.writeUInt16LE(16, 34)
header.write("data", 36)
header.writeUInt32LE(dataSize, 40)

fs.mkdirSync(path.dirname(outPath), { recursive: true })
fs.writeFileSync(outPath, Buffer.concat([header, pcm]))
console.log("wrote", outPath, SECS.toFixed(2) + "s", (dataSize / 1024 / 1024).toFixed(2) + "MB")
