# 15 书签创建恢复 v1（外部源准备）
原型 prototype/bookmark-creation-recovery-v1.png已先于UI落盘；既有15-bookmarks/15-bookmark-editor原型保留。新界面只解决创建未知回执与冷目录，已有ID编辑保持现有布局/接口。

## 固定身份与不可重放边界
独立bookstark.bookmark-create.v1记录与bookstark.bookmark-create-slot.v1索引；scope=SHA256(server/member/namespace)，随机128bit attempt key，不借topic身份。一个账号一个新建slot，不按URL分slot，因此unknown改URL不能新POST。正文元数据冻结title/URL/description/favicon/public/精确labels数组。pending→unknown严格CAS、同key lease、flush+readback后唯一授权；auth/profile/CSRF已完成。HTTP实际发送前再次ownerGuard。未知无自动重发；missing expected拒绝晚ACK复活；结束仅删除恢复记录，不表示服务器未执行。

## 实际服务协议
POST /api/bookmarks/creation-check 仅同owner只读，URL在CSRF body，不进query；存在返回完整真实资源供既有“编辑已有”显式选择。相同URL不当创建证明。
POST /api/bookmarks/create-owned 严格仅新建、从认证member确定owner；同事务INSERT+精确label关系+兼容label缓存+完整真实回执，重复URL409/零改动，绝不legacy upsert。一次成功已含全部标签；knownID仅storage重试，不再POST/PUT整资源。
GET /api/bookmarks/:id/creation-review 仅owner正ID、有界完整metadata+labels同Tx snapshot。cold输入实际ID，展示完整字段、URL与全部说明/标签，fresh完整fingerprint一致后显式接纳；只关联ID，不宣称证明POST来源。并发rename/flags/labels变化不得覆盖或falseSaved。
旧POST/PUT及existing-ID两阶段标签恢复仍兼容，本批Root新建走专用协议，不用旧sameURL查重绕过已unknown slot。

## 字节、事务与数据
title500/url2048/description2000/favicon4096 UTF8字节，URL HTTP(S)/无账号/无ASCII空白控制/合法端口。labels最多100项、每项4096字节、合计64KiB；原名不trim/NFC/逗号拆分（允许既有空名/空白/逗号，去重保首项）。请求512KiB/回执1MiB；旧超限/损坏数据明确受限，不假空/不可自动写。JSON strictUTF8、重复key/未知key/非法surrogate拒绝。SQLite首次写语句计算order并INSERT；任何标签/回执错误回滚整事务，created/pin/nav/order归真实服务，已存在metadata绝不改。
SecureStorage普通书签输入按既有承诺保存，不持久Root cookie/token/password；键名只opaque hash。Native keys-only allowlist/inventory识别两独立前缀，不读取value作phase证明。当前账号冷入口直接受限读取唯一slot，再读最多一个768KiB记录；不进行全账号/凭证readAll。损坏slot/record明确错误保留、不假空、不分配替代slot。只有显式End完成record delete+flush/readback后才clear slot；旧key不可复用。

## UI与验收
原型三态+当前账号目录；unknown冻结输入，修改URL保存进入旧恢复；explicit End确认不会删除服务器资源。大字单滚动列表；controller replacement/dialog capture/current guards；storageUnconfirmed先reload，known ACK仅存储。
Go真实SQLite并发唯一/精确label回执/trigger回滚/owner/只读预算；Dart真实prepared CSRF held、claim held、冷恢复不POST、改变URL仍同slot、clear晚writer0复活、fullfp conflict；实际NAS redroid ARM64 Native后另验。不把原型、fake callback或同URLGET当回执/Native完成。

远端Go真实删除是snapshot后物理DELETE，没有deleted列；显式再创建可得不同ID，旧trash快照与旧ID不当本次回执。Flutter本地partial active-URL唯一/独立trash语义不变。
