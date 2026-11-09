# NativeEncoder

NativeWriter and NativeReader: DeltaEncoder's SimpleWriter2 and SimpleReader2
(Simple 2 format 2), renamed, with the mapper classes they use, to be sped up
by replacing pure Java methods with native methods in C while the GUI and the
threading stay in Java.

They write and read exactly the same files as SimpleWriter2 and SimpleReader2,
so files go back and forth between the two repositories, and any native method
must leave the files and the decoded images byte for byte the same.

So far these are in C: the writer's least-squares fit
(DeltaMapper.RowFit.plane) and its coder (DeltaMapper.packMixedDeltas), and
the reader's decoding (DeltaMapper.getValuesFromRowFitChannels: the decoder
and the fit, row by row) and its last steps (adding the minimums back,
getBlueGreenRed, resize2 and getPixel, in one pass on every core), and the
writer's Apply (quantizing, the candidate channels, the preview) and its
decode check after Save. When the
library DeltaMapper (native/DeltaMapper.dll, libDeltaMapper.so) has been
built, NativeWriter and NativeReader use them and say so ("Fit and coder: C
(...)", "Decoder and fit: C (...)"); without it, or run with
`-Dnative=false`, they use the Java. The library is looked for first in the
repository's own native folder, and must be as new as the Java (they check a
version number): an older one is reported ("... is older than the Java:
rebuild the C") and the Java used. The C decoder starts on a band once all
its bytes are read (the Java's starts on each channel as its bytes arrive).

NativeWriter2 and NativeReader2 are the Huffman pair: DeltaEncoder's
HuffmanWriter and HuffmanReader (Huffman format 'H' 1, the same files) with
the same native methods where they apply: the writer's fit and Apply, and
the reader's fit (the C decoder's machinery with the deltas given:
DeltaMapper.getValuesFromRowFitDeltas) and last steps. Their Huffman coding
and decoding are C too (StringMapper's unary strings and bit-pair transform,
CodeMapper's canonical code, in native/StringMapper.c and CodeMapper.c);
only the code lengths and their small Deflate'd table are Java.

On scrubjay.jpg (3518 x 2697, Save's defaults, 16 cores, Windows), with the
same file and the same decoded image either way:

| | Java | C |
|---|---|---|
| Save, 1 band | 1.12 s | 0.54 s |
| Save, 4 bands | | 0.43 s |
| Decode, 1 band | 1.45 s | 0.72 s |
| Decode, 4 bands | | 0.55 s |

Decoding scrubjay.jpg on a 2-core Linux machine, after a warm-up (the same
image from every one):

| | 1 band | 4 bands |
|---|---|---|
| NativeReader (C decoder and fit) | 2.9 s | 2.7 s |
| NativeReader2, fit in Java | 3.3 s | 3.0 s |
| NativeReader2, fit in C | 2.2 s | 1.8 s |
| NativeReader2, fit and Huffman decoding in C | 1.9 s | 1.7 s |

Most of what's left is the fit (about 1.5 s); the Huffman decoding is under
0.2 s. The three channels' Huffman coding, one after another, went from 1.38 s
in Java to 0.29 s in C, and their decoding from 0.65 s to 0.29 s.

Save prints its timeline (when each channel's fit and coding ended). With
one band it's the three fits (run at the same time) and then the last
channel's coding, each a serial loop: more bands is the way to go faster.

## Layout: two Eclipse projects in one repository

| Folder | Eclipse project | What it is |
|---|---|---|
| java/src | NativeEncoder (Java) | NativeWriter, NativeReader and the mappers (the default package); src/test: the regression test's tools, test.Drive and test.Decode (package test) |
| java/bench | | the Java halves of the benchmarks (RowFitBench, CoderBench, DecoderBench; the default package: they use DeltaMapper's package-private classes) |
| java/run_tests.sh, .bat | | the regression test |
| java/launch | | shared run configurations (they appear under Run and External Tools) |
| native | NativeEncoder_C (C, CDT; on Linux, after native/eclipse-linux.sh) | the C versions (DeltaMapper.c, .h, ArithmeticMapper.c, .h, StringMapper.c, .h, CodeMapper.c, .h), their JNI side (DeltaMapper_jni.c), the C halves of the benchmarks (bench_RowFit.c), the Makefile |

| File | What it is |
|---|---|
| java/src/NativeWriter.java | the writer (SimpleWriter2 1.1) |
| java/src/NativeReader.java | the reader (SimpleReader2 1.1) |
| java/src/NativeWriter2.java, NativeReader2.java | NativeWriter and NativeReader with Huffman coding in place of the mixed context coding: the same fit and deltas, then StringMapper's unary strings (its bit-pair transform kept if it saves enough) and CodeMapper's canonical Huffman code over the strings' bytes, per channel and band; their own format ('H' 1). Less compression (on the test photos 9-29% bigger files), faster to decode. In C, as NativeWriter's and NativeReader's are: the writer's fit and Apply, the reader's fit (the C decoder's, with the deltas given) and last steps, and the Huffman coding and decoding (all but the code lengths) |
| java/src/DeltaMapper.java | the channels, the least-squares fit from the rows above (RowFit, RowWave), the mixed context coding (MixedModels): DeltaEncoder's DeltaMapper trimmed to what these programs use |
| java/src/ArithmeticMapper.java | the range coder (RangeEncoder, RangeDecoder, Arriving): DeltaEncoder's ArithmeticMapper, trimmed the same way |
| java/src/ResizeMapper.java, ViewerSupport.java | resizing (resize2); the windows, dialogs and parallel helpers |
| java/src/CodeMapper.java, StringMapper.java, SegmentMapper.java | DeltaEncoder's, whole: NativeWriter2 and NativeReader2 use CodeMapper's and StringMapper's Huffman coding (the Java when the library isn't there); SegmentMapper isn't used |
| native/DeltaMapper.c, .h | DeltaMapper's methods in C, under the same names (so far RowFit: RowFit_init, _start, _moveTo, _addColumns, _solveRow, _solvePoints, _predict, _plane) |
| native/DeltaMapper.c, .h (2) | ... and the mixed context coder: DeltaMapper_packMixedDeltas (MixedModels_init, _contexts, _contextsRow, _update, _encode), the same bytes as packMixedDeltas |
| native/DeltaMapper.c, .h (3) | ... and the reader's decoding: DeltaMapper_decodeRowFitChannels (MixedModels_decode, _earlierRows; each channel's decoder and helper threads, as RowWave), the same deltas and values as getValuesFromRowFitChannels |
| native/DeltaMapper.c, .h (4) | ... and the reader's last steps: DeltaMapper_getPixels (getBlueGreenRed, ResizeMapper.resize2 and getPixel in one pass, on threads), the same image as the Java |
| native/DeltaMapper.c, .h (5) | ... and the writer's Apply (DeltaMapper_applyQuantize, _applyPreview) and decode check (DeltaMapper_checkMixedDeltas) |
| native/DeltaMapper.c, .h (6) | ... and NativeReader2's fit: DeltaMapper_rebuildRowFitChannels (the decoder's threads with the deltas given, nothing decoded), the same values as getValuesFromRowFitDeltas |
| native/StringMapper.c, .h | StringMapper's unary strings in C for the Huffman pair: StringMapper_getStringList (getHistogram, getRankTable, packStrings, compressStrings), _decompressStrings, _unpackStrings; the bit-pair transforms run a byte at a time through tables made from the Java's rules: the same bits |
| native/CodeMapper.c, .h | CodeMapper's canonical Huffman code in C: CodeMapper_packRegularCode, _unpackRegularCode (the code lengths come from the Java's getRegularHuffmanLength) |
| native/ArithmeticMapper.c, .h | ArithmeticMapper's range coder in C (RangeEncoder_init, _encode, _finish; RangeDecoder_init, _target, _decode) |
| native/DeltaMapper_jni.c | the native methods DeltaMapper.java declares (rowFitPlane, packMixedDeltasNative, decodeRowFitChannelsNative, getPixelsNative, applyQuantizeNative, applyPreviewNative, checkMixedDeltasNative, rebuildRowFitChannelsNative) and NativeWriter2 declares (stringListNative, packRegularCodeNative, huffmanDecodeNative), built with DeltaMapper.c, ArithmeticMapper.c, StringMapper.c and CodeMapper.c into the library DeltaMapper |

## Setting up Eclipse (Windows and Linux)

You need Eclipse with Java (JDT) and C/C++ (CDT: Help > Eclipse Marketplace >
"Eclipse C/C++ IDE CDT"), a JDK 8 or later, and gcc and make: on Windows
MSYS2's ucrt64 environment in C:\msys64\ucrt64 (in an MSYS2 UCRT64 shell,
`pacman -S mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-make`), on Linux
the distribution's gcc and make. Building the library needs the JDK's
headers, found through JAVA_HOME (see below).

On Windows the Makefile always compiles with C:/msys64/ucrt64/bin/gcc.exe,
even if another gcc (MSYS2's mingw64, an older MinGW) comes first on the
PATH or is the one Eclipse finds; `make MINGW=D:/msys64/ucrt64` points it
elsewhere. ucrt64 is the one to use: it links against Windows' own Universal
C Runtime, as current Windows programs do, where mingw64 uses the old
msvcrt.dll. The programs are linked statically, so they don't need ucrt64's
DLLs on the PATH to run.

1. **The Java project.** File > Import > General > Existing Projects into
   Workspace, root directory the repository's `java` folder. Leave "Copy
   projects into workspace" off: the launches find the C folder next to it.
   It builds with the workspace's JRE at Java 8 compliance.
2. **The C project.** File > Import > General > Existing Projects into
   Workspace, root directory the repository's `native` folder (Copy off
   again). It's a Makefile project, `NativeEncoder_C`, built by
   native/Makefile. Its native/.cproject is for Windows (configuration
   **Windows**: C:\msys64\ucrt64\bin\mingw32-make, with ucrt64's bin put
   first on the build's PATH). **On Linux, first run `native/eclipse-linux.sh`**
   (before importing, and again after unzipping a newer zip over the
   folder, then refresh): it puts in the Linux one, whose only
   configuration, **Linux**, runs make. (Switching configurations inside
   Eclipse doesn't work there.) The Makefile finds the JDK's
   headers from JAVA_HOME, or if that isn't set, from the `java` command
   (Windows) or `javac` (Linux), so nothing needs setting in Eclipse. If your
   MSYS2 isn't in C:\msys64, change the build command and PATH in Project >
   Properties > C/C++ Build, and run `make MINGW=...`.

   (Don't make the C project with Eclipse's wizards: they make an
   "Executable" project that builds with a makefile of Eclipse's own, or its
   internal builder, which can't build the library.)
3. **Build the C.** Project > Build Project on NativeEncoder_C (it runs the
   Makefile: the library DeltaMapper with -O3 -march=native, bench_RowFit
   with -O3, bench_RowFit_native with -O3 -march=native, all
   -ffp-contract=off). The console should start with `mingw32-make all`
   (or `make all`). -march=native builds for this machine's processor,
   so build it on the machine that runs it. Close NativeWriter before
   rebuilding: Windows won't replace a DLL a program has loaded. Clean
   (Project > Clean) removes the library and the benchmarks.

## Updating from a newer zip

The zip has no library or class files: after updating, rebuild the C if
any of native's .c or .h files changed (the writers and readers say "...
is older than the Java: rebuild the C" when it's needed, and use the Java
until then).

- **Windows.** Close the programs, copy the zip's `java` and `native`
  folders over the repository's (replacing files), delete any files the
  newer version renamed or removed (copying over leaves the old ones in
  place), then in Eclipse select both projects and press F5 (Refresh). The
  Java rebuilds itself; build NativeEncoder_C (configuration **Windows**)
  if the C changed. The DLL stays where it was.
- **Linux.** Delete both projects in Eclipse (contents kept), unzip over
  the folder, run `native/eclipse-linux.sh`, re-import them (File > Import >
  Existing Projects into Workspace, the repository's folder, with "Search
  for nested projects"), and build the C. Refreshing in place doesn't take
  the Linux .cproject reliably.

If NativeEncoder_C's Build or Clean does nothing (an empty console), its
native/.cproject may have been replaced by one of Eclipse's own (a
configuration "Default" with a "MinGW GCC" toolchain): copy the zip's
native/.cproject and native/.project back over it, refresh, and if
Build Configurations > Set Active still doesn't offer Windows, delete and
re-import just NativeEncoder_C.

## Running

From Run > Run Configurations (and Run > External Tools for the C), all
shared from java/launch:

| Launch | What it does |
|---|---|
| NativeWriter | asks for an image; File > Save writes `foo` in the java folder (with the C fit if native has the library) |
| NativeReader | asks for a file (e.g. that `foo`) |
| NativeWriter2, NativeReader2 | the same for the Huffman pair (NativeWriter2's Save also writes `foo`; each reader says if a file is the other's format) |
| RowFitBench | asks for an image; times RowFit's fit in Java and, if the library is built, in C through JNI (as NativeWriter runs it), and writes native/rowfit.dump |
| bench_RowFit (Windows / Linux), bench_RowFit_native (...) | the C half: reads native/rowfit.dump, checks every prediction against the Java's, and times the same way |
| DecoderBench | asks for an image; codes it as Save does, then times the reader's decoding (all three channels at once) in Java and in C through JNI, checking the deltas and values are the same |
| CoderBench | asks for an image; makes its deltas as Save does, then times the mixed coder in Java (packMixedDeltasJava) and in C through JNI, checking the bytes are the same |

The Java launches give the JVM `--enable-native-access=ALL-UNNAMED`, which
Java 17 and later want before a program loads a library (without it they
warn, and a future release will refuse). Java 8 to 16 don't know the option
and won't start with it: for those, take it out of the launch's VM
arguments. The scripts give it only if the java they run accepts it.

The benchmark is the RowFitBench launch, then one of the bench_RowFit ones.
From a command prompt, `native\run_bench.bat image` (or
`native/run_bench.sh image`) builds the C, runs all of them and writes
native/bench_results.txt. On Windows it takes JAVA_HOME from the `java`
command if it isn't set.

## Test

```
java\run_tests.bat bluejay.jpg     # Windows
java/run_tests.sh bluejay.jpg      # Linux (needs xvfb-run)
```

It writes the image in 1 and 4 bands with NativeWriter (test.Drive), in
1 band with the Java fit and coder (`-Dnative=false`), and in 1 and 4 bands
with NativeWriter2, decodes them (test.Decode, with the reader for the
file's format), and checks the sizes and the decoded
image's MD5 for the images it knows (bcrow99/TestImages): bluejay.jpg
(61,174 and 62,689 bytes; Huffman 69,095 and 70,893) and scrubjay.jpg
(4,075,255 and 4,080,169 bytes; Huffman 4,453,703 and 4,454,159);
for others it prints them. Each line ends with how long decoding took (a second time, after a warm-up)
and what the writer used, C or Java (the decoder uses the same). Leave
the writer's windows be: they close themselves.
