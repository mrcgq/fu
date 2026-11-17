# ctbrec 修复包 · StripChat + Chaturbate 稳定录制（fix2）

日期：2026-11-17
本包 = 修复后源码 + 成品 jar。不含 `target/` 构建产物与文档站素材（`docs/img`、`docs/vendor`）。
**fix2 相对上一版的唯一差别：修了构建用的 `master/pom.xml`（上一版里这一行是错的，CI 因此挂在 `open-m3u8`）。**

---

## 0. 你问的「哪个文件代码写错了」

**`master/pom.xml` 第 22 行**（仓库 `<url>`）：

```xml
<!-- 错的（上一版）：没有 file: 方案，Maven 把 ${project.basedir}/... 当成 http 仓库名去找连接器 -->
<url>${project.basedir}/../repo</url>

<!-- 对的（本版）-->
<url>file:///${project.basedir}/../repo</url>
```

报错就是这条：

```
[ERROR] Failed to execute goal on project common: Could not resolve dependencies for project ctbrec:common
[ERROR]   Could not find artifact com.iheartradio.m3u8:open-m3u8:pom:0.2.8-CTBREC in central
[ERROR]   ... open-m3u8:jar:0.2.8-CTBREC with type default using the available connector factories:
[ERROR]       BasicRepositoryConnectorFactory
```

要点：`open-m3u8:0.2.8-CTBREC` 不在 Maven Central，只在本仓库自带的 `repo/`（file repository）里 ——
`repo/com/iheartradio/m3u8/open-m3u8/0.2.8-CTBREC/open-m3u8-0.2.8-CTBREC.{jar,pom}`（注意 groupId 是 `com.iheartradio.m3u8`，
目录是 `com/iheartradio/...`）。`repo/` 的目录布局本来是对的，**唯一错的就是那个缺了 `file:` 的 URL**：
没有 scheme，Maven 就没有任何 transporter 能读它，于是「仓库存在但取不到」。

本地为何没暴露：`.m2` 里有这个 artifact（还带 `.lastUpdated` 残档）会直接判过 —— 假绿。
把 `~/.m2/repository/com/iheartradio/m3u8` 挪走再跑你那条命令，才复现出和你一样的失败；改完 `file:///` 后 `common` 变 SUCCESS。

## 0.1 修完 pom 后的第二个坎（不是代码错，是打包输入缺失）

`client/src/assembly/win64-jre.xml` 里 ffmpeg 是**硬 `<file>`**（要重命名成 `ffmpeg.exe`，所以不能写成 fileSet）：

```xml
<file><source>${project.basedir}/ffmpeg/ffmpeg-win64.exe</source>
      <outputDirectory>ctbrec/lib/ffmpeg</outputDirectory>
      <destName>ffmpeg.exe</destName></file>
```

仓库里原本没有 `client/ffmpeg/ffmpeg-win64.exe`，`package` 会挂在
`Error adding file to archive: ...\client\.\ffmpeg\ffmpeg-win64.exe`。
**本包已把这个二进制放进 `client/ffmpeg/ffmpeg-win64.exe`（87,728,640 B，就是 app 自己在用的那份 ffmpeg）**，
所以你的命令不用再带任何跳过参数。若你的 CI 仓库里已经有它，直接删掉本包这份即可。

`client/jre/jdk_windows`、`client/browser/ctbrec-minimal-browser-win32-x64` 是 fileSet，缺了只 WARNING 不失败（成品 zip 里少内嵌 JRE / 内嵌浏览器）。

## 0.2 你的 CI 命令（原样，已实测通过）

```bat
mvn -B -ntp -e -DskipTests package -U -am -f ./master -pl :client -Djavafx.platform=win
```

```
[INFO] Reactor Build Order:  master 5.3.4 -> common 5.3.4 -> client 5.3.4
[INFO] Reading assembly descriptor: src/assembly/win64-jre.xml
[INFO] Building zip: ...\client\target\ctbrec-5.3.4-win64-jre.zip
[INFO] master ............................................. SUCCESS [  0.002 s]
[INFO] common ............................................. SUCCESS [  1.682 s]
[INFO] client ............................................. SUCCESS [ 10.817 s]
[INFO] BUILD SUCCESS
```

注意两点（跟 pom 无关，是命令行本身的坑）：
1. `-f ./master` 必须指到 `master/pom.xml`（仓库根没有聚合 pom，写 `-f .` 会 `Could not find the selected project in the reactor: common`）。
2. 在 PowerShell 里 `-Djavafx.platform=win` 会被拆成两段，报 `Unknown lifecycle phase ".platform=win"`，要写成 `'-Djavafx.platform=win'`；CI 的 `cmd`/`sh` 不受影响。

---

## 1. 一句话结论

StripChat 的 MOUFLON（XOR key）录制路径**本来就是通的**，被两个具体 bug 挡住了；修完后离线纯 Java（不开浏览器）实测 6 轮连抓 15,165,788 字节真段、seq 连续推进、稳定命中最高画质档。Chaturbate 走 `get_edge_hls_url_ajax` + 变体自带 `?session=` 继承，同样实测通过。

## 2. 关键事实：密钥配对（不要改，你原来的值是对的）

| 用途 | 值 | 出现在 |
|---|---|---|
| XOR 口令（解密段名） | `tOcYOap4Ty1l9Jzb` | 设置页 “XOR Key (v2)” |
| **pkey（查询串里发的 keyId）** | `NTK9aqcLmNFMWrpQ` | 设置页 “V1 Key 1” |

派生：`K16 = sha256("tOcYOap4Ty1l9Jzb")[:16]` = `1838c78f543606e6de5fc81167f36e5a`

段名解码（播放器真实算法，已用两组独立明密对自检验证）：

```
rev   = reverse(hash)                       # 22 位 base64 串倒过来
rev  += '='  补到 4 的倍数
data  = base64Decode(rev)                   # 16 字节
plain[i] = data[i] XOR K16[i]               # 结果恒为 [A-Za-z0-9]{16}
```

**最重要的坑**：master 里的 11 行 `#EXT-X-MOUFLON:PSCH:v2:<x>` 只有 `NTK9aqcLmNFMWrpQ` 是真 keyId，**其余 10 个是诱饵**。
用诱饵当 pkey 时，媒体播放列表照样 `200`、照样带 `#EXTINF`、照样不是 `/cpa/` 广告列表 —— 但段名一段都解不开，于是每段静静 404。
这就是「看起来一切正常但录不到东西」的根因。已用 `Mouflon.decodedV2Count()` 把这种状态变成**显式报错**，不再静默失败。

## 3. 改了什么（代码侧）

### 3.1 让 XOR 路径真正生效

| 文件 | 问题 | 修法 |
|---|---|---|
| `recorder/download/hls/StripchatPlaylist.java` | `pkey()` 把 **XOR 口令本身**当 pkey 发出去 | 改为发 keyId（`MouflonSettings.getPkey()`）；新增 `xorKey()`、`decodableSegmentCount()`、`undecodedMouflonSegments()` |
| `sites/stripchat/StripchatModel.java` | 拿 `seeds.get(0)` 当 pkey → 命中诱饵 | 优先用配置里的 keyId；并真正合并 `_auto` master 的多档阶梯（原 `url.replace("_auto","")` 因 url 里从来没有 `_auto` 而永不触发，是死代码） |
| `sites/stripchat/mouflon/MouflonSettings.java` | 无 pkey 概念 | 新增 `pkey` 字段（默认 `NTK9aqcLmNFMWrpQ`）+ `adopt()` 落盘已验证配对 |
| `sites/stripchat/mouflon/Mouflon.java` | 无法判断“拿到的是不是能解的列表” | 新增 `hasV2Segments()`、`decodedV2Count()` |
| `recorder/download/hls/AbstractHlsDownload.java` | 解不开时段静静 404 | 解析后立刻检查，抛 `IOException("MOUFLON segments not decodable ...")` |
| `Settings.java` | — | 新增 `pkeyV2`、`alwaysPreferHighestQuality`（默认值编进 jar，`settings.json` 被旧实例覆写也不影响） |

### 3.2 画质（你反馈的「2160p/1440p/1080p/720p/450p/360p 各房不同」）

| 位置 | bug | 后果 |
|---|---|---|
| `sites/chaturbate/ChaturbateModel.java:339` | `if (w > res[1])` —— 拿 **width 跟 height 比** | `428x240` 能压过 `960x540` |
| `recorder/download/StreamSource.compareTo` | 只比 height | 竖屏流（StripChat 常见 `720x960`）被误排 |
| `recorder/download/AbstractDownload.selectStreamSource` | 按 `streamUrlIndex` **位置**取档 | 阶梯每次开播都变（房不同/顶档时有时无），位置型索引随机掉到 360p/450p |
| `sites/stripchat/StripchatModel.getStreamResolution` | 未排序取 `size()-1` | StripChat `_auto` master 是**降序**（source 在最前），于是取到 **240p** |
| `recorder/download/hls/HlsdlDownload` | 同样的位置型选择 | 与主路径统一 |

现在统一按**像素数 → 高度 → 带宽**排序，末位恒为最高档；`alwaysPreferHighestQuality`（默认 true）把遗留的 `streamUrlIndex` 解析成分辨率而非位置，关掉后 `minimumResolution`/`maximumResolution`/`restrictBitrate` 照常生效。

## 4. 实测数据（都用部署后的 jar、纯 Java、不开浏览器）

```
pkey=NTK9aqcLmNFMWrpQ  playlist=REAL mouflon=17 decodable=17  fetched 4/4  3,266,249B
   200 1237B     init_8XzZLUHeUJgsafVn.mp4
   200 1025472B  1138_JQuG6TI7bU096OaC_...mp4
   200 1083871B  1139_zwf9tzBj1jt8cQUW_...mp4
   200 1025517B  1140_hZBRxNiLHueWUFpV_...mp4

ROUNDS=6 withBytes=6 TOTAL=15,165,788B       seq 连续 1138 -> 1151，全 200，box=sidx
=> STRIPCHAT SUSTAINED CAPTURE PASS (native XOR-key path)

ladder: 1920x1080 1280x720 854x480 426x240 -> selected 1920x1080 @4952780
```

诱饵对照（同一条流、同一时刻）：

```
pkey=1Dzcc6OjP73LKbtI  playlist=REAL mouflon=19 decodable=0  -> decoy
pkey=7uUnbD0jMCB9GH32  playlist=REAL mouflon=17 decodable=0  -> decoy
... 10 个诱饵全部 REAL+decodable=0，只有 NTK9aqcLmNFMWrpQ 全解
```

自检（两组独立明密对）：

```
decode(gDosrLE5fLsCJVZdixsmUb) = uqkIsoRvrr6UIHFT   MATCH
decode(gFascLkw5E/etTXBA5Gy2T) = WTAkTaH1aLT5J8tL   MATCH
```

Chaturbate：1080p 阶梯 + 段 `token/session` 继承已实测（变体 URI 自带 `?session=`，绝不能重组路径或丢 query）。

单测：`mvn -pl :common test` → **Tests run: 110, Failures: 0, Errors: 0**（含新增 `QualitySelectionTest` 8 条 + `StripchatFixTest` 10 条，明密对与诱饵识别都锁在里面）。

## 5. 部署

⚠️ **必须覆盖清单真正指名的那个 jar**。app 的 `MANIFEST.MF` 里写死 `lib/common-5.3.4.jar`；覆盖 `common-5.4.4.jar` **不会生效**（踩过，白跑几轮）。

```bat
:: 方式 A：用本包成品 jar，替换目标安装目录里清单指名的文件
deploy.bat "D:\ctbrec-fixed-544"

:: 方式 B：可运行的服务端（fat jar，已内嵌修复后的全部类）
java -jar dist\ctbrec-server-5.3.4-final.jar
```

如果有**旧实例**在跑，它会用旧 jar 且不停覆写 `settings.json` 把新字段抹掉。这不影响功能（默认值已编进 jar），但要确认启动的是修好的那份。

## 6. 配置

`%APPDATA%\ctbrec\5.4.4\extra.json`（可热改，`MouflonSettings.reload()`）：

```json
{"xorKey":"tOcYOap4Ty1l9Jzb","pkey":"NTK9aqcLmNFMWrpQ","v1Keys":["NTK9aqcLmNFMWrpQ","tOcYOap4Ty1l9Jzb"]}
```

`settings.json` 相关项（都有 jar 内默认值，缺省即可）：

```
"pkeyV2":"NTK9aqcLmNFMWrpQ", "xorKeyV2":"tOcYOap4Ty1l9Jzb",
"stripchatDemangle":true, "alwaysPreferHighestQuality":true,
"proxyType":"HTTP", "proxyHost":"127.0.0.1", "proxyPort":"10808",
"egressGuardEnabled":true, "egressGuardIntervalSecs":45
```

## 7. 构建

```bat
set JAVA_HOME=<JDK21>
mvn -B -ntp -e -DskipTests package -U -am -f ./master -pl :client -Djavafx.platform=win
```

或分模块：

```bat
mvn -o -f master\pom.xml install
mvn -o -f common\pom.xml install
mvn -o -f server\pom.xml package          :: -> ctbrec-server-5.3.4-final.jar
mvn -o -f client\pom.xml package -Djavafx.platform=win
```

`repo/` 是 file repository（含 `open-m3u8-0.2.8-CTBREC`），离线构建必需 —— 它的 `<url>` 现在带 `file:///`，所以 `-o` 离线也能过。
只想出 jar 不出 zip：`-D"assembly.skipAssembly=true"`。

## 8. 验证脚本（`tools/verify/`）

只依赖 `lib/*` 与部署后的 common，不需要浏览器：

```bat
javac -cp "D:\ctbrec-fixed-544\lib\*" -d out tools\verify\RecSim.java tools\verify\XorProof.java
java  -cp "out;D:\ctbrec-fixed-544\lib\*" RecSim   <streamName(=modelId)>
java  -cp "out;D:\ctbrec-fixed-544\lib\*" XorProof <streamName>
```

`RecSim` 复现录制器内循环（取列表 → `rewriteMediaPlaylistBody` → 不可解检查 → `inheritQuery` → 取段），并校验阶梯排序是否命中最高档。

## 9. 剩余外部变量（代码侧无解）

media-hls CDN 会按**出口 IP 段**返回 403/400（实测漂到 `104.28.x` Cloudflare 段时全域拒答，同时 edge-hls 的 master 仍 200）。这与代码、TLS 指纹、cookie、codec 都无关 —— 换代理出口节点即恢复。`EgressGuard` 在 IP 漂移时失效 DNS/会话缓存并触发 token 刷新，但 CDN 侧的段封锁必须换出口。

## 10. 本包未含（可复现，非源码）

- 各模块 `target/`（构建产物，`mvn package` 可重建，含成品 `client\target\ctbrec-5.3.4-win64-jre.zip`）
- `docs/img`、`docs/vendor`（文档站素材，与修复无关；`src/main/resources/html/static/vendor` **已保留**）
- `.decompiled/`、`probe/`（排障期的反编译与临时探针，非项目代码）
