package com.bookstark.bookstark_flutter;

/** Canonical RFC 4648 Base64 without an API-26 java.util.Base64 dependency. */
final class LegacyBase64 {
    private LegacyBase64() {}
    private static final char[] ALPHABET =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".toCharArray();

    static String encode(byte[] bytes) {
        char[] output = new char[((bytes.length + 2) / 3) * 4];
        int at = 0;
        for (int i = 0; i < bytes.length; i += 3) {
            int first = bytes[i] & 255;
            int second = i + 1 < bytes.length ? bytes[i + 1] & 255 : 0;
            int third = i + 2 < bytes.length ? bytes[i + 2] & 255 : 0;
            output[at++] = ALPHABET[first >>> 2];
            output[at++] = ALPHABET[((first & 3) << 4) | (second >>> 4)];
            output[at++] = i + 1 < bytes.length ? ALPHABET[((second & 15) << 2) | (third >>> 6)] : '=';
            output[at++] = i + 2 < bytes.length ? ALPHABET[third & 63] : '=';
        }
        return new String(output);
    }

    static byte[] decode(String text) {
        int length = text.length();
        if ((length & 3) != 0) throw invalid();
        int padding = length == 0 ? 0 : text.charAt(length - 1) == '=' ?
            (text.charAt(length - 2) == '=' ? 2 : 1) : 0;
        byte[] output = new byte[(length / 4) * 3 - padding];
        int at = 0;
        for (int i = 0; i < length; i += 4) {
            int a = value(text.charAt(i)), b = value(text.charAt(i + 1));
            char cChar = text.charAt(i + 2), dChar = text.charAt(i + 3);
            boolean last = i + 4 == length;
            if ((cChar == '=' || dChar == '=') && !last) throw invalid();
            if (cChar == '=' && (dChar != '=' || (b & 15) != 0)) throw invalid();
            int c = cChar == '=' ? 0 : value(cChar);
            if (dChar == '=' && cChar != '=' && (c & 3) != 0) throw invalid();
            int d = dChar == '=' ? 0 : value(dChar);
            output[at++] = (byte) ((a << 2) | (b >>> 4));
            if (cChar != '=') output[at++] = (byte) ((b << 4) | (c >>> 2));
            if (dChar != '=') output[at++] = (byte) ((c << 6) | d);
        }
        return output;
    }

    private static int value(char c) {
        if (c >= 'A' && c <= 'Z') return c - 'A';
        if (c >= 'a' && c <= 'z') return c - 'a' + 26;
        if (c >= '0' && c <= '9') return c - '0' + 52;
        if (c == '+') return 62;
        if (c == '/') return 63;
        throw invalid();
    }
    private static IllegalArgumentException invalid() {
        return new IllegalArgumentException("Invalid canonical Base64");
    }
}
