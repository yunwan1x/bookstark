package com.bookstark.bookstark_flutter;
import java.util.*;
public final class LegacyBase64HostTest {
  public static void main(String[] args) {
    Random random = new Random(44);
    int assertions = 0;
    for (int length = 0; length < 4096; length++) {
      byte[] value = new byte[length];
      random.nextBytes(value);
      String reference = Base64.getEncoder().encodeToString(value);
      if (!reference.equals(LegacyBase64.encode(value)) ||
          !Arrays.equals(value, LegacyBase64.decode(reference))) {
        throw new AssertionError("Base64 reference mismatch");
      }
      assertions += 2;
    }
    for (String malformed : new String[]{
      "A", "AA", "AAA", "====", "A===", "AA=A", "AB==", "AAB=",
      "AAAA\n", "AAAA====", "AAA_", "AAA-", "AAA ", "AAA\u0100"
    }) {
      try {
        LegacyBase64.decode(malformed);
        throw new AssertionError("Malformed Base64 accepted");
      } catch (IllegalArgumentException expected) { assertions++; }
    }
    System.out.println("{\"passed\":true,\"reference\":\"JDK Base64\",\"assertions\":" +
      assertions + ",\"actualAndroidExecution\":false}");
  }
}
