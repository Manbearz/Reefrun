import fs from "fs"
import path from "path"
import { fileURLToPath } from "url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const outPath = path.join(root, "assets", "sfx", "checkpoint.wav")

const SR = 22050
const SECS = 0.32
const N = Math.floor(SR * SECS)
const TAU = Math.PI * 2

const L = new Float64Array(N)
const R = new Float64Array(N)

function ping(start, hz, amp, dur) {
	const s0 = Math.floor(start * SR)
	const len = Math.floor(dur * SR)
	for (let k = 0; k < len; k++) {
		const t = k / SR
		const env = Math.exp(-t * 14) * Math.min(1, t / 0.008)
		const s = Math.sin(TAU * hz * t) * 0.85 + Math.sin(TAU * hz * 2 * t) * 0.08
		const i = s0 + k
		if (i >= N) break
		L[i] += s * env * amp * 0.92
		R[i] += s * env * amp * 1.08
	}
}

ping(0.0, 784.0, 0.22, 0.28)
ping(0.07, 1046.5, 0.18, 0.24)

const chirp0 = Math.floor(0.02 * SR)
const chirpLen = Math.floor(0.09 * SR)
for (let k = 0; k < chirpLen; k++) {
	const u = k / chirpLen
	const env = Math.pow(1 - u, 1.8) * Math.min(1, u / 0.1)
	const hz = 920 + (220 - 920) * u
	const s = Math.sin((TAU * hz * k) / SR) * 0.07 * env
	const i = chirp0 + k
	if (i >= N) break
	L[i] += s * 0.8
	R[i] += s
}

let peak = 0.0001
for (let i = 0; i < N; i++) peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]))
const gain = 0.18 / peak

const pcm = Buffer.alloc(N * 4)
for (let i = 0; i < N; i++) {
	pcm.writeInt16LE(Math.round(Math.max(-1, Math.min(1, L[i] * gain)) * 32767), i * 4)
	pcm.writeInt16LE(Math.round(Math.max(-1, Math.min(1, R[i] * gain)) * 32767), i * 4 + 2)
}

const header = Buffer.alloc(44)
header.write("RIFF", 0)
header.writeUInt32LE(36 + pcm.length, 4)
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
header.writeUInt32LE(pcm.length, 40)

fs.mkdirSync(path.dirname(outPath), { recursive: true })
fs.writeFileSync(outPath, Buffer.concat([header, pcm]))
console.log("wrote", outPath)
