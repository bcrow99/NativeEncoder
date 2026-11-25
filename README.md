# NativeEncoder

NativeWriter and NativeReader: DeltaEncoder's SimpleWriter2 and HuffmanWriter
(and their readers) in one, with the mapper classes they use, to be sped up
by replacing pure Java methods with native methods in C while the GUI and the
threading stay in Java. (They were NativeSimpleWriter / NativeSimpleReader and
NativeHuffmanWriter / NativeHuffmanReader.)

The writer has two menus for how Save codes the image:

- **Delta**: LS, the least-squares fit from the rows above (the default), or
  Avg, the classic average filter (each pixel from (left + above) / 2).
- **Entropy**: Context aware (the default), the Simple 2 format ('F');
  Context tables, the Context tables format ('T') 2: fixed tables chosen by
  each delta's own context (its neighbours' activity and its second
  opinion) in place of the context aware coding's adaptive models (the
  deltas counted once by context, the counts written as tables, the deltas
  rANS coded with them; no other channel used, so all the channels decode
  at the same time), a little bigger (about 1-8%) and about three times as
  fast to decode (version 1, with the context aware coding's contexts, is
  read too) (coded and decoded in C with the library, ContextTables.c,
  else in Java, ContextTables); Huffman on the unary strings, the Huffman
  format ('H'); or Huffman tables (neighbour Huffman) on the deltas
  themselves, DeltaEncoder's HuffmanWriter2 coding:
  Huffman tables chosen by each delta's neighbours and a second opinion (how
  far the median edge detector is from the prediction, as the context aware
  coding has it), with a run mode and pairs in the quiet parts, and a delta's
  sign flipped where the opinion is negative ('N' version 3, the same files
  as HuffmanWriter2; versions 2 and 1, without the opinions, are still read;
  coded and decoded in C with the library, NeighbourMapper.c, else in Java,
  NeighbourMapper). Version 3 decodes a pixel at a time as the channel is
  rebuilt, since the opinions need the values.

With LS, the files are exactly SimpleWriter2's (Simple 2 format 2) and
HuffmanWriter's (Huffman format 3), so they go back and forth between the two
repositories. With Avg they're Simple 2 format 3 and Huffman format 4 (the
same with the delta type in the header). Huffman formats 3 and 4 code the
code lengths compactly (NeighbourMapper.packLengths), with no Deflate, so the
files don't depend on a zlib; the formats before them, 1 and 2, had the code
lengths Deflated, and are still read.
NativeReader reads them all, by the file's first byte, and DeltaEncoder's
GenericWriter and GenericReader write and read the same files. Any native method must
leave the files and the decoded images byte for byte the same.

In C so far: the writer's least-squares fit (DeltaMapper.RowFit.plane), its
context aware coder (DeltaMapper.packMixedDeltas) and decode check, and its
Apply (quantizing, the candidate channels, the preview); the Huffman coding
and decoding (StringMapper's unary strings and bit-pair transform,
CodeMapper's canonical code, in native/StringMapper.c and CodeMapper.c; only
the code lengths and their small table are Java); the reader's
context aware decoding (DeltaMapper.getValuesFromRowFitChannels and
getValuesFromAverageChannels: the decoder and the fit, row by row), its fit
for Huffman files (the decoder's machinery with the deltas given:
DeltaMapper.getValuesFromRowFitDeltas), and its last steps (adding the
minimums back, getBlueGreenRed, resize2 and getPixel, in one pass on every
core). When the library DeltaMapper (native/DeltaMapper.dll,
libDeltaMapper.so) has been built, NativeWriter and NativeReader use them and
say so ("Fit and coder: C (...)", "Decoder and fit: C (...)"); without it, or
run with `-Dnative=false`, they use the Java. The library is looked for first
in the repository's own native folder, and must be as new as the Java (they
check a version number): an older one is reported ("... is older than the
Java: rebuild the C") and the Java used. The C decoder starts on a band once
all its bytes are read (the Java's starts on each channel as its bytes
arrive).

On scrubjay (2 cores):

| | LS | Avg |
|---|---|---|
| Context aware: file | 4,075,255 bytes | 4,352,656 bytes |
| encode (1 band; 4 bands) | 1.56 s; 1.58 s | 1.12 s; 0.80 s |
| decode | 2.1-3.0 s | 1.0-1.25 s |
| Huffman: file | 4,453,703 bytes | 4,765,333 bytes |
| encode | 0.94 s | 0.27 s |
| decode | 1.1 s | 0.30-0.36 s |

The Bands menu goes up to 64 bands (each band at least 64 rows of the
quantized image), so a reader can keep about 96 cores busy on a big image:
three channel threads a band. Each band costs a little, as its fit and
contexts start again: on scrubjay, 33 bands (the most its 2,159 rows allow)
against 1 cost 1.25% with Context aware and LS (4,126,314 bytes), 0.9% with
Avg, and 0.24% with Huffman.

Many bands suit the average deltas, whose bands the reader decodes all at
once. With LS each band carries its fits (about 2.5 MB a channel on a wide
image), so the reader decodes LS bands one for each 6 processors at a time
(NativeReader.bandsAtOnce): with all of a 64-band LS file's bands at once,
decoding was up to 3 times slower than in 1 band on a Ryzen 7 5700G (16
threads, Windows), and a quarter slower on 4 cores (Linux). For a reader with
two threads a core, LS decoding is fastest with one a core (start /affinity
or taskset): the fits fill the caches the two share.

Where the time goes besides the coding (measured with Java's Flight
Recorder on a 7036 x 5394 frame): the C library keeps its large blocks for
reuse (native/BlockPool.c); the bands are coded and decoded at their place
in the channels, not copied out and back; the C writes the pixels straight
into the image, in one pass; and the LS writer refits the bands' first rows
all at once. Together, on the Ryzen with 16 threads, Huffman Avg went from
1.04 to 0.69 s (encode and decode) and Mixed Avg from 1.79 to 1.31 s. The
Huffman reader also decodes and rebuilds each Avg band in one C step
(NativeWriter.huffmanAverage; native version 16). Version 17 added the neighbour Huffman decoding in C (native/NeighbourMapper.c), version 18 its coding, version 19 the flipped signs (Neighbour Huffman version 2), version 20 the second opinions (Neighbour Huffman version 3, decoded inside the rebuilding: DeltaMapper_decodeRowFitChannelsWith, NeighbourMapper_average), version 21 the Context tables (ContextTables.c; NeighbourMapper.c's bit streams and code lengths moved to LengthCoding.c, which both use), version 22 Context tables version 2 (each channel's own contexts: ContextTables_pixel, ContextTables_average).

With the context aware coding the coder, which both share, is most of the
time. Its C decoder was sped up (about 12% on one core: the earlier
channels' context rows from running row sums, the inside pixels' contexts
without the edge tests, MED and the interval's bottom without branches), the
same bytes and values. Since then: the coder's divisions are multiplications
by reciprocals (exactly the same results), the model count is a constant in
each version of the coder, and an interior pixel's contexts take the terms
from the rows above from a pass over the row made before it
(MixedModels_rowAbove): about 6% more off the Avg decoding on one core.

NativePacketWriter and NativePacketReader are the Packet pair: DeltaEncoder's
PacketWriter and PacketReader (Packet format 'P' 3 and 5, the same files),
with every menu: Pixel and Color Resolution, the 14 delta types, the 8
entropy coders, the Segment Length levels and Auto. So far in C: the
segmentation of each channel's unary string at Save (SegmentMapper's
getSegmentedData3: cutting, merging and compressing the segments, combining
the ones that didn't compress; packSegments3; and unpackSegments3 and
restore2 for the round-trip check), and in the reader the segments back to
the string and its deltas (restore2, StringMapper.unpackStrings) and the last
steps (getBlueGreenRed, ResizeMapper.resize and getPixel in one pass). On
scrubjay (2 cores, defaults: average deltas, LZ77) Save's segmentation went
from 0.52 s to 0.17 s and the decode from 0.82 s to 0.38 s (cold), the same
file and image either way. Next in line: the writer's Apply (about 1.1 s,
all Java, run on each change of settings), and with the block map (delta
type 13) its rebuild in the reader, which takes 11 s there (Java,
DeltaMapper.getValuesFromBlockDeltas, one pixel at a time).

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
| Context aware (C decoder and fit) | 2.9 s | 2.7 s |
| Huffman, fit in Java | 3.3 s | 3.0 s |
| Huffman, fit in C | 2.2 s | 1.8 s |
| Huffman, fit and Huffman decoding in C | 1.9 s | 1.7 s |

Most of what's left is the fit (about 1.5 s); the Huffman decoding is under
0.2 s, and now runs alongside the fit (each channel's thread decodes its own
deltas, then rebuilds it, so the first channel starts while the others are
still decoding). On a machine with more cores, each channel's fit is also
shared among several helper threads (PairBench shows the parts with one
helper and with as many as the machine gets). On 16 cores (Windows,
scrubjay, 1 band) that took the Huffman decoding from 664 to 461 ms,
against the context aware's 717; its encode is 391 ms against 942, and its
decode check 106 against 398. The three channels' Huffman coding, one after another, went from 1.38 s
in Java to 0.29 s in C, and their decoding from 0.65 s to 0.29 s.

Save prints its timeline (when each channel's fit and coding ended). With
one band it's the three fits (run at the same time) and then the last
channel's coding, each a serial loop: more bands is the way to go faster.

## Layout: two Eclipse projects in one repository

| Folder | Eclipse project | What it is |
|---|---|---|
| java/src | NativeEncoder (Java) | the native writers and readers and the mappers (the default package); src/test: the regression test's tools, test.Drive and test.Decode (package test) |
| java/bench | | the Java halves of the benchmarks (RowFitBench, CoderBench, DecoderBench, PairBench, ScaleBench; the default package: they use DeltaMapper's package-private classes) |
| java/run_tests.sh, .bat | | the regression test |
| java/launch | | shared run configurations (they appear under Run and External Tools) |
| native | NativeEncoder_C (C, CDT; on Linux, after native/eclipse-linux.sh) | the C versions (DeltaMapper.c, .h, ArithmeticMapper.c, .h, StringMapper.c, .h, CodeMapper.c, .h, SegmentMapper.c, .h, NeighbourMapper.c, .h, ContextTables.c, .h, LengthCoding.c, .h, BlockPool.c, .h), their JNI side (DeltaMapper_jni.c), the C halves of the benchmarks (bench_RowFit.c), the Makefile |

| File | What it is |
|---|---|
| java/src/NativeWriter.java | the writer: SimpleWriter2 1.1 and HuffmanWriter in one, with the Delta (LS, Avg) and Entropy (Context aware, Context tables, Huffman, Huffman tables) menus; the Huffman coding (huffmanCode, huffmanRead, huffmanDecode) and its native methods (stringListNative, packRegularCodeNative, huffmanDecodeNative, rebuildHuffmanChannelsNative) |
| java/src/NativeReader.java | the reader for all its formats (decodeMixed: streaming, each channel as its bytes arrive; decodeHuffman, decodeTables, decodeAlone: read, then decoded and rebuilt a band at a time) |
| java/src/ContextTables.java, NeighbourMapper.java | DeltaEncoder's, whole: the Context tables coding and the neighbour Huffman coding (the Java when the library isn't there) |
| java/src/NativePacketWriter.java, NativePacketReader.java | DeltaEncoder's PacketWriter and PacketReader (2.2; Packet format 'P'), with the segmentation, the reader's deltas and its last steps in C. The reader's native methods are the writer's (segmentNative, packSegmentsNative, restoreNative, restoreDeltasNative) |
| java/src/DeltaMapper.java | the channels, the deltas of every type, the least-squares fit from the rows above (RowFit, RowWave), the context aware coding (MixedModels): DeltaEncoder's DeltaMapper, whole, with the native methods' declarations and the Java they stand in for |
| java/src/ArithmeticMapper.java | the arithmetic and range coders (RangeEncoder, RangeDecoder, Arriving): DeltaEncoder's ArithmeticMapper, whole, plus Arriving.awaitAll |
| java/src/ResizeMapper.java, ViewerSupport.java | resizing (resize, resize2); the windows, dialogs and parallel helpers |
| java/src/CodeMapper.java, StringMapper.java, SegmentMapper.java | DeltaEncoder's, whole: NativeWriter and NativeReader use CodeMapper's and StringMapper's Huffman coding, the Packet pair all three (the Java when the library isn't there) |
| native/DeltaMapper.c, .h | DeltaMapper's methods in C, under the same names (so far RowFit: RowFit_init, _start, _moveTo, _addColumns, _solveRow, _solvePoints, _predict, _plane) |
| native/DeltaMapper.c, .h (2) | ... and the context aware coder: DeltaMapper_packMixedDeltas (MixedModels_init, _contexts, _contextsRow, _update, _encode), the same bytes as packMixedDeltas |
| native/DeltaMapper.c, .h (3) | ... and the reader's decoding: DeltaMapper_decodeRowFitChannels (MixedModels_decode, _earlierRows; each channel's decoder and helper threads, as RowWave), the same deltas and values as getValuesFromRowFitChannels; DeltaMapper_decodeAverageChannels, the same for the average deltas (getValuesFromAverageChannels: each channel's decoder thread, with the average of left and above in place of the fit) |
| native/DeltaMapper.c, .h (4) | ... and the reader's last steps: DeltaMapper_getPixels (getBlueGreenRed, ResizeMapper.resize2 or resize, and getPixel in one pass, on threads), the same image as the Java. resize's maps come from DeltaMapper.resizeMap, which runs ResizeMapper.resizeX and resizeY on a line of known values |
| native/DeltaMapper.c, .h (5) | ... and the writer's Apply (DeltaMapper_applyQuantize, _applyPreview) and decode check (DeltaMapper_checkMixedDeltas) |
| native/DeltaMapper.c, .h (6) | ... and NativeReader's fit for Huffman files: DeltaMapper_rebuildRowFitChannels (the decoder's threads with the deltas given, nothing decoded, or each channel's deltas Huffman decoded in its own thread first), the same values as getValuesFromRowFitDeltas. In NativeHuffmanReader each channel's fit can be shared among several helper threads, or solved by the channel's own thread with none (DeltaMapper.fitHelpers: 0 to 4, from the cores and the bands, so that the bands' threads don't crowd the cores), with the same result; NativeSimpleReader keeps one, since its decoder, not the fit, sets its pace |
| native/StringMapper.c, .h | StringMapper's unary strings in C for the Huffman and Packet pairs: StringMapper_getStringList (getHistogram, getRankTable, packStrings, compressStrings), _compressStrings, _decompressStrings, _unpackStrings; the bit-pair transforms run a byte at a time through tables made from the Java's rules (once, when the library is loaded): the same bits |
| native/SegmentMapper.c, .h | SegmentMapper's segmentation in C for the Packet pair: SegmentMapper_getSegmentedData3 (segment, merge3 with its compressing on threads, combine3), _packSegments3, and _restore (unpackSegments3 and restore2, decompressing on threads): the same segments, bytes and strings |
| native/CodeMapper.c, .h | CodeMapper's canonical Huffman code in C: CodeMapper_packRegularCode, _unpackRegularCode (the code lengths come from the Java's getRegularHuffmanLength) |
| native/ArithmeticMapper.c, .h | ArithmeticMapper's range coder in C (RangeEncoder_init, _encode, _finish; RangeDecoder_init, _target, _decode) |
| native/NeighbourMapper.c, .h | NeighbourMapper's neighbour Huffman coding in C: NeighbourMapper_code, _decode (versions 1 and 2), NeighbourDecoder (version 3, a pixel at a time), NeighbourMapper_average, _decodeKnown: the same bytes and deltas |
| native/ContextTables.c, .h | ContextTables' Context tables coding in C: ContextTables_code (each pixel's own context, ContextTables_ownContext), ContextTables_decoder, ContextTables_pixel (with DeltaMapper_decodeRowFitChannelsWith) and ContextTables_average, ContextTables_check: the same bytes and deltas; version 1's tables decoded by TablesDecoder_next, which DeltaMapper_decodeTablesRowFitChannels and _decodeTablesAverageChannels call at each pixel, after its model's context alone |
| native/LengthCoding.c, .h | the bit streams, canonical Huffman tables and compact code lengths (NeighbourMapper's BitReader, BitWriter, Table, writeLengthSymbols and readLengthSymbols) that NeighbourMapper.c and ContextTables.c share |
| native/BlockPool.c, .h | the library's memory, kept for reuse: every C file includes BlockPool.h last, which makes its malloc, calloc, realloc and free the pool's; freed blocks of 1 MB or more are kept (up to a quarter of the memory, at most 2 GB) and handed out again, so a program that keeps running doesn't get fresh memory, page by page from the system, for every frame |
| native/DeltaMapper_jni.c | the native methods DeltaMapper.java declares (rowFitPlane, packMixedDeltasNative, decodeRowFitChannelsNative, decodeAverageChannelsNative, getPixelsNative, applyQuantizeNative, applyPreviewNative, checkMixedDeltasNative, rebuildRowFitChannelsNative), NativeWriter declares (stringListNative, packRegularCodeNative, huffmanDecodeNative, rebuildHuffmanChannelsNative) and NativePacketWriter declares (segmentNative, packSegmentsNative, restoreNative, restoreDeltasNative), built with DeltaMapper.c, ArithmeticMapper.c, StringMapper.c, CodeMapper.c, SegmentMapper.c and BlockPool.c into the library DeltaMapper |

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
- **Linux.** Copy the zip's `java` and `native` folders over the
  repository's, run `native/eclipse-linux.sh` (it makes native/.cproject the
  Linux one), then in Eclipse press F5 on both projects and Clean and Build
  NativeEncoder_C (configuration **Linux**). The Makefile finds the JDK by
  itself (JAVA_HOME if it has include/jni.h, the folder above it if that
  has, else the JDK javac belongs to); `make which` in native shows the one
  it used. Copying `native` over replaces native/.settings, so a JAVA_HOME
  set in the project's Environment settings is lost: there's no need for one.
- **Re-importing.** If F5 doesn't bring in new Java files, delete the Java
  project (contents kept) and re-import it with File > Import > General >
  **Existing Projects into Workspace**. Don't re-import NativeEncoder_C
  unless you must, and never with a C/C++ import wizard ("Existing Code as
  Makefile Project", or "Projects from Folder or Archive" when it detects C
  code): they make a new project around the folder with Eclipse's own
  builder in place of the Makefile, and Build then does nothing. Eclipse
  needn't know about new C files: the Makefile builds them.

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
| NativeWriter | asks for an image; File > Save writes `foo` in the java folder (with the C fit if native has the library), coded as the Delta and Entropy menus say, and checked by decoding it back if File > Decode Check is on (it's off unless switched on: the check takes about as long as decoding the file, and a file that doesn't decode right is found by its reader instead; then, with the check on, Save says whether the writer or the reader is at fault). From a command line, every writer takes the file to save to after the image (`java NativeWriter image.jpg out.bin`); without one, Save writes `foo` |
| NativeReader | asks for a file (e.g. that `foo`): Simple 2 or Huffman, LS or Avg |
| NativePacketWriter, NativePacketReader | the same for the Packet pair (Save writes `foo` too, and says "Native methods: C (...)" or Java) |
| RowFitBench | asks for an image; times RowFit's fit in Java and, if the library is built, in C through JNI (as NativeWriter runs it), and writes native/rowfit.dump |
| bench_RowFit (Windows / Linux), bench_RowFit_native (...) | the C half: reads native/rowfit.dump, checks every prediction against the Java's, and times the same way |
| DecoderBench | asks for an image; codes it as Save does, then times the reader's decoding (all three channels at once) in Java and in C through JNI, checking the deltas and values are the same |
| PairBench | asks for an image; codes it as Save does with both codings (LS deltas), in 1 and 4 bands, and times each one's encode (with its decode check) and its decoding (best of 5), then the decoding's parts in 1 band: the context aware decoder and fit, the Huffman decoding, and its fit rebuild |
| ScaleBench | asks for an image; tiles it 2 x 2 and times each coding (context aware and Huffman, LS and Avg deltas) in 1, 2, 4 ... 64 bands, encode and decode, with the file's size (see native/run_scale below) |
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

How the speed grows with cores: `native\run_scale.bat image` (or
`native/run_scale.sh image`) builds the C and runs ScaleBench. It tiles the
image 2 x 2 (mirrored copies; scrubjay.jpg at Save's Pixel Resolution 4 is
then coded 5630 x 4316, enough for 64 bands) and times each coding (mixed
context and Huffman, LS and Avg deltas) in 1, 2, 4 ... 64 bands: encode
(without its decode check), decode, and the file's size. It runs once on all
the logical processors and, on a machine with two a core, again on one a
core (taskset on Linux, start /affinity on Windows), then on one processor
in 1 and 4 bands (the single-core times). The writer and reader make their
threads for the processors Java sees, which each section shows. It first
records the processor, cores, threads, clock and memory, and writes it all
to native/scale_results_<machine>.txt. Optional arguments: the tiling, Pixel
Resolution, Color Resolution and timed runs (default 2 4 3 2). The Java heap
is half the memory, taken and touched at the start (-Xms, AlwaysPreTouch), as
a program that keeps running would have it; a 2 x 2 scrubjay needs about 3 GB
(tile 1 if there's less). Other Java options can be given in JAVA_OPTS (e.g.
-XX:+UseParallelGC; it made no difference). The runs on fewer processors tell
Java how many it has (-XX:ActiveProcessorCount), as it doesn't always see an
affinity limit.

On a rented machine: native/cloud_setup.sh, pasted as the machine's startup
script ("user data" on AWS) when launching it from an Ubuntu image, installs
a JDK, gcc and make, downloads NativeEncoder.zip and scrubjay.jpg from
GitHub and runs run_scale (with a 16 GB heap). The results end up in
/home/ubuntu/NativeEncoder/native, the log in /home/ubuntu/run_scale.log,
and /home/ubuntu/DONE appears when it's finished.

## Test

```
java\run_tests.bat bluejay.jpg     # Windows
java/run_tests.sh bluejay.jpg      # Linux (needs xvfb-run)
```

It writes the image with NativeWriter (test.Drive): context aware in 1, 4 and
8 bands, in 1 band with the Java fit and coder (`-Dnative=false`) and in 4 bands
with Avg deltas; Huffman in 1, 4 and 8 bands and in 4 bands with Avg deltas; and
with NativePacketWriter at its defaults and
with the block map (delta_type=13), decodes them (test.Decode, with the
reader for the file's format), and checks the sizes and the decoded
image's MD5 for the images it knows (bcrow99/TestImages): bluejay.jpg
(1, 4 and 8 bands: 61,174, 62,689 and 62,689 bytes, Avg 67,743; Huffman
69,095, 70,893 and 70,893, Avg 76,031; Packet 76,209 and 68,830; its 295 rows
allow only 4 bands) and scrubjay.jpg (4,075,255, 4,080,169 and 4,086,689
bytes, Avg 4,356,507; Huffman 4,453,703, 4,454,159 and 4,453,700, Avg
4,765,744; Packet 4,855,085 and 4,465,954); for others it prints them.
The Packet files decode to another image, as PacketWriter resizes
differently. Each line ends with how long decoding took (a second time, after a warm-up)
and what the writer used, C or Java (the decoder uses the same). Leave
the writer's windows be: they close themselves.
