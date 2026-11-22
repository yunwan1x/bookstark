package com.bookstark.bookstark_flutter;

import org.mindrot.jbcrypt.BCrypt;
import javax.crypto.Cipher;
import javax.crypto.Mac;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.ByteBuffer;
import java.nio.CharBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.regex.Pattern;

/** Pure worker-thread crypto; no Context, files, preferences, logging or SQL. */
public final class LegacyContentCrypto {
    private LegacyContentCrypto() {}
    public static final int MAX_PLAINTEXT_BYTES = 20 * 1024 * 1024;
    public static final int MAX_WIRE_BYTES = 28 * 1024 * 1024;
    private static final int MAX_ENVELOPE_CHARACTERS = MAX_WIRE_BYTES;
    private static final Pattern HASH = Pattern.compile(
        "^\\$2[aby]\\$(0[4-9]|1[0-4])\\$[./A-Za-z0-9]{53}$");
    private static final SecureRandom RANDOM = new SecureRandom();

    public enum Reason { UNSUPPORTED, WRONG_PASSWORD, INVALID_CONTENT, CANCELLED }

    public static final class Failure extends Exception {
        public final Reason reason;
        private Failure(Reason reason) {
            super(reason.name()); // No body, password, hash or provider details.
            this.reason = reason;
        }
    }

    public static final class ProtectedBody {
        public final String passwordHash;
        public final String encryptedBody;
        private ProtectedBody(String hash, String body) {
            passwordHash = hash;
            encryptedBody = body;
        }
    }

    public static boolean verifyPassword(String password, String hash) throws Failure {
        byte[] passwordBytes = passwordBytes(password);
        Arrays.fill(passwordBytes, (byte) 0);
        if (hash == null || !HASH.matcher(hash).matches()) throw fail(Reason.UNSUPPORTED);
        checkCancelled();
        try {
            // Go's modern 2a/2b/2y variants share byte semantics. This adapter
            // is covered by Go interoperability vectors, including non-ASCII.
            String normalized = "$2a$" + hash.substring(4);
            boolean matches = BCrypt.checkpw(password, normalized);
            checkCancelled();
            return matches;
        } catch (IllegalArgumentException error) {
            throw fail(Reason.UNSUPPORTED);
        }
    }

    /** Always verifies the original bcrypt hash before exposing plaintext. */
    public static String unlock(String password, String hash, String body) throws Failure {
        if (!verifyPassword(password, hash)) throw fail(Reason.WRONG_PASSWORD);
        if (body == null) throw fail(Reason.INVALID_CONTENT);
        if (!body.startsWith("ENC:")) {
            byte[] plain = utf8(body);
            try {
                if (plain.length > MAX_PLAINTEXT_BYTES) throw fail(Reason.INVALID_CONTENT);
                return body; // Legacy password-only records retain exact bytes.
            } finally {
                Arrays.fill(plain, (byte) 0);
            }
        }
        return decrypt(password, body);
    }

    /** Saves encrypted bytes using the same verified password, with fresh salt. */
    public static String encryptExisting(String password, String hash, String plaintext)
            throws Failure {
        if (!verifyPassword(password, hash)) throw fail(Reason.WRONG_PASSWORD);
        return encrypt(password, plaintext);
    }

    /** Ordinary stores have no bcrypt column: authenticate exact ENC:v1 GCM. */
    public static String unlockEnvelope(String password, String envelope) throws Failure {
        if (envelope == null || !envelope.startsWith("ENC:v1:")) throw fail(Reason.UNSUPPORTED);
        return decrypt(password, envelope, true);
    }

    public static String encryptEnvelope(String password, String plaintext) throws Failure {
        return encrypt(password, plaintext);
    }

    public static ProtectedBody protectNew(String password, String plaintext) throws Failure {
        byte[] bytes = passwordBytes(password);
        try {
            // Match current Go GenerateFromPassword's byte-length restriction.
            if (bytes.length > 72) throw fail(Reason.UNSUPPORTED);
        } finally {
            Arrays.fill(bytes, (byte) 0);
        }
        checkCancelled();
        String hash = BCrypt.hashpw(password, BCrypt.gensalt(10, RANDOM));
        checkCancelled();
        return new ProtectedBody(hash, encrypt(password, plaintext));
    }

    private static String encrypt(String password, String plaintext) throws Failure {
        byte[] plain = utf8(plaintext);
        byte[] key = null;
        byte[] salt = new byte[16];
        byte[] nonce = new byte[12];
        try {
            if (plain.length > MAX_PLAINTEXT_BYTES) throw fail(Reason.INVALID_CONTENT);
            RANDOM.nextBytes(salt);
            RANDOM.nextBytes(nonce);
            key = derive(password, salt);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(key, "AES"),
                new GCMParameterSpec(128, nonce));
            byte[] encrypted = cipher.doFinal(plain);
            checkCancelled();
            return "ENC:v1:" + LegacyBase64.encode(salt) + ":" +
                LegacyBase64.encode(nonce) + ":" + LegacyBase64.encode(encrypted);
        } catch (GeneralSecurityException error) {
            throw fail(Reason.INVALID_CONTENT);
        } finally {
            Arrays.fill(plain, (byte) 0);
            if (key != null) Arrays.fill(key, (byte) 0);
        }
    }

    private static String decrypt(String password, String envelope) throws Failure {
        return decrypt(password, envelope, false);
    }

    private static String decrypt(String password, String envelope, boolean envelopeAuthentication) throws Failure {
        if (envelope.length() > MAX_ENVELOPE_CHARACTERS) throw fail(Reason.INVALID_CONTENT);
        String[] parts = envelope.split(":", -1);
        if (parts.length != 5 || !parts[0].equals("ENC") || !parts[1].equals("v1")) {
            throw fail(Reason.UNSUPPORTED);
        }
        byte[] key = null;
        byte[] plaintext = null;
        try {
            byte[] salt = canonicalBase64(parts[2]);
            byte[] nonce = canonicalBase64(parts[3]);
            byte[] ciphertext = canonicalBase64(parts[4]);
            if (salt.length != 16 || nonce.length != 12 ||
                ciphertext.length < 16 || ciphertext.length > MAX_PLAINTEXT_BYTES + 16) {
                throw fail(Reason.INVALID_CONTENT);
            }
            key = derive(password, salt);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, new SecretKeySpec(key, "AES"),
                new GCMParameterSpec(128, nonce));
            plaintext = cipher.doFinal(ciphertext);
            checkCancelled();
            return StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(plaintext)).toString();
        } catch (javax.crypto.AEADBadTagException error) {
            throw fail(envelopeAuthentication ? Reason.WRONG_PASSWORD : Reason.INVALID_CONTENT);
        } catch (GeneralSecurityException | CharacterCodingException error) {
            throw fail(Reason.INVALID_CONTENT);
        } finally {
            if (key != null) Arrays.fill(key, (byte) 0);
            if (plaintext != null) Arrays.fill(plaintext, (byte) 0);
        }
    }

    private static byte[] canonicalBase64(String encoded) throws Failure {
        try {
            byte[] bytes = LegacyBase64.decode(encoded);
            if (!LegacyBase64.encode(bytes).equals(encoded)) {
                throw fail(Reason.INVALID_CONTENT);
            }
            return bytes;
        } catch (IllegalArgumentException error) {
            throw fail(Reason.INVALID_CONTENT);
        }
    }

    /** PBKDF2-HMAC-SHA256, 100000 iterations, one 32-byte block.
     * Uses explicit UTF-8 password bytes to avoid PBEKeySpec provider differences. */
    private static byte[] derive(String password, byte[] salt) throws Failure {
        byte[] passwordBytes = passwordBytes(password);
        byte[] u = null;
        byte[] result = null;
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(passwordBytes, "HmacSHA256"));
            byte[] initial = Arrays.copyOf(salt, 20);
            initial[19] = 1;
            u = mac.doFinal(initial);
            result = u.clone();
            for (int iteration = 1; iteration < 100000; iteration++) {
                if ((iteration & 1023) == 0) checkCancelled();
                byte[] next = mac.doFinal(u);
                Arrays.fill(u, (byte) 0);
                u = next;
                for (int i = 0; i < result.length; i++) result[i] ^= u[i];
            }
            checkCancelled();
            byte[] key = result;
            result = null;
            return key;
        } catch (GeneralSecurityException error) {
            throw fail(Reason.INVALID_CONTENT);
        } finally {
            Arrays.fill(passwordBytes, (byte) 0);
            if (u != null) Arrays.fill(u, (byte) 0);
            if (result != null) Arrays.fill(result, (byte) 0);
        }
    }

    /** Byte transport preserves leading BOMs that Flutter's String codec drops. */
    public static byte[] encodeWireBody(String body) throws Failure {
        byte[] bytes = utf8(body);
        if (bytes.length > MAX_ENVELOPE_CHARACTERS) {
            Arrays.fill(bytes, (byte) 0);
            throw fail(Reason.INVALID_CONTENT);
        }
        return bytes;
    }

    public static String decodeWireBody(byte[] bytes) throws Failure {
        if (bytes == null || bytes.length > MAX_ENVELOPE_CHARACTERS) {
            throw fail(Reason.INVALID_CONTENT);
        }
        try {
            return StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes)).toString();
        } catch (CharacterCodingException error) {
            throw fail(Reason.INVALID_CONTENT);
        }
    }

    private static byte[] passwordBytes(String password) throws Failure {
        byte[] value = utf8(password);
        if (value.length == 0 || value.length > 4096) {
            Arrays.fill(value, (byte) 0);
            throw fail(Reason.UNSUPPORTED);
        }
        return value;
    }

    private static byte[] utf8(String value) throws Failure {
        if (value == null) throw fail(Reason.INVALID_CONTENT);
        try {
            ByteBuffer buffer = StandardCharsets.UTF_8.newEncoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .encode(CharBuffer.wrap(value));
            byte[] bytes = new byte[buffer.remaining()];
            buffer.get(bytes);
            return bytes;
        } catch (CharacterCodingException error) {
            throw fail(Reason.INVALID_CONTENT);
        }
    }

    private static void checkCancelled() throws Failure {
        if (Thread.currentThread().isInterrupted()) throw fail(Reason.CANCELLED);
    }
    private static Failure fail(Reason reason) { return new Failure(reason); }
}
