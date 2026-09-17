import decode from "audio-decode"
import fs from "fs"
import path from "path"
import { fileURLToPath } from "url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const srcPath = path.join(root, "assets", "sfx", "splat.mp3")
const outPath = path.join(root, "assets", "sfx", "splat.wav")

const START = 0.175
const END = 0.56
const FADE_IN = 0.008
const FADE_OUT = 0.05

const audio = await decode(fs.readFileSync(srcPath))
const sr = audio.sampleRate
const L = audio.channelData[0]
const R = audio.channelData[1] || L
const s0 = Math.max(0, Math.floor(START * sr))
const s1 = Math.min(L.length, Math.floor(END * sr))
const n = s1 - s0
const fadeInN = Math.max(1, Math.floor(FADE_IN * sr))
const fadeOutN = Math.max(1, Math.floor(FADE_OUT * sr))

const pcm = Buffer.alloc(n * 4)
for (let i = 0; i < n; i++) {
	let g = 1
	if (i < fadeInN) g *= i / fadeInN
	if (i > n - fadeOutN) g *= Math.max(0, (n - i) / fadeOutN)
	pcm.writeInt16LE(Math.round(Math.max(-1, Math.min(1, L[s0 + i] * g)) * 32767), i * 4)
	pcm.writeInt16LE(Math.round(Math.max(-1, Math.min(1, R[s0 + i] * g)) * 32767), i * 4 + 2)
}

const header = Buffer.alloc(44)
header.write("RIFF", 0)
header.writeUInt32LE(36 + pcm.length, 4)
header.write("WAVE", 8)
header.write("fmt ", 12)
header.writeUInt32LE(16, 16)
header.writeUInt16LE(1, 20)
header.writeUInt16LE(2, 22)
header.writeUInt32LE(sr, 24)
header.writeUInt32LE(sr * 4, 28)
header.writeUInt16LE(4, 32)
header.writeUInt16LE(16, 34)
header.write("data", 36)
header.writeUInt32LE(pcm.length, 40)

fs.writeFileSync(outPath, Buffer.concat([header, pcm]))
console.log("wrote", outPath, "secs", (n / sr).toFixed(3), "from", START, "to", END)
