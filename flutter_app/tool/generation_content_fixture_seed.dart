// Public synthetic Go crypto vectors only. Never production credentials.
const generationContentProbeCases = <String, Map<String, String>>{
  "protected-native": {
    "name": "ascii",
    "password": "synthetic-password",
    "hash": "\$2a\$10\$HNSwRI8mT.MBgKAwSaLdYOVmni29Znb5YwGVeCddj5GHysfegdZhC",
    "body":
        "ENC:v1:AQIDBAUGBwgJCgsMDQ4PEA==:HyAhIiMkJSYnKCkq:oiV5abDwe7zAxnEVayn8+WEJE/tbNqE3XSyZT9EmQRG22A==",
    "plain": "﻿# exact\r\nline\r\n",
    "sourceSha256":
        "28953ca8e0192de745f6a6de822c5ba298b7f720bd5428b341f0545e55801134",
  },
  "protected-native-unicode": {
    "name": "unicode",
    "password": "中文😀 é",
    "hash": "\$2a\$10\$qXKLk9V22SP5bCIbqvqH4uFQvWlPEuHUnPYAtlx64tM22u4qguCW.",
    "body":
        "ENC:v1:AQIDBAUGBwgJCgsMDQ4PEA==:HyAhIiMkJSYnKCkq:MwBu99blOiawJ2kEc2GddQba8M2AV8haF6HCXT6x6Iv7zWw7ywlu2w==",
    "plain": "﻿原文😀\r\n<未知>\n",
    "sourceSha256":
        "05341e078fa14276f7f7f37330bdf4304685612f181c7aeb71543099b56d8917",
  },
  "protected-plain-native": {
    "name": "ascii",
    "password": "synthetic-password",
    "hash": "\$2a\$10\$HNSwRI8mT.MBgKAwSaLdYOVmni29Znb5YwGVeCddj5GHysfegdZhC",
    "body":
        "ENC:v1:AQIDBAUGBwgJCgsMDQ4PEA==:HyAhIiMkJSYnKCkq:oiV5abDwe7zAxnEVayn8+WEJE/tbNqE3XSyZT9EmQRG22A==",
    "plain": "﻿# exact\r\nline\r\n",
    "sourceSha256":
        "529f31b7bd6fbd13664c8af1abae50b0c256ca929f92c9b2410983cce143386c",
  },
};
