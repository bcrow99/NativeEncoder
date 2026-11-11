# NativeEncoder

NativeSimpleWriter and NativeSimpleReader: DeltaEncoder's SimpleWriter2 and SimpleReader2
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
built, NativeSimpleWriter and NativeSimpleReader use them and say so ("Fit and coder: C
(...)", "Decoder and fit: C (...)"); without it, or run with
`-Dnative=false`, they use the Java. The library is looked for first in the
repository's own native folder, and must be as new as the Java (they check a
version number): an older one is reported ("... is older than the Java:
rebuild the C") and the Java used. The C decoder starts on a band once all
its bytes are read (the Java's starts on each channel as its bytes arrive).

NativeHuffmanWriter and NativeHuffmanReader are the Huffman pair: DeltaEncoder's
HuffmanWriter and HuffmanReader (Huffman format 'H' 1, the same files) with
the same native methods where they apply: the writer's fit and Apply, and
the reader's fit (the C decoder's machinery with the deltas given:
DeltaMapper.getValuesFromRowFitDeltas) and last steps. Their Huffman coding
and decoding are C too (StringMapper's unary strings and bit-pair transform,
CodeMapper's canonical code, in native/StringMapper.c and CodeMapper.c);
only the code lengths and their small Deflate'd table are Java.

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
| NativeSimpleReader (C decoder and fit) | 2.9 s | 2.7 s |
| NativeHuffmanReader, fit in Java | 3.3 s | 3.0 s |
| NativeHuffmanReader, fit in C | 2.2 s | 1.8 s |
| NativeHuffmanReader, fit and Huffman decoding in C | 1.9 s | 1.7 s |

Most of what's left is the fit (about 1.5 s); the Huffman decoding is under
0.2 s, and now runs alongside the fit (each channel's thread decodes its own
deltas, then rebuilds it, so the first channel starts while the others are
still decoding). On a machine with more cores, each channel's fit is also
shared among several helper threads (PairBench shows the parts with one
helper and with as many as the machine gets). On 16 cores (Windows,
scrubjay, 1 band) that took NativeHuffmanReader's decoding from 664 to 461 ms,
against NativeSimpleReader's 717; its encode is 391 ms against 942, and its
decode check 106 against 398. The three channels' Huffman coding, one after another, went from 1.38 s
in Java to 0.29 s in C, and their decoding from 0.65 s to 0.29 s.

Save prints its timeline (when each channel's fit and coding ended). With
one band it's the three fits (run at the same time) and then the last
channel's coding, each a serial loop: more bands is the way to go faster.

## Layout: two Eclipse projects in one repository

| Folder | Eclipse project | What it is |
|---|---|---|
| java/src | NativeEncoder (Java) | the native writers and readers and the mappers (the default package); src/test: the regression test's tools, test.Drive and test.Decode (package test) |
| java/bench | | the Java halves of the benchmarks (RowFitBench, CoderBench, DecoderBench, PairBench; the default package: they use DeltaMapper's package-private classes) |
| java/run_tests.sh, .bat | | the regression test |
| java/launch | | shared run configurations (they appear under Run and External Tools) |
| native | NativeEncoder_C (C, CDT; on Linux, after native/eclipse-linux.sh) | the C versions (DeltaMapper.c, .h, ArithmeticMapper.c, .h, StringMapper.c, .h, CodeMapper.c, .h, SegmentMapper.c, .h), their JNI side (DeltaMapper_jni.c), the C halves of the benchmarks (bench_RowFit.c), the Makefile |

| File | What it is |
|---|---|
| java/src/NativeSimpleWriter.java | the writer (SimpleWriter2 1.1) |
| java/src/NativeSimpleReader.java | the reader (SimpleReader2 1.1) |
| java/src/NativeHuffmanWriter.java, NativeHuffmanReader.java | NativeSimpleWriter and NativeSimpleReader with Huffman coding in place of the mixed context coding: the same fit and deltas, then StringMapper's unary strings (its bit-pair transform kept if it saves enough) and CodeMapper's canonical Huffman code over the strings' bytes, per channel and band; their own format ('H' 1). Less compression (on the test photos 9-29% bigger files), faster to decode. In C, as NativeSimpleWriter's and NativeSimpleReader's are: the writer's fit and Apply, the reader's fit (the C decoder's, with the deltas given) and last steps, and the Huffman coding and decoding (all but the code lengths) |
| java/src/NativePacketWriter.java, NativePacketReader.java | DeltaEncoder's PacketWriter and PacketReader (2.2; Packet format 'P'), with the segmentation, the reader's deltas and its last steps in C. The reader's native methods are the writer's (segmentNative, packSegmentsNative, restoreNative, restoreDeltasNative) |
| java/src/DeltaMapper.java | the channels, the deltas of every type, the least-squares fit from the rows above (RowFit, RowWave), the mixed context coding (MixedModels): DeltaEncoder's DeltaMapper, whole, with the native methods' declarations and the Java they stand in for |
| java/src/ArithmeticMapper.java | the arithmetic and range coders (RangeEncoder, RangeDecoder, Arriving): DeltaEncoder's ArithmeticMapper, whole, plus Arriving.awaitAll |
| java/src/ResizeMapper.java, ViewerSupport.java | resizing (resize, resize2); the windows, dialogs and parallel helpers |
| java/src/CodeMapper.java, StringMapper.java, SegmentMapper.java | DeltaEncoder's, whole: the Huffman pair uses CodeMapper's and StringMapper's Huffman coding, the Packet pair all three (the Java when the library isn't there) |
| native/DeltaMapper.c, .h | DeltaMapper's methods in C, under the same names (so far RowFit: RowFit_init, _start, _moveTo, _addColumns, _solveRow, _solvePoints, _predict, _plane) |
| native/DeltaMapper.c, .h (2) | ... and the mixed context coder: DeltaMapper_packMixedDeltas (MixedModels_init, _contexts, _contextsRow, _update, _encode), the same bytes as packMixedDeltas |
| native/DeltaMapper.c, .h (3) | ... and the reader's decoding: DeltaMapper_decodeRowFitChannels (MixedModels_decode, _earlierRows; each channel's decoder and helper threads, as RowWave), the same deltas and values as getValuesFromRowFitChannels |
| native/DeltaMapper.c, .h (4) | ... and the reader's last steps: DeltaMapper_getPixels (getBlueGreenRed, ResizeMapper.resize2 or resize, and getPixel in one pass, on threads), the same image as the Java. resize's maps come from DeltaMapper.resizeMap, which runs ResizeMapper.resizeX and resizeY on a line of known values |
| native/DeltaMapper.c, .h (5) | ... and the writer's Apply (DeltaMapper_applyQuantize, _applyPreview) and decode check (DeltaMapper_checkMixedDeltas) |
| native/DeltaMapper.c, .h (6) | ... and NativeHuffmanReader's fit: DeltaMapper_rebuildRowFitChannels (the decoder's threads with the deltas given, nothing decoded, or each channel's deltas Huffman decoded in its own thread first), the same values as getValuesFromRowFitDeltas. In NativeHuffmanReader each channel's fit can be shared among several helper threads, or solved by the channel's own thread with none (DeltaMapper.fitHelpers: 0 to 4, from the cores and the bands, so that the bands' threads don't crowd the cores), with the same result; NativeSimpleReader keeps one, since its decoder, not the fit, sets its pace |
| native/StringMapper.c, .h | StringMapper's unary strings in C for the Huffman and Packet pairs: StringMapper_getStringList (getHistogram, getRankTable, packStrings, compressStrings), _compressStrings, _decompressStrings, _unpackStrings; the bit-pair transforms run a byte at a time through tables made from the Java's rules (once, when the library is loaded): the same bits |
| native/SegmentMapper.c, .h | SegmentMapper's segmentation in C for the Packet pair: SegmentMapper_getSegmentedData3 (segment, merge3 with its compressing on threads, combine3), _packSegments3, and _restore (unpackSegments3 and restore2, decompressing on threads): the same segments, bytes and strings |
| native/CodeMapper.c, .h | CodeMapper's canonical Huffman code in C: CodeMapper_packRegularCode, _unpackRegularCode (the code lengths come from the Java's getRegularHuffmanLength) |
| native/ArithmeticMapper.c, .h | ArithmeticMapper's range coder in C (RangeEncoder_init, _encode, _finish; RangeDecoder_init, _target, _decode) |
| native/DeltaMapper_jni.c | the native methods DeltaMapper.java declares (rowFitPlane, packMixedDeltasNative, decodeRowFitChannelsNative, getPixelsNative, applyQuantizeNative, applyPreviewNative, checkMixedDeltasNative, rebuildRowFitChannelsNative), NativeHuffmanWriter declares (stringListNative, packRegularCodeNative, huffmanDecodeNative, rebuildHuffmanChannelsNative) and NativePacketWriter declares (segmentNative, packSegmentsNative, restoreNative, restoreDeltasNative), built with DeltaMapper.c, ArithmeticMapper.c, StringMapper.c, CodeMapper.c and SegmentMapper.c into the library DeltaMapper |

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
   so build it on the machine that runs it. Close NativeSimpleWriter before
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
| NativeSimpleWriter | asks for an image; File > Save writes `foo` in the java folder (with the C fit if native has the library). From a command line, every writer takes the file to save to after the image (`java NativeSimpleWriter image.jpg out.bin`); without one, Save writes `foo` |
| NativeSimpleReader | asks for a file (e.g. that `foo`) |
| NativeHuffmanWriter, NativeHuffmanReader | the same for the Huffman pair (NativeHuffmanWriter's Save also writes `foo`; each reader says if a file is the other's format) |
| NativePacketWriter, NativePacketReader | the same for the Packet pair (Save writes `foo` too, and says "Native methods: C (...)" or Java) |
| RowFitBench | asks for an image; times RowFit's fit in Java and, if the library is built, in C through JNI (as NativeSimpleWriter runs it), and writes native/rowfit.dump |
| bench_RowFit (Windows / Linux), bench_RowFit_native (...) | the C half: reads native/rowfit.dump, checks every prediction against the Java's, and times the same way |
| DecoderBench | asks for an image; codes it as Save does, then times the reader's decoding (all three channels at once) in Java and in C through JNI, checking the deltas and values are the same |
| PairBench | asks for an image; codes it as Save does with both pairs, in 1 and 4 bands, and times each writer's encode (with its decode check) and each reader's decoding (best of 5), then the decoding's parts in 1 band: NativeSimpleReader's decoder and fit, NativeHuffmanReader's Huffman decoding, and its fit rebuild |
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

It writes the image in 1 and 4 bands with NativeSimpleWriter (test.Drive), in
1 band with the Java fit and coder (`-Dnative=false`), in 1 and 4 bands
with NativeHuffmanWriter, and with NativePacketWriter at its defaults and
with the block map (delta_type=13), decodes them (test.Decode, with the
reader for the file's format), and checks the sizes and the decoded
image's MD5 for the images it knows (bcrow99/TestImages): bluejay.jpg
(61,174 and 62,689 bytes; Huffman 69,095 and 70,893; Packet 76,209 and
68,830) and scrubjay.jpg (4,075,255 and 4,080,169 bytes; Huffman 4,453,703
and 4,454,159; Packet 4,855,085 and 4,465,954); for others it prints them.
The Packet files decode to another image, as PacketWriter resizes
differently. Each line ends with how long decoding took (a second time, after a warm-up)
and what the writer used, C or Java (the decoder uses the same). Leave
the writer's windows be: they close themselves.
