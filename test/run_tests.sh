#!/bin/bash
# Regression test for NativeWriter / NativeReader (Linux: needs xvfb-run).
#
#   test/run_tests.sh <image> [out_dir]
#
# Compiles everything, then for 1 band and 4 bands: NativeWriter writes the
# image (test.Drive, Save's defaults: Pixel Resolution 4, Color Resolution 3),
# NativeReader decodes it (test.Decode), and the size and the decoded image's
# MD5 are checked against EXPECTED for bluejay.jpg (bcrow99/TestImages).
# Native methods must keep these the same: the files are byte for byte
# SimpleWriter2's (DeltaEncoder).
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="$1"; OUT="${2:-out}"
[ -n "$IMAGE" ] || { echo "usage: test/run_tests.sh <image> [out_dir]"; exit 1; }
IMAGE="$(cd "$(dirname "$IMAGE")" && pwd)/$(basename "$IMAGE")"
mkdir -p "$OUT/classes"; OUT="$(cd "$OUT" && pwd)"
javac --release 8 -nowarn -Xlint:-options -encoding UTF-8 -Xlint:-unchecked -d "$OUT/classes" "$HERE"/*.java "$HERE"/test/*.java
cd "$OUT"
declare -A SIZE=([n1]=61174 [n4]=62689)
MD5=7c41049db7c073c7026278bcf58b15a5
fail=0
for job in n1 n4; do
	bands=${job#n}
	xvfb-run -a java -cp classes test.Drive NativeWriter "$IMAGE" "$job.bin" 30 bands=$bands > "$job.log" 2>&1 || { echo "$job: writer failed (see $job.log)"; fail=1; continue; }
	size=$(stat -c %s "$job.bin")
	md5=$(java -Djava.awt.headless=true -cp classes test.Decode "$job.bin" 2>/dev/null | awk '{print $2}')
	status=ok
	if [ "$(basename "$IMAGE")" = bluejay.jpg ]; then
		[ "$size" = "${SIZE[$job]}" ] || { status="FAILED: expected ${SIZE[$job]} bytes"; fail=1; }
		[ "$md5" = "$MD5" ] || { status="FAILED: decoded MD5 $md5, expected $MD5"; fail=1; }
	fi
	printf '%-3s %2s band(s) %8d bytes  %s  %s\n' "$job" "$bands" "$size" "$md5" "$status"
done
exit $fail
