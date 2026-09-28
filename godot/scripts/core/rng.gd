# Seeded randomness: mulberry32 plus the small helpers gameplay code needs (port of src/core/rng.js).
# game.rand() is the seeded stream (ARCHITECTURE §1); cosmetics may use randf() (= Math.random()).
# mulberry32(seed) returns a Callable () -> float in [0,1) that produces EXACTLY the same sequence as the JS version
# (32-bit unsigned arithmetic emulated with 64-bit ints + masks). Helpers take an optional source Callable `r`
# (default: randf, like Math.random in JS).
class_name Rng

const M32 := 0xFFFFFFFF

# Math.imul: 32-bit wrapping multiply, returned as an UNSIGNED 32-bit value (callers only use it inside >>> 0 chains).
static func imul(a: int, b: int) -> int:
	a &= M32
	b &= M32
	var lo := (a & 0xFFFF) * b
	var hi := ((a >> 16) * b) & M32
	return (lo + (hi << 16)) & M32

class Mulberry32:
	var a: int
	func _init(seed: int) -> void:
		a = seed & 0xFFFFFFFF
	func next() -> float:
		a = (a + 0x6D2B79F5) & 0xFFFFFFFF
		var t := a
		t = Rng.imul(t ^ (t >> 15), t | 1)
		t = (t ^ ((t + Rng.imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF
		return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0

static func mulberry32(seed: int) -> Callable:
	var m := Mulberry32.new(seed)   # the lambda holds the reference (a bound method Callable would not)
	return func() -> float: return m.next()

static func _src(r: Callable) -> Callable:
	return r if r.is_valid() else Callable(randf)

static func range(min_v: float, max_v: float, r: Callable = Callable()) -> float:
	return min_v + (max_v - min_v) * _src(r).call()

static func rangeInt(min_v: int, max_v: int, r: Callable = Callable()) -> int:
	return int(floor(min_v + (max_v - min_v + 1) * _src(r).call()))

static func pick(arr: Array, r: Callable = Callable()):
	if arr.is_empty():
		return null
	return arr[int(floor(_src(r).call() * arr.size()))]

static func chance(p: float, r: Callable = Callable()) -> bool:
	return _src(r).call() < p

# In-place Fisher-Yates shuffle.
static func shuffle(arr: Array, r: Callable = Callable()) -> Array:
	var src := _src(r)
	for i in range(arr.size() - 1, 0, -1):
		var j := int(floor(src.call() * (i + 1)))
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
	return arr

# Weighted pick over { key: weight } -> key (null if all weights are 0). Iterates in insertion order like JS.
static func weighted(weights: Dictionary, r: Callable = Callable()):
	var total := 0.0
	for k in weights:
		total += weights[k]
	if total <= 0.0:
		return null
	var x: float = _src(r).call() * total
	for k in weights:
		x -= weights[k]
		if x < 0.0:
			return k
	return null

# Cheap deterministic hash noise in [0,1) for cosmetic jitter.
static func hash1(n: float) -> float:
	var s := sin(n * 127.1 + 311.7) * 43758.5453
	return s - floorf(s)

# Smooth 1D value noise in [-1,1] (used by shake, flicker, wobble).
static func noise1(x: float) -> float:
	var i := floorf(x)
	var f := x - i
	var u := f * f * (3.0 - 2.0 * f)
	return (hash1(i) * (1.0 - u) + hash1(i + 1.0) * u) * 2.0 - 1.0

# FNV-1a string hash (the `hashStr` / `hash` helpers of textures.js, kit.js and cards.js).
static func hashStr(s: String) -> int:
	var h := 2166136261
	for i in s.length():
		h = imul(h ^ s.unicode_at(i), 16777619)
	return h & M32
