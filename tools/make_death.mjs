import fs from "fs"
import path from "path"
import { fileURLToPath } from "url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const outPath = path.join(root, "assets", "sfx", "death.wav")

const SR = 22050
const SECS = 0.72
const N = Math.floor(SR * SECS)
const TAU = Math.PI * 2

const L = new Float64Array(N)
const R = new Float64Array(N)

function add(i, s, pan = 0) {
	if (i < 0 || i >= N) return
	L[i] += s * (1 - pan)
	R[i] += s * (1 + pan)
}

for (let k = 0; k < N; k++) {
	const u = k / N
	const t = k / SR
	const env = Math.min(1, t / 0.02) * Math.pow(1 - u, 0.55)
	const hz = 1980 * Math.pow(0.22, u)
	const vib = 1 + 0.012 * Math.sin(TAU * 6.5 * t)
	const s = Math.sin(TAU * hz * vib * t) * env * 0.42
	add(k, s, 0.1)
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
console.log("wrote", outPath, "secs", SECS)
