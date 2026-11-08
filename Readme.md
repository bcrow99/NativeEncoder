# NativeEncoder

NativeWriter and NativeReader (DeltaEncoder's Simple 2 format 2) with their
slowest parts in C, through JNI, with a Java fallback: about twice as fast
on Save and on decode, with the same files and images as the Java.

Download NativeEncoder.zip and unzip it. It holds two Eclipse projects
(java: the Java, native: the C, built by its Makefile), the test and
benchmark scripts, and a README with the setup for Windows (MSYS2 ucrt64)
and Linux.