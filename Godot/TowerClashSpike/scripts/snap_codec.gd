class_name SnapCodec
extends RefCounted
## Binary snapshot codec. MatchSim.snapshot() Dictionary <-> PackedByteArray.
## Keeps a full-state snapshot well under the ENet MTU (~1392 B) so unreliable sends are not
## fragmented. Decode returns the same Dictionary shape the client already consumes.
## Player rows carry the per-deck-slot card levels (u8 each).
## Quantisation: dist 1 cm (u16), hp fraction 1/255, tower aim 1/254 turn, enemy id u16 (wraps).

const AIM_NONE := 255
const NO_AIM := 9.0


static func encode(s: Dictionary) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_float(float(s.t))
	b.put_u8(int(s.ph))
	b.put_u8(int(s.r))
	b.put_u8(int(s.rn))
	b.put_u16(clampi(int(round(float(s.tl) * 10.0)), 0, 65535))
	for p in 2:
		var pl: Array = s.p[p]
		b.put_u32(maxi(0, int(pl[0])))
		b.put_8(clampi(int(pl[1]), -128, 127))
		b.put_u16(clampi(int(pl[2]), 0, 65535))
		b.put_u16(clampi(int(pl[3]), 0, 65535))
		b.put_u16(clampi(int(pl[4]), 0, 65535))
		var lv: Array = pl[5]
		b.put_u8(lv.size())
		for l in lv:
			b.put_u8(int(l))
	for p in 2:
		var tws: Array = s.tw[p]
		b.put_u8(tws.size())
		for t in tws:
			b.put_u8(int(t[0]))
			b.put_u8(int(t[1]))
			b.put_u8(int(t[2]))
			var aim := float(t[3])
			b.put_u8(AIM_NONE if aim > 7.0 else posmod(int(round((aim + PI) / TAU * 254.0)), 254))
	var en: Array = s.en
	b.put_u16(en.size())
	for e in en:
		b.put_u16(int(e[0]) & 0xFFFF)
		b.put_u8((int(e[1]) & 1) | ((int(e[5]) & 3) << 1))
		b.put_u8(int(e[2]))
		b.put_u16(clampi(int(round(float(e[3]))), 0, 65535))
		b.put_u8(clampi(int(round(float(e[4]) * 255.0)), 0, 255))
	b.put_u16(s.sh.size())
	for x in s.sh:
		b.put_u8(int(x[0]))
		b.put_u8(int(x[1]))
		b.put_u16(int(x[2]) & 0xFFFF)
	b.put_u16(s.k.size())
	for x in s.k:
		b.put_u16(int(x[0]) & 0xFFFF)
		b.put_u8(int(x[1]))
		b.put_u8(1 if x[2] else 0)
	b.put_u8(mini(s.h.size(), 255))
	for i in mini(s.h.size(), 255):
		b.put_u8(int(s.h[i][0]))
		b.put_u16(int(s.h[i][1]) & 0xFFFF)
	return b.data_array


static func decode(bytes: PackedByteArray) -> Dictionary:
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	var s := {}
	s.t = b.get_float()
	s.ph = b.get_u8()
	s.r = b.get_u8()
	s.rn = b.get_u8()
	s.tl = b.get_u16() / 10.0
	s.p = []
	for p in 2:
		var row: Array = [b.get_u32(), b.get_8(), b.get_u16(), b.get_u16(), b.get_u16()]
		var lv: Array = []
		for i in b.get_u8():
			lv.append(b.get_u8())
		row.append(lv)
		s.p.append(row)
	s.tw = []
	for p in 2:
		var list: Array = []
		for i in b.get_u8():
			var slot := b.get_u8()
			var type := b.get_u8()
			var level := b.get_u8()
			var q := b.get_u8()
			list.append([slot, type, level, NO_AIM if q == AIM_NONE else q / 254.0 * TAU - PI])
		s.tw.append(list)
	s.en = []
	for i in b.get_u16():
		var id := b.get_u16()
		var bf := b.get_u8()
		var type := b.get_u8()
		var dist := float(b.get_u16())
		var hp := b.get_u8() / 255.0
		s.en.append([id, bf & 1, type, dist, hp, bf >> 1])
	s.sh = []
	for i in b.get_u16():
		s.sh.append([b.get_u8(), b.get_u8(), b.get_u16()])
	s.k = []
	for i in b.get_u16():
		s.k.append([b.get_u16(), b.get_u8(), b.get_u8() == 1])
	s.h = []
	for i in b.get_u8():
		s.h.append([b.get_u8(), b.get_u16()])
	return s
