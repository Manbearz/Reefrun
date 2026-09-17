import fs from "fs"
import path from "path"
import { fileURLToPath } from "url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const outPath = path.join(root, "assets", "sfx", "coin.wav")

const SR = 22050
const SECS = 0.28
const N = Math.floor(SR * SECS)
const TAU = Math.PI * 2

const L = new Float64Array(N)
const R = new Float64Array(N)

function ping(start, hz, amp, dur, decay) {
	const s0 = Math.floor(start * SR)
	const len = Math.floor(dur * SR)
	for (let k = 0; k < len; k++) {
		const t = k / SR
		const env = Math.exp(-t * decay) * Math.min(1, t / 0.006)
		const s = Math.sin(TAU * hz * t) * 0.82 + Math.sin(TAU * hz * 2.0 * t) * 0.12
		const i = s0 + k
		if (i >= N) break
		L[i] += s * env * amp * 0.94
		R[i] += s * env * amp * 1.06
	}
}

ping(0.0, 987.8, 0.22, 0.22, 16)
ping(0.055, 1318.5, 0.2, 0.22, 15)
ping(0.1, 1568.0, 0.12, 0.18, 18)

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
