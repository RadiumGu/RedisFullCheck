# RedisFullCheck（TLS 增强版）

> 本仓库 fork 自 [tair-opensource/RedisFullCheck](https://github.com/tair-opensource/RedisFullCheck)，在原版基础上**增加了 TLS 支持**（单机、集群、mTLS），并在 Amazon ElastiCache Redis OSS 7.0、Valkey 9.0（开启传输加密，单机和集群模式）上验证通过。English: [README.md](README.md)

RedisFullCheck 用于校验两个 Redis 的数据是否一致，常用于迁移后的数据核对。工具从源端取 key，到目标端比对，不一致的结果写入 sqlite3，下一轮只比对上一轮的差异，逐轮收敛。

只从源端取 key，所以目标端多出来的 key 发现不了。要确认两边完全一致，需要双向各跑一次：源→目标、目标→源。

* 上游中文文档：<https://developer.aliyun.com/article/690463>
* 上游 wiki（首次使用如何配置）：<https://github.com/tair-opensource/RedisFullCheck/wiki>
* 本 fork 的发布页：<https://github.com/RadiumGu/RedisFullCheck/releases>

## 支持范围

单机、集群、代理（阿里云、腾讯云集群代理）。Redis 2.x～7.x，Valkey（已测 9.0）。不支持 Redis Modules。
源端和目标端可分别使用明文或 TLS（含 mTLS）。

## 编译

需要 Go ≥ 1.17 和 gcc（sqlite3 依赖 cgo，请在目标平台上编译）。x86_64（如 t3/m6i/c6i 等 Intel/AMD EC2）和 aarch64（Graviton EC2）都支持。

```
# Amazon Linux 2023，x86_64 和 aarch64 相同
sudo dnf install -y golang gcc git
git clone https://github.com/RadiumGu/RedisFullCheck.git
cd RedisFullCheck && ./build.sh
./bin/redis-full-check --help
```

## TLS 参数

源端、目标端各一套（`--source*` / `--target*`）：

| 参数 | 说明 |
|---|---|
| `--sourcetls` / `--targettls` | 开启 TLS |
| `--sourcetlscacert` / `--targettlscacert` | 私有 CA 的 PEM 文件；不填用系统根证书（ElastiCache / MemoryDB 无需填写） |
| `--sourcetlscert` + `--sourcetlskey` | 客户端证书和私钥（mTLS），必须成对提供 |
| `--sourcetlsservername` | 覆盖证书校验 / SNI 用的主机名 |
| `--sourcetlsinsecure` | 跳过服务端证书校验，仅用于排查问题 |

## 示例

```
# ElastiCache 单机（TLS + AUTH）→ ElastiCache 集群模式（TLS + AUTH）
./bin/redis-full-check \
  -s master.src.xxxx.apne1.cache.amazonaws.com:6379 -p '<源端token>' --sourcetls \
  -t master@clustercfg.dst.xxxx.apne1.cache.amazonaws.com:6379 -a '<目标端token>' --targetdbtype 1 --targettls \
  -m 1 --comparetimes 3 --log check.log --result diff.txt

# 自建 Redis（私有 CA + 客户端证书）→ ElastiCache
./bin/redis-full-check \
  -s 10.0.0.10:6380 --sourcetls --sourcetlscacert ca.crt --sourcetlscert client.crt --sourcetlskey client.key \
  -t master.dst.xxxx.apne1.cache.amazonaws.com:6379 --targettls
```

## 注意事项

* 集群模式用配置端点，写成 `master@<配置端点>:6379`，并加 `--targetdbtype 1`（源端用 `--sourcedbtype 1`）。节点自动发现，所有节点连接使用同一套 TLS 设置。
* 证书按集群返回的节点地址校验。ElastiCache（开启 TLS）在默认设置下校验通过（已测 Redis OSS 7.0 / Valkey 9.0）。如果集群返回 IP、证书里没有对应 IP，用 `--*tlsservername` 指定证书中的域名，或临时用 `--*tlsinsecure`。
* 对只开 TLS 的端点忘记加 `--*tls` 时，程序会卡住而不是报错，脚本里建议套 `timeout`。
* `-m 1` 做全量值比对，最严格；默认 `-m 2` 只比对长度。
* 校验结果在 sqlite3 文件 `result.db.N` 中，N 是轮次，例如 `sqlite3 result.db.3 'select * from key'`。

## 验证脚本

见 [test/tokyo](test/tokyo)：在东京 region 自动创建 VPC、运行机和 4 个 ElastiCache 集群，跑完 16 个用例（明文/TLS/mTLS、单机/集群、错误 CA、数据差异检测），再全部删除。

## License

Apache 2.0，同上游。`src/full_check/third_party/redis-go-cluster` 来自 [najoast/redis-go-cluster](https://github.com/najoast/redis-go-cluster)（Apache 2.0），加入了 TLS 支持。
