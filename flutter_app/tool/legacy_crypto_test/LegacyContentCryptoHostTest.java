import com.bookstark.bookstark_flutter.LegacyContentCrypto;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

public final class LegacyContentCryptoHostTest {
    static int assertions = 0;
    static void check(boolean condition) {
        assertions++;
        if (!condition) throw new AssertionError("Synthetic crypto assertion " + assertions);
    }
    interface Operation { void run() throws Exception; }
    static void fails(Operation operation, LegacyContentCrypto.Reason reason) throws Exception {
        try { operation.run(); throw new AssertionError("Expected rejection"); }
        catch (LegacyContentCrypto.Failure failure) {
            check(failure.reason == reason);
            check(failure.getMessage().equals(reason.name()));
        }
    }
    static String decode(String value) {
        return new String(Base64.getDecoder().decode(value), StandardCharsets.UTF_8);
    }
    static String encode(String value) {
        return Base64.getEncoder().encodeToString(value.getBytes(StandardCharsets.UTF_8));
    }
    public static void main(String[] args) throws Exception {
        List<String> output = new ArrayList<>();
        int vectors = 0;
        for (String line : Files.readAllLines(Path.of(args[0]), StandardCharsets.UTF_8)) {
            String[] fields = line.split("\t", -1);
            String name = fields[0], pw = decode(fields[1]), hash = decode(fields[2]);
            String body = decode(fields[3]), plain = decode(fields[4]);
            check(LegacyContentCrypto.verifyPassword(pw, hash));
            check(!LegacyContentCrypto.verifyPassword("wrong-" + pw, hash));
            check(LegacyContentCrypto.unlock(pw, hash, body).equals(plain));
            check(LegacyContentCrypto.unlockEnvelope(pw, body).equals(plain));
            fails(() -> LegacyContentCrypto.unlockEnvelope("wrong-" + pw, body),
                LegacyContentCrypto.Reason.WRONG_PASSWORD);
            String envelopeOnly = LegacyContentCrypto.encryptEnvelope(pw, plain);
            check(!envelopeOnly.equals(body));
            check(LegacyContentCrypto.unlockEnvelope(pw, envelopeOnly).equals(plain));
            output.add(name + "-envelope\t" + encode(pw) + "\t" + encode(hash) + "\t" +
                encode(envelopeOnly) + "\t" + encode(plain));

            check(Arrays.equals(plain.getBytes(StandardCharsets.UTF_8),
                LegacyContentCrypto.encodeWireBody(plain)));
            check(LegacyContentCrypto.decodeWireBody(
                plain.getBytes(StandardCharsets.UTF_8)).equals(plain));
            check(LegacyContentCrypto.unlock(pw, hash, plain).equals(plain));
            fails(() -> LegacyContentCrypto.unlock("wrong-" + pw, hash, body),
                LegacyContentCrypto.Reason.WRONG_PASSWORD);
            String[] envelope = body.split(":");
            byte[] ciphertext = Base64.getDecoder().decode(envelope[4]);
            ciphertext[ciphertext.length - 1] ^= 1;
            String altered = String.join(":", Arrays.copyOf(envelope, 4)) + ":" +
                Base64.getEncoder().encodeToString(ciphertext);
            fails(() -> LegacyContentCrypto.unlock(pw, hash, altered),
                LegacyContentCrypto.Reason.INVALID_CONTENT);
            String encrypted = LegacyContentCrypto.encryptExisting(pw, hash, plain);
            check(!encrypted.equals(body));
            check(LegacyContentCrypto.unlock(pw, hash, encrypted).equals(plain));
            output.add(name + "-existing\t" + encode(pw) + "\t" + encode(hash) + "\t" +
                encode(encrypted) + "\t" + encode(plain));
            if (pw.getBytes(StandardCharsets.UTF_8).length <= 72) {
                LegacyContentCrypto.ProtectedBody fresh =
                    LegacyContentCrypto.protectNew(pw, plain);
                check(fresh.passwordHash.startsWith("$2a$10$"));
                check(LegacyContentCrypto.unlock(pw, fresh.passwordHash, fresh.encryptedBody).equals(plain));
                output.add(name + "-new\t" + encode(pw) + "\t" + encode(fresh.passwordHash) + "\t" +
                    encode(fresh.encryptedBody) + "\t" + encode(plain));
            } else {
                fails(() -> LegacyContentCrypto.protectNew(pw, plain),
                    LegacyContentCrypto.Reason.UNSUPPORTED);
            }
            fails(() -> LegacyContentCrypto.unlock(pw, hash, "ENC:v9:unsupported"),
                LegacyContentCrypto.Reason.UNSUPPORTED);
            fails(() -> LegacyContentCrypto.unlockEnvelope(pw, "\uFEFF" + body),
                LegacyContentCrypto.Reason.UNSUPPORTED);
            vectors++;
        }
        String[] first = Files.readAllLines(Path.of(args[0])).get(0).split("\t", -1);
        String pw = decode(first[1]), hash = decode(first[2]), body = decode(first[3]);
        fails(() -> LegacyContentCrypto.verifyPassword("", hash), LegacyContentCrypto.Reason.UNSUPPORTED);
        fails(() -> LegacyContentCrypto.verifyPassword(pw, "$2a$31$" + hash.substring(7)),
            LegacyContentCrypto.Reason.UNSUPPORTED);
        fails(() -> LegacyContentCrypto.verifyPassword(pw, "not-a-hash"),
            LegacyContentCrypto.Reason.UNSUPPORTED);
        fails(() -> LegacyContentCrypto.protectNew("valid", "\uD800"),
            LegacyContentCrypto.Reason.INVALID_CONTENT);
        fails(() -> LegacyContentCrypto.unlock(pw, hash, body + "\n"),
            LegacyContentCrypto.Reason.INVALID_CONTENT);
        fails(() -> LegacyContentCrypto.decodeWireBody(new byte[]{(byte)255}),
            LegacyContentCrypto.Reason.INVALID_CONTENT);
        check(LegacyContentCrypto.decodeWireBody(
            new byte[]{(byte)239,(byte)187,(byte)191,(byte)239,(byte)187,(byte)191})
            .equals("\uFEFF\uFEFF"));
        String prefix = "\\uFEFF\\uFEFF# exact\\r\\n中🙂";
        String largePlain = prefix + "x".repeat(LegacyContentCrypto.MAX_PLAINTEXT_BYTES -
            prefix.getBytes(StandardCharsets.UTF_8).length);
        String largeCipher = LegacyContentCrypto.encryptExisting(pw, hash, largePlain);
        check(largeCipher.length() > 20 * 1024 * 1024 &&
            largeCipher.length() <= LegacyContentCrypto.MAX_WIRE_BYTES);
        check(LegacyContentCrypto.unlock(pw, hash, largeCipher).equals(largePlain));
        fails(() -> LegacyContentCrypto.encryptExisting(pw, hash, largePlain + "x"),
            LegacyContentCrypto.Reason.INVALID_CONTENT);
        Thread.currentThread().interrupt();
        fails(() -> LegacyContentCrypto.verifyPassword(pw, hash),
            LegacyContentCrypto.Reason.CANCELLED);
        Thread.interrupted();
        Files.write(Path.of(args[1]), output, StandardCharsets.UTF_8);
        System.out.println("{\"passed\":true,\"goToJavaVectors\":" + vectors +
            ",\"javaOutputVectors\":" + output.size() + ",\"assertions\":" + assertions +
            ",\"actualAndroidExecution\":false,\"syntheticDataOnly\":true}");
    }
}
