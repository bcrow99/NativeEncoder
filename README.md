# NativeEncoder

NativeWriter and NativeReader: DeltaEncoder's SimpleWriter2 and SimpleReader2
(Simple 2 format 2), renamed, with the mapper classes they use, to be sped up
by replacing pure Java methods with native methods in C while the GUI and the
threading stay in Java.

They write and read exactly the same files as SimpleWriter2 and SimpleReader2,
so files go back and forth between the two repositories, and any native method
must leave the files and the decoded images byte for byte the same.

| File | What it is |
|---|---|
| NativeWriter.java | the writer (SimpleWriter2 1.1) |
| NativeReader.java | the reader (SimpleReader2 1.1) |
| DeltaMapper.java | the channels, the least-squares fit from the rows above (RowFit, RowWave), the mixed context coding (MixedModels) |
| ArithmeticMapper.java | the range coder (RangeEncoder, RangeDecoder, Arriving) |
| ResizeMapper.java | resizing (resize2) |
| ViewerSupport.java | the windows, dialogs and parallel helpers |
| CodeMapper.java, StringMapper.java, SegmentMapper.java | used by parts of the mappers above |
| test/ | the regression test |

## Build and run

Java 8 or later:

```
javac -d bin *.java
java -cp bin NativeWriter image.png     # File > Save writes "foo"
java -cp bin NativeReader foo
```

## Test

```
test/run_tests.sh bluejay.jpg      # Linux (needs xvfb-run)
test\run_tests.bat bluejay.jpg     # Windows
```

It writes the image in 1 and 4 bands with NativeWriter (test.Drive), decodes
both with NativeReader (test.Decode), and for bluejay.jpg (bcrow99/TestImages)
checks the sizes (61,174 and 62,689 bytes) and the decoded image's MD5.
