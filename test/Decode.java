package test;

import java.awt.image.BufferedImage;
import java.io.BufferedInputStream;
import java.io.DataInputStream;
import java.io.FileInputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.security.MessageDigest;

/**
 * Regression harness for the reader: decodes files as NativeReader does,
 * without its window, and prints each one's MD5 (of the pixels' blue, green
 * and red bytes, row by row).
 *
 * <pre>
 * java -cp &lt;classes&gt; test.Decode &lt;file&gt;...
 * </pre>
 */
public class Decode
{
	/** Not instantiated: everything is static. */
	private Decode() { }

	/**
	 * Decodes each file and prints "file md5".
	 *
	 * @param args the files
	 * @throws Exception when a file can't be read or decoded
	 */
	public static void main(String[] args) throws Exception
	{
		Class<?> c = Class.forName("NativeReader");
		// The constructor opens a window, so the reader is made without it
		// and its header and decoding are called directly.
		Field uf = Class.forName("sun.misc.Unsafe").getDeclaredField("theUnsafe");
		uf.setAccessible(true);
		Object unsafe = uf.get(null);
		Method allocate = unsafe.getClass().getMethod("allocateInstance", Class.class);
		Method header = c.getDeclaredMethod("readHeader", DataInputStream.class, String.class);
		Method decode = c.getDeclaredMethod("decodeFile", String.class);
		header.setAccessible(true);
		decode.setAccessible(true);
		Field min = c.getDeclaredField("min");
		min.setAccessible(true);
		for(String file : args)
		{
			Object reader = allocate.invoke(unsafe, c);
			min.set(reader, new int[3]);
			try(DataInputStream in = new DataInputStream(new BufferedInputStream(new FileInputStream(file)))) { header.invoke(reader, in, file); }
			BufferedImage image = (BufferedImage) decode.invoke(reader, file);
			int xdim = image.getWidth(), ydim = image.getHeight();
			int[] pixel = image.getRGB(0, 0, xdim, ydim, null, 0, xdim);
			MessageDigest md = MessageDigest.getInstance("MD5");
			for(int p : pixel) { md.update((byte) p); md.update((byte) (p >> 8)); md.update((byte) (p >> 16)); }
			StringBuilder hex = new StringBuilder();
			for(byte b : md.digest()) hex.append(String.format("%02x", b));
			System.out.println(file + " " + hex);
		}
	}
}
