import java.io.FileInputStream;
import java.io.FileOutputStream;
import org.objectweb.asm.ClassReader;
import org.objectweb.asm.ClassVisitor;
import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.MethodVisitor;
import org.objectweb.asm.Opcodes;

/** Injects one fail-safe bootstrap call at the end of ClusterService's main constructor. */
public final class InjectStandaloneBootstrap {
    private static final String BOOTSTRAP =
        "com/luka/carplay/routeguidance/StandaloneMirrorBootstrap";

    public static void main(String[] args) throws Exception {
        if (args.length != 2) throw new IllegalArgumentException("input output");
        FileInputStream in = new FileInputStream(args[0]);
        byte[] source;
        try {
            source = new byte[in.available()];
            int offset = 0;
            while (offset < source.length) {
                int count = in.read(source, offset, source.length - offset);
                if (count < 0) throw new IllegalStateException("short read");
                offset += count;
            }
        } finally {
            in.close();
        }

        ClassReader reader = new ClassReader(source);
        ClassWriter writer = new ClassWriter(reader, ClassWriter.COMPUTE_MAXS);
        final int[] injected = new int[1];
        ClassVisitor visitor = new ClassVisitor(Opcodes.ASM7, writer) {
            public MethodVisitor visitMethod(
                int access, String name, String descriptor, String signature,
                String[] exceptions
            ) {
                MethodVisitor base = super.visitMethod(
                    access, name, descriptor, signature, exceptions);
                if (!"<init>".equals(name)
                    || descriptor.indexOf("IViewSizeManager") < 0) return base;
                return new MethodVisitor(Opcodes.ASM7, base) {
                    public void visitInsn(int opcode) {
                        if (opcode == Opcodes.RETURN) {
                            super.visitVarInsn(Opcodes.ALOAD, 0);
                            super.visitMethodInsn(
                                Opcodes.INVOKESTATIC,
                                BOOTSTRAP,
                                "attach",
                                "(Ljava/lang/Object;)V",
                                false);
                            injected[0]++;
                        }
                        super.visitInsn(opcode);
                    }
                };
            }
        };
        reader.accept(visitor, 0);
        if (injected[0] != 1) {
            throw new IllegalStateException("expected one constructor return, got " + injected[0]);
        }

        FileOutputStream out = new FileOutputStream(args[1]);
        try {
            out.write(writer.toByteArray());
        } finally {
            out.close();
        }
        System.out.println("injected bootstrap calls=" + injected[0]);
    }
}
