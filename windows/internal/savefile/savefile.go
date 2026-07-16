// Package savefile implements read-only parsing of《黑夜君临》save archives
// (.sl2/.co2, BND4 containers with AES-128-CBC encrypted entries).
//
// The package is deliberately free of platform-specific imports so its tests
// run on any OS; the Windows shell (zenity dialog, KnownFolderPath) stays in
// package main. Nothing here ever writes to a save file.
package savefile

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/md5"
	"encoding/binary"
	"errors"
	"fmt"
	"unicode/utf16"
)

// Payload is the JSON shape returned to the renderer. Field order and json
// tags are part of the bridge contract shared with the macOS implementation.
type Payload struct {
	FileName   string      `json:"fileName"`
	ChecksumOk bool        `json:"checksumOk"`
	Characters []Character `json:"characters"`
}

// Character is one occupied character slot (USERDATA_0..9).
type Character struct {
	Slot       int     `json:"slot"`
	Name       string  `json:"name"`
	ParseError *string `json:"parseError"`
	Relics     []Relic `json:"relics"`
}

// Relic is a single relic item state. Effects and Curses always hold three
// entries; empty affix slots are normalized to -1 (raw 0xFFFFFFFF or 0).
type Relic struct {
	Index   int     `json:"index"`
	ItemID  int     `json:"itemId"`
	Effects []int64 `json:"effects"`
	Curses  []int64 `json:"curses"`
}

const (
	bnd4HeaderLen      = 64
	bnd4EntryHeaderLen = 32
	ivSize             = 16

	// Per-entry integrity: MD5(plain[4 : L-28]) is stored at plain[L-28 : L-12],
	// followed by 12 bytes of padding.
	checksumStart   = 4
	checksumTrailer = 28

	characterSlots = 10   // USERDATA_0..9 are character slots; USERDATA_10 is shared.
	stateSlotCount = 5120 // fixed number of variable-length item state records
	stateStart     = 0x14 // item state records begin at this plaintext offset
	nameGap        = 0x94 // gap between the end of the state area and the name
	nameMaxUnits   = 16   // player name: UTF-16LE, at most 16 code units, NUL-terminated

	// Item entry area: 3065 fixed 14-byte records, preceded by a u32 count,
	// located 0x5B8 past the player name. Only states referenced here are in
	// the character's actual inventory — stale (deleted) relic states remain
	// in the state area and must be filtered out.
	entrySlotCount = 3065
	entryRecordLen = 14
	entryCountGap  = 0x5B8
)

var (
	bnd4Magic  = []byte("BND4")
	entryMagic = []byte{0x40, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF}
	// faceMagic locates the character-slot occupancy flags inside USERDATA_10:
	// the 10 flag bytes sit 61 bytes before a match.
	faceMagic = []byte{0x27, 0x00, 0x00, 0x46, 0x41, 0x43, 0x45}
	// aesKey is the hardcoded AES-128 key shared by every entry ("DS2 key").
	aesKey = []byte{
		0x18, 0xF6, 0x32, 0x66, 0x05, 0xBD, 0x17, 0x8A,
		0x55, 0x24, 0x52, 0x3A, 0xC0, 0xA0, 0xC6, 0x09,
	}
)

// errNotSaveFile is returned when the input is not a BND4 archive at all.
var errNotSaveFile = errors.New("不是有效的存档文件")

// Parse decodes a .sl2/.co2 archive and extracts every occupied character's
// relics. Structural corruption (bad magic, out-of-bounds entries, cipher
// length) fails the whole parse; a failure inside a single character slot is
// reported through that character's ParseError so other slots still load.
func Parse(data []byte, fileName string) (*Payload, error) {
	if len(data) < len(bnd4Magic) || !bytes.Equal(data[:len(bnd4Magic)], bnd4Magic) {
		return nil, errNotSaveFile
	}
	if len(data) < bnd4HeaderLen {
		return nil, errors.New("存档文件损坏：文件头不完整")
	}
	entryCount := int(int32(binary.LittleEndian.Uint32(data[12:16])))
	if entryCount <= 0 {
		return nil, fmt.Errorf("存档文件损坏：条目数无效（%d）", entryCount)
	}

	// Only the entries this feature reads are decoded: USERDATA_0..9 hold the
	// character slots and USERDATA_10 the shared account data.
	parsed := entryCount
	if parsed > characterSlots+1 {
		parsed = characterSlots + 1
	}

	// Structural pass: the entry header table must be intact for every entry
	// this feature reads; anything past the header table is per-entry state.
	refs := make([]entryRef, parsed)
	for i := 0; i < parsed; i++ {
		ref, err := readEntryHeader(data, i)
		if err != nil {
			return nil, err
		}
		refs[i] = ref
	}

	// Entry-level failures from here on are isolated: a broken shared entry
	// falls back to "all slots occupied", a broken character slot is reported
	// through that character's ParseError. checksumOk covers the entries this
	// parse actually consumed.
	checksumOk := true
	decrypt := func(i int) ([]byte, error) {
		plain, err := decryptEntry(data, refs[i])
		if err != nil {
			return nil, err
		}
		if !verifyChecksum(plain) {
			checksumOk = false
		}
		return plain, nil
	}

	occupied := allOccupied()
	if parsed > characterSlots {
		if shared, err := decrypt(characterSlots); err == nil {
			occupied = slotFlags(shared)
		}
	}

	characters := make([]Character, 0, characterSlots)
	for slot := 0; slot < characterSlots && slot < parsed; slot++ {
		if !occupied[slot] {
			continue
		}
		plain, err := decrypt(slot)
		if err != nil {
			msg := fmt.Sprintf("该槽位解密失败：%v", err)
			characters = append(characters, Character{
				Slot: slot, Name: fallbackName(slot), ParseError: &msg, Relics: []Relic{},
			})
			continue
		}
		characters = append(characters, parseCharacter(slot, plain))
	}

	return &Payload{FileName: fileName, ChecksumOk: checksumOk, Characters: characters}, nil
}

type entryRef struct {
	size       int
	dataOffset int
}

// readEntryHeader validates entry i's header row (magic and bounds). The
// bounds check is written overflow-safe so a crafted size/offset pair cannot
// wrap on 32-bit builds and bypass the guard.
func readEntryHeader(data []byte, i int) (entryRef, error) {
	pos := bnd4HeaderLen + bnd4EntryHeaderLen*i
	if pos+bnd4EntryHeaderLen > len(data) {
		return entryRef{}, fmt.Errorf("存档文件损坏：条目 %d 头部越界", i)
	}
	if !bytes.Equal(data[pos:pos+len(entryMagic)], entryMagic) {
		return entryRef{}, fmt.Errorf("存档文件损坏：条目 %d 魔数不符", i)
	}
	size := int(int32(binary.LittleEndian.Uint32(data[pos+8:])))
	dataOffset := int(int32(binary.LittleEndian.Uint32(data[pos+16:])))
	if size < 0 || dataOffset <= 0 || dataOffset > len(data)-size {
		return entryRef{}, fmt.Errorf("存档文件损坏：条目 %d 数据越界", i)
	}
	return entryRef{size: size, dataOffset: dataOffset}, nil
}

// decryptEntry decrypts one entry's data (IV-prefixed AES-128-CBC, no
// padding). Errors here are entry-local and isolated by the caller.
func decryptEntry(data []byte, ref entryRef) ([]byte, error) {
	if ref.size <= ivSize || (ref.size-ivSize)%aes.BlockSize != 0 {
		return nil, errors.New("加密数据长度无效")
	}
	iv := data[ref.dataOffset : ref.dataOffset+ivSize]
	ciphertext := data[ref.dataOffset+ivSize : ref.dataOffset+ref.size]
	block, err := aes.NewCipher(aesKey)
	if err != nil {
		return nil, err
	}
	plain := make([]byte, len(ciphertext))
	cipher.NewCBCDecrypter(block, iv).CryptBlocks(plain, ciphertext)
	return plain, nil
}

// verifyChecksum reports whether MD5(plain[4 : L-28]) matches the digest
// stored at plain[L-28 : L-12].
func verifyChecksum(plain []byte) bool {
	if len(plain) < checksumStart+checksumTrailer {
		return false
	}
	end := len(plain) - checksumTrailer
	sum := md5.Sum(plain[checksumStart:end])
	return bytes.Equal(sum[:], plain[end:end+md5.Size])
}

// allOccupied is the fallback occupancy table used when USERDATA_10 is
// missing or unreadable.
func allOccupied() [characterSlots]bool {
	var flags [characterSlots]bool
	for i := range flags {
		flags[i] = true
	}
	return flags
}

// slotFlags locates the 10 character-slot occupancy flags in USERDATA_10
// (61 bytes before the FACE magic). When the magic is missing, every slot
// is assumed occupied.
func slotFlags(shared []byte) [characterSlots]bool {
	flags := allOccupied()
	for pos := 0; pos+len(faceMagic) <= len(shared); {
		hit := bytes.Index(shared[pos:], faceMagic)
		if hit < 0 {
			break
		}
		start := pos + hit - 61
		if start >= 0 && start+characterSlots <= len(shared) && flagBytesValid(shared[start:start+characterSlots]) {
			for i := 0; i < characterSlots; i++ {
				flags[i] = shared[start+i] == 1
			}
			return flags
		}
		pos += hit + 1
	}
	return flags
}

// flagBytesValid rejects candidate flag runs containing anything but 0/1,
// mirroring the reference implementation's false-positive guard.
func flagBytesValid(b []byte) bool {
	for _, v := range b {
		if v > 1 {
			return false
		}
	}
	return true
}

// parseCharacter scans one decrypted character slot: 5120 variable-length
// item state records starting at 0x14, then the player name 0x94 past the
// end of the state area. Truncation is reported via ParseError, never panic.
func parseCharacter(slot int, plain []byte) Character {
	c := Character{Slot: slot, Name: fallbackName(slot), Relics: []Relic{}}
	fail := func(format string, args ...interface{}) Character {
		msg := fmt.Sprintf(format, args...)
		c.ParseError = &msg
		return c
	}

	off := stateStart
	gaHandles := []uint32{}
	for rec := 0; rec < stateSlotCount; rec++ {
		if off+8 > len(plain) {
			return fail("存档数据截断：第 %d 条物品记录越界", rec)
		}
		gaHandle := binary.LittleEndian.Uint32(plain[off:])
		itemID := binary.LittleEndian.Uint32(plain[off+4:])

		// Record length by type nibble; unknown non-empty types (e.g. goods,
		// 0xB...) occupy the 8 header bytes only.
		size := 8
		switch gaHandle & 0xF0000000 {
		case 0x80000000: // weapon
			size = 88
		case 0x90000000: // armor
			size = 16
		case 0xC0000000: // relic
			size = 80
		}
		if off+size > len(plain) {
			return fail("存档数据截断：第 %d 条物品记录不完整", rec)
		}
		if gaHandle&0xF0000000 == 0xC0000000 {
			gaHandles = append(gaHandles, gaHandle)
			c.Relics = append(c.Relics, Relic{
				Index:  len(c.Relics),
				ItemID: int(itemID & 0x00FFFFFF),
				Effects: []int64{
					affixAt(plain, off+16),
					affixAt(plain, off+20),
					affixAt(plain, off+24),
				},
				Curses: []int64{
					affixAt(plain, off+56),
					affixAt(plain, off+60),
					affixAt(plain, off+64),
				},
			})
		}
		off += size
	}

	nameOff := off + nameGap
	if name, ok := readName(plain, nameOff); ok {
		c.Name = name
	}
	c.Relics = filterOwnedRelics(plain, nameOff, c.Relics, gaHandles)
	return c
}

// filterOwnedRelics keeps only relics whose gaHandle is referenced by the
// item entry area — deleted relics leave stale records in the state area.
// When the entry area is unreadable the list is returned unfiltered.
func filterOwnedRelics(plain []byte, nameOff int, relics []Relic, gaHandles []uint32) []Relic {
	countOff := nameOff + entryCountGap
	if countOff < 0 || countOff+4 > len(plain) {
		return relics
	}
	owned := make(map[uint32]bool)
	readable := false
	for slot := 0; slot < entrySlotCount; slot++ {
		pos := countOff + 4 + slot*entryRecordLen
		if pos+entryRecordLen > len(plain) {
			break
		}
		readable = true
		ga := binary.LittleEndian.Uint32(plain[pos:])
		if ga&0xF0000000 == 0xC0000000 {
			owned[ga] = true
		}
	}
	if !readable {
		return relics
	}
	kept := make([]Relic, 0, len(relics))
	for i, relic := range relics {
		if owned[gaHandles[i]] {
			relic.Index = len(kept)
			kept = append(kept, relic)
		}
	}
	return kept
}

// fallbackName is the display name used when a slot's real name cannot be
// read; 1-based to match how the UI numbers slots.
func fallbackName(slot int) string {
	return fmt.Sprintf("槽位 %d", slot+1)
}

// affixAt reads an affix ID and normalizes both empty sentinels
// (0xFFFFFFFF and 0) to -1.
func affixAt(plain []byte, off int) int64 {
	v := binary.LittleEndian.Uint32(plain[off:])
	if v == 0xFFFFFFFF || v == 0 {
		return -1
	}
	return int64(v)
}

// readName decodes the UTF-16LE player name (at most 16 code units,
// NUL-terminated). It reports false when the region is unreadable or empty,
// letting the caller keep the "槽位 N" fallback.
func readName(plain []byte, off int) (string, bool) {
	if off < 0 || off+2 > len(plain) {
		return "", false
	}
	units := make([]uint16, 0, nameMaxUnits)
	for i := 0; i < nameMaxUnits; i++ {
		p := off + 2*i
		if p+2 > len(plain) {
			break
		}
		u := binary.LittleEndian.Uint16(plain[p:])
		if u == 0 {
			break
		}
		units = append(units, u)
	}
	if len(units) == 0 {
		return "", false
	}
	return string(utf16.Decode(units)), true
}
