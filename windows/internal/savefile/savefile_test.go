package savefile

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/md5"
	"encoding/binary"
	"encoding/json"
	"reflect"
	"strings"
	"testing"
	"unicode/utf16"
)

// ---- synthetic fixture builders -------------------------------------------

// emptyState is one empty record: ga_handle 0, item_id 0xFFFFFFFF.
func emptyState() []byte {
	return []byte{0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF}
}

// weaponState builds an 88-byte weapon record (type nibble 0x8).
func weaponState(instance uint32) []byte {
	b := make([]byte, 88)
	binary.LittleEndian.PutUint32(b, 0x80000000|instance)
	binary.LittleEndian.PutUint32(b[4:], 0x80000000|1000000)
	return b
}

// armorState builds a 16-byte armor record (type nibble 0x9).
func armorState(instance uint32) []byte {
	b := make([]byte, 16)
	binary.LittleEndian.PutUint32(b, 0x90000000|instance)
	binary.LittleEndian.PutUint32(b[4:], 0x90000000|40000)
	return b
}

// goodsState builds an 8-byte record with an unknown-to-us type nibble (0xB),
// which the scanner must skip as header-only.
func goodsState(instance uint32) []byte {
	b := make([]byte, 8)
	binary.LittleEndian.PutUint32(b, 0xB0000000|instance)
	binary.LittleEndian.PutUint32(b[4:], 0xB0000000|9600)
	return b
}

// relicState builds an 80-byte relic record with raw (un-normalized) affix
// values so tests can exercise both empty sentinels (0xFFFFFFFF and 0).
func relicState(instance, realID uint32, effects, curses [3]uint32) []byte {
	b := make([]byte, 80)
	binary.LittleEndian.PutUint32(b, 0xC0000000|instance)
	binary.LittleEndian.PutUint32(b[4:], 0x80000000|realID)
	binary.LittleEndian.PutUint32(b[8:], 0x80000000|realID) // durability mirrors item_id
	binary.LittleEndian.PutUint32(b[12:], 0xFFFFFFFF)       // unk_1
	for i, e := range effects {
		binary.LittleEndian.PutUint32(b[16+4*i:], e)
	}
	for i, cu := range curses {
		binary.LittleEndian.PutUint32(b[56+4*i:], cu)
	}
	binary.LittleEndian.PutUint32(b[68:], 0xFFFFFFFF) // unk_2
	return b
}

// sealPlain pads content to the AES block size and appends the 28-byte
// trailer: MD5(plain[4 : L-28]) at [L-28 : L-12] plus 12 padding bytes.
func sealPlain(content []byte) []byte {
	content = append([]byte{}, content...)
	if rem := (len(content) + checksumTrailer) % aes.BlockSize; rem != 0 {
		content = append(content, make([]byte, aes.BlockSize-rem)...)
	}
	plain := append(content, make([]byte, checksumTrailer)...)
	end := len(plain) - checksumTrailer
	sum := md5.Sum(plain[checksumStart:end])
	copy(plain[end:], sum[:])
	return plain
}

// characterPlain builds one character slot's plaintext: the 0x14 header, the
// given records padded with empties up to 5120, the 0x94 gap and the
// UTF-16LE name (16 code units, NUL padded), then the checksum trailer.
func characterPlain(name string, records [][]byte) []byte {
	var body bytes.Buffer
	body.Write(make([]byte, stateStart))
	count := 0
	for _, r := range records {
		body.Write(r)
		count++
	}
	for ; count < stateSlotCount; count++ {
		body.Write(emptyState())
	}
	body.Write(make([]byte, nameGap))
	nameBuf := make([]byte, nameMaxUnits*2)
	for i, u := range utf16.Encode([]rune(name)) {
		if i >= nameMaxUnits {
			break
		}
		binary.LittleEndian.PutUint16(nameBuf[2*i:], u)
	}
	body.Write(nameBuf)
	return sealPlain(body.Bytes())
}

// sharedPlain builds USERDATA_10: when withMagic is set, the 10 occupancy
// flags sit 61 bytes before the FACE magic.
func sharedPlain(flags [10]byte, withMagic bool) []byte {
	buf := make([]byte, 128)
	if withMagic {
		copy(buf[16:], flags[:])
		copy(buf[16+61:], faceMagic)
	}
	return sealPlain(buf)
}

// encryptEntry produces IV + AES-128-CBC ciphertext for one entry.
func encryptEntry(t *testing.T, plain []byte, seed byte) []byte {
	t.Helper()
	if len(plain)%aes.BlockSize != 0 {
		t.Fatalf("fixture plaintext not block aligned: %d bytes", len(plain))
	}
	iv := bytes.Repeat([]byte{seed}, ivSize)
	block, err := aes.NewCipher(aesKey)
	if err != nil {
		t.Fatal(err)
	}
	out := make([]byte, len(plain))
	cipher.NewCBCEncrypter(block, iv).CryptBlocks(out, plain)
	return append(iv, out...)
}

// buildSave assembles encrypted entries into a BND4 container.
func buildSave(entries [][]byte) []byte {
	var out bytes.Buffer
	header := make([]byte, bnd4HeaderLen)
	copy(header, bnd4Magic)
	binary.LittleEndian.PutUint32(header[12:], uint32(len(entries)))
	out.Write(header)
	offset := bnd4HeaderLen + bnd4EntryHeaderLen*len(entries)
	for _, e := range entries {
		h := make([]byte, bnd4EntryHeaderLen)
		copy(h, entryMagic)
		binary.LittleEndian.PutUint32(h[8:], uint32(len(e)))
		binary.LittleEndian.PutUint32(h[16:], uint32(offset))
		out.Write(h)
		offset += len(e)
	}
	for _, e := range entries {
		out.Write(e)
	}
	return out.Bytes()
}

// fixtureSlot0 holds two relics interleaved with empty/weapon/armor/goods
// records; empty affix slots use both sentinels (0xFFFFFFFF and 0).
func fixtureSlot0() []byte {
	return characterPlain("夜巡者", [][]byte{
		emptyState(),
		weaponState(0x54),
		relicState(0x100, 2000002,
			[3]uint32{6001400, 6600000, 0xFFFFFFFF},
			[3]uint32{6800000, 0x00000000, 0xFFFFFFFF}),
		armorState(0x55),
		goodsState(0x56),
		relicState(0x101, 150,
			[3]uint32{7000000, 0x00000000, 0xFFFFFFFF},
			[3]uint32{0xFFFFFFFF, 0xFFFFFFFF, 0x00000000}),
		emptyState(),
	})
}

func fixtureSlot2() []byte {
	return characterPlain("Knight-02", [][]byte{
		relicState(0x200, 1001,
			[3]uint32{7000000, 0xFFFFFFFF, 0xFFFFFFFF},
			[3]uint32{0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF}),
	})
}

// minimalPlain is the smallest valid slot plaintext: parsing it as a
// character truncates almost immediately, but its checksum verifies.
func minimalPlain() []byte { return sealPlain(make([]byte, stateStart)) }

// buildFixture assembles the canonical 11-entry archive: slots 0 and 2
// occupied, the rest carrying minimal placeholder data.
func buildFixture(t *testing.T) []byte {
	t.Helper()
	entries := make([][]byte, 11)
	for i := 0; i < 10; i++ {
		entries[i] = encryptEntry(t, minimalPlain(), byte(i+1))
	}
	entries[0] = encryptEntry(t, fixtureSlot0(), 0xA0)
	entries[2] = encryptEntry(t, fixtureSlot2(), 0xA2)
	entries[10] = encryptEntry(t, sharedPlain([10]byte{1, 0, 1, 0, 0, 0, 0, 0, 0, 0}, true), 0xAA)
	return buildSave(entries)
}

// ---- tests -----------------------------------------------------------------

func TestParseFixture(t *testing.T) {
	payload, err := Parse(buildFixture(t), "NR0000.sl2")
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if payload.FileName != "NR0000.sl2" {
		t.Errorf("fileName = %q, want NR0000.sl2", payload.FileName)
	}
	if !payload.ChecksumOk {
		t.Errorf("checksumOk = false, want true")
	}
	if len(payload.Characters) != 2 {
		t.Fatalf("characters = %d, want 2", len(payload.Characters))
	}

	c0 := payload.Characters[0]
	if c0.Slot != 0 || c0.Name != "夜巡者" || c0.ParseError != nil {
		t.Errorf("slot0 = {%d %q %v}, want {0 夜巡者 <nil>}", c0.Slot, c0.Name, c0.ParseError)
	}
	wantRelics0 := []Relic{
		{Index: 0, ItemID: 2000002, Effects: []int64{6001400, 6600000, -1}, Curses: []int64{6800000, -1, -1}},
		{Index: 1, ItemID: 150, Effects: []int64{7000000, -1, -1}, Curses: []int64{-1, -1, -1}},
	}
	if !reflect.DeepEqual(c0.Relics, wantRelics0) {
		t.Errorf("slot0 relics = %+v, want %+v", c0.Relics, wantRelics0)
	}

	c2 := payload.Characters[1]
	if c2.Slot != 2 || c2.Name != "Knight-02" || c2.ParseError != nil {
		t.Errorf("slot2 = {%d %q %v}, want {2 Knight-02 <nil>}", c2.Slot, c2.Name, c2.ParseError)
	}
	wantRelics2 := []Relic{
		{Index: 0, ItemID: 1001, Effects: []int64{7000000, -1, -1}, Curses: []int64{-1, -1, -1}},
	}
	if !reflect.DeepEqual(c2.Relics, wantRelics2) {
		t.Errorf("slot2 relics = %+v, want %+v", c2.Relics, wantRelics2)
	}
}

// TestPayloadWireShape pins the exact JSON the bridge sends to the renderer;
// the macOS implementation must match it byte for byte.
func TestPayloadWireShape(t *testing.T) {
	parseError := "槽位数据损坏"
	payload := &Payload{
		FileName:   "NR0000.sl2",
		ChecksumOk: true,
		Characters: []Character{
			{
				Slot: 0, Name: "甲", ParseError: nil,
				Relics: []Relic{{
					Index: 0, ItemID: 2000002,
					Effects: []int64{6001400, 6600000, -1},
					Curses:  []int64{6800000, -1, -1},
				}},
			},
			{Slot: 3, Name: "槽位 4", ParseError: &parseError, Relics: []Relic{}},
		},
	}
	got, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	want := `{"fileName":"NR0000.sl2","checksumOk":true,"characters":[` +
		`{"slot":0,"name":"甲","parseError":null,"relics":[` +
		`{"index":0,"itemId":2000002,"effects":[6001400,6600000,-1],"curses":[6800000,-1,-1]}]},` +
		`{"slot":3,"name":"槽位 4","parseError":"槽位数据损坏","relics":[]}]}`
	if string(got) != want {
		t.Errorf("payload JSON:\n got %s\nwant %s", got, want)
	}
}

func TestParseRejectsBadInput(t *testing.T) {
	good := buildFixture(t)

	corruptEntryMagic := append([]byte{}, good...)
	corruptEntryMagic[bnd4HeaderLen] = 0x41

	zeroEntries := append([]byte{}, good...)
	binary.LittleEndian.PutUint32(zeroEntries[12:], 0)

	// IV + 24-byte ciphertext: not a multiple of the AES block size.


	cases := []struct {
		name string
		data []byte
	}{
		{"空输入", nil},
		{"非 BND4", []byte("XXXX" + strings.Repeat("\x00", 96))},
		{"BND4 头截断", []byte("BND4")},
		{"条目头越界", good[:bnd4HeaderLen+8]},
		{"条目数据越界", good[:len(good)-31]},
		{"条目魔数不符", corruptEntryMagic},
		{"条目数为零", zeroEntries},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			payload, err := Parse(tc.data, "bad.sl2")
			if err == nil {
				t.Fatalf("expected error, got payload %+v", payload)
			}
		})
	}
}

// TestBadCipherLengthIsIsolated: 条目数据层面的问题（如密文长度非 16 倍数）
// 不再使整体解析失败，而是隔离为该槽位的 ParseError。
func TestBadCipherLengthIsIsolated(t *testing.T) {
	payload, err := Parse(badCipherLenSave(), "bad.sl2")
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if len(payload.Characters) != 1 {
		t.Fatalf("characters = %d, want 1", len(payload.Characters))
	}
	c := payload.Characters[0]
	if c.ParseError == nil || !strings.Contains(*c.ParseError, "解密失败") {
		t.Errorf("parseError = %v, want 解密失败", c.ParseError)
	}
	if c.Name != "槽位 1" || len(c.Relics) != 0 {
		t.Errorf("character = %+v, want fallback name and no relics", c)
	}
}

func badCipherLenSave() []byte {
	return buildSave([][]byte{append(bytes.Repeat([]byte{1}, ivSize), bytes.Repeat([]byte{2}, 24)...)})
}

func TestNotSaveFileMessage(t *testing.T) {
	_, err := Parse([]byte("PK\x03\x04junk"), "bad.sl2")
	if err == nil || err.Error() != "不是有效的存档文件" {
		t.Fatalf("err = %v, want 不是有效的存档文件", err)
	}
}

// TestChecksumMismatchDegrades verifies a bad per-entry MD5 flips checksumOk
// without blocking the parse.
func TestChecksumMismatchDegrades(t *testing.T) {
	slot0 := fixtureSlot0()
	slot0[len(slot0)-20] ^= 0xFF // corrupt the stored digest, not the data

	entries := make([][]byte, 11)
	for i := 0; i < 10; i++ {
		entries[i] = encryptEntry(t, minimalPlain(), byte(i+1))
	}
	entries[0] = encryptEntry(t, slot0, 0xA0)
	entries[2] = encryptEntry(t, fixtureSlot2(), 0xA2)
	entries[10] = encryptEntry(t, sharedPlain([10]byte{1, 0, 1, 0, 0, 0, 0, 0, 0, 0}, true), 0xAA)

	payload, err := Parse(buildSave(entries), "NR0000.sl2")
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if payload.ChecksumOk {
		t.Errorf("checksumOk = true, want false")
	}
	if len(payload.Characters) != 2 || len(payload.Characters[0].Relics) != 2 {
		t.Errorf("parsing degraded more than expected: %+v", payload.Characters)
	}
}

// TestSlotParseErrorIsIsolated verifies that a truncated character slot only
// poisons itself: it gets ParseError and the fallback name while other slots
// keep parsing.
func TestSlotParseErrorIsIsolated(t *testing.T) {
	entries := make([][]byte, 11)
	for i := 0; i < 10; i++ {
		entries[i] = encryptEntry(t, minimalPlain(), byte(i+1))
	}
	entries[0] = encryptEntry(t, sealPlain(make([]byte, stateStart+64)), 0xA0) // room for a few records only
	entries[2] = encryptEntry(t, fixtureSlot2(), 0xA2)
	entries[10] = encryptEntry(t, sharedPlain([10]byte{1, 0, 1, 0, 0, 0, 0, 0, 0, 0}, true), 0xAA)

	payload, err := Parse(buildSave(entries), "NR0000.sl2")
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if len(payload.Characters) != 2 {
		t.Fatalf("characters = %d, want 2", len(payload.Characters))
	}
	c0 := payload.Characters[0]
	if c0.ParseError == nil {
		t.Errorf("slot0 parseError = nil, want truncation error")
	}
	if c0.Name != "槽位 1" {
		t.Errorf("slot0 name = %q, want 槽位 1", c0.Name)
	}
	c2 := payload.Characters[1]
	if c2.ParseError != nil || len(c2.Relics) != 1 {
		t.Errorf("slot2 should parse cleanly, got %+v", c2)
	}
}

// TestTruncatedRelicRecord: a relic header whose 80-byte body runs past the
// end of the plaintext must produce ParseError, not a panic.
func TestTruncatedRelicRecord(t *testing.T) {
	content := make([]byte, stateStart)
	content = append(content, relicState(0x100, 2000002,
		[3]uint32{6001400, 0xFFFFFFFF, 0xFFFFFFFF},
		[3]uint32{0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF})[:8]...)
	entry := encryptEntry(t, sealPlain(content), 0x01)

	payload, err := Parse(buildSave([][]byte{entry}), "NR0000.sl2")
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if len(payload.Characters) != 1 || payload.Characters[0].ParseError == nil {
		t.Fatalf("want one character with parseError, got %+v", payload.Characters)
	}
}

// TestMissingSlotFlagsAssumesAllOccupied: without the FACE magic every slot
// is treated as occupied and parsed (most of them failing individually).
func TestMissingSlotFlagsAssumesAllOccupied(t *testing.T) {
	entries := make([][]byte, 11)
	for i := 0; i < 10; i++ {
		entries[i] = encryptEntry(t, minimalPlain(), byte(i+1))
	}
	entries[2] = encryptEntry(t, fixtureSlot2(), 0xA2)
	entries[10] = encryptEntry(t, sharedPlain([10]byte{}, false), 0xAA)

	payload, err := Parse(buildSave(entries), "NR0000.sl2")
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if len(payload.Characters) != 10 {
		t.Fatalf("characters = %d, want 10", len(payload.Characters))
	}
	for _, c := range payload.Characters {
		if c.Slot == 2 {
			if c.ParseError != nil || len(c.Relics) != 1 {
				t.Errorf("slot2 should parse cleanly, got %+v", c)
			}
		} else if c.ParseError == nil {
			t.Errorf("slot %d: placeholder data should yield parseError", c.Slot)
		}
	}
}

// TestFewerEntriesThanSlots: slots at or beyond the entry count are skipped.
func TestFewerEntriesThanSlots(t *testing.T) {
	entries := [][]byte{
		encryptEntry(t, fixtureSlot0(), 0xA0),
		encryptEntry(t, minimalPlain(), 0x01),
		encryptEntry(t, fixtureSlot2(), 0xA2),
	}
	payload, err := Parse(buildSave(entries), "NR0000.co2")
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if len(payload.Characters) != 3 {
		t.Fatalf("characters = %d, want 3 (no USERDATA_10 → all occupied, capped at entryCount)", len(payload.Characters))
	}
	if payload.Characters[0].Name != "夜巡者" || payload.Characters[2].Name != "Knight-02" {
		t.Errorf("unexpected names: %q / %q", payload.Characters[0].Name, payload.Characters[2].Name)
	}
	if payload.Characters[1].ParseError == nil {
		t.Errorf("slot1 placeholder should yield parseError")
	}
}
