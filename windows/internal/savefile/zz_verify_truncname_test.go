package savefile

import (
	"encoding/binary"
	"testing"
)

// Temporary verification test (not part of the repo): a character plaintext
// whose 5120 state records are complete but whose name region is cut after
// 4 complete UTF-16 units.
func TestVerifyTruncatedNameRegion(t *testing.T) {
	nameOff := stateStart + stateSlotCount*8 + nameGap // 41128
	plain := make([]byte, nameOff+8)                   // 41136, multiple of 16
	if len(plain)%16 != 0 {
		t.Fatalf("plain len %d not multiple of 16", len(plain))
	}
	for i, r := range "TEST" {
		binary.LittleEndian.PutUint16(plain[nameOff+2*i:], uint16(r))
	}
	c := parseCharacter(3, plain)
	t.Logf("name=%q parseError=%v", c.Name, c.ParseError)
	if c.Name != "TEST" {
		t.Errorf("Go readName did not recover partial name, got %q", c.Name)
	}
	if c.ParseError != nil {
		t.Errorf("unexpected parseError: %s", *c.ParseError)
	}

	// Same geometry through Swift's guard: offset+32 <= count fails
	// (41128+32=41160 > 41136), so characterName returns nil.
	if nameOff+32 <= len(plain) {
		t.Errorf("geometry does not exercise the Swift guard")
	}
}
