// oodledec.exe <oo2core_9_win64.dll> <in.krak> <out.bin> <dst_len>
// oodledec.exe <oo2core_9_win64.dll> --batch <manifest.txt>
//
// 在 Wine/CrossOver 里用游戏自带的 Oodle DLL 解压 Kraken 数据。
// --batch：manifest 每行 "in<TAB>out<TAB>dst_len"，一次进程解完整批文件
// （extract_msb.py 要解 400 多张地图，逐个起 Wine 每次要 3–4 秒）。
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
	"syscall"
	"unsafe"
)

func decompress(proc *syscall.LazyProc, in, out string, n int) error {
	src, err := os.ReadFile(in)
	if err != nil {
		return err
	}
	dst := make([]byte, n+64)
	// OodleLZ_Decompress(compBuf, compBufSize, rawBuf, rawLen, fuzzSafe=1, checkCRC=0, verbosity=0,
	//   decBufBase=0, decBufSize=0, fpCallback=0, cbUserData=0, decoderMemory=0, decoderMemorySize=0, threadPhase=3)
	r, _, _ := proc.Call(
		uintptr(unsafe.Pointer(&src[0])), uintptr(len(src)),
		uintptr(unsafe.Pointer(&dst[0])), uintptr(n),
		1, 0, 0, 0, 0, 0, 0, 0, 0, 3)
	if int(r) != n {
		return fmt.Errorf("OodleLZ_Decompress returned %d, expected %d", int(r), n)
	}
	return os.WriteFile(out, dst[:n], 0o644)
}

func main() {
	batch := len(os.Args) == 4 && os.Args[2] == "--batch"
	if len(os.Args) != 5 && !batch {
		fmt.Fprintln(os.Stderr, "usage: oodledec <oo2core.dll> <in> <out> <dst_len>")
		fmt.Fprintln(os.Stderr, "       oodledec <oo2core.dll> --batch <manifest>")
		os.Exit(2)
	}
	dll := syscall.NewLazyDLL(os.Args[1])
	proc := dll.NewProc("OodleLZ_Decompress")

	if !batch {
		n, _ := strconv.Atoi(os.Args[4])
		if err := decompress(proc, os.Args[2], os.Args[3], n); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}

	f, err := os.Open(os.Args[3])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	done, bad := 0, 0
	for sc.Scan() {
		line := strings.TrimRight(sc.Text(), "\r")
		if line == "" {
			continue
		}
		parts := strings.Split(line, "\t")
		if len(parts) != 3 {
			fmt.Fprintf(os.Stderr, "bad manifest line: %q\n", line)
			bad++
			continue
		}
		n, _ := strconv.Atoi(parts[2])
		if err := decompress(proc, parts[0], parts[1], n); err != nil {
			fmt.Fprintf(os.Stderr, "%s: %v\n", parts[0], err)
			bad++
			continue
		}
		done++
	}
	fmt.Printf("ok %d, failed %d\n", done, bad)
	if bad > 0 {
		os.Exit(1)
	}
}
