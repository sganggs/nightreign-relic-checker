// oodledec.exe <oo2core_9_win64.dll> <in.krak> <out.bin> <dst_len>
// 在 Wine/CrossOver 里用游戏自带的 Oodle DLL 解压一段 Kraken 数据。
package main

import (
	"fmt"
	"os"
	"strconv"
	"syscall"
	"unsafe"
)

func main() {
	if len(os.Args) != 5 {
		fmt.Fprintln(os.Stderr, "usage: oodledec <oo2core.dll> <in> <out> <dst_len>")
		os.Exit(2)
	}
	src, err := os.ReadFile(os.Args[2])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	n, _ := strconv.Atoi(os.Args[4])
	dst := make([]byte, n+64)
	dll := syscall.NewLazyDLL(os.Args[1])
	proc := dll.NewProc("OodleLZ_Decompress")
	// OodleLZ_Decompress(compBuf, compBufSize, rawBuf, rawLen, fuzzSafe=1, checkCRC=0, verbosity=0,
	//   decBufBase=0, decBufSize=0, fpCallback=0, cbUserData=0, decoderMemory=0, decoderMemorySize=0, threadPhase=3)
	r, _, _ := proc.Call(
		uintptr(unsafe.Pointer(&src[0])), uintptr(len(src)),
		uintptr(unsafe.Pointer(&dst[0])), uintptr(n),
		1, 0, 0, 0, 0, 0, 0, 0, 0, 3)
	if int(r) != n {
		fmt.Fprintf(os.Stderr, "OodleLZ_Decompress returned %d, expected %d\n", int(r), n)
		os.Exit(1)
	}
	if err := os.WriteFile(os.Args[3], dst[:n], 0o644); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
