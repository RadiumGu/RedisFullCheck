> **This is a fork of [tair-opensource/RedisFullCheck](https://github.com/tair-opensource/RedisFullCheck) that adds TLS support** (standalone and cluster, incl. mTLS), validated against Amazon ElastiCache Redis OSS 7.0 and Valkey 9.0 with in-transit encryption. See [TLS](#tls). 中文说明见 [README_CN.md](README_CN.md).

Redis-full-check is used to compare whether two redis have the same data. We also offer a data synchronization tool called [RedisShake](https://github.com/tair-opensource/RedisShake) to syncing data from one redis to another redis.<br>
Thanks to the Douyu's WSD team for the support. <br>

* [中文文档 (upstream)](https://developer.aliyun.com/article/690463)
* [Download / build](#usage) — this fork: [releases](https://github.com/RadiumGu/RedisFullCheck/releases)
* [第一次使用，如何进行配置 (upstream wiki)](https://github.com/tair-opensource/RedisFullCheck/wiki/%E7%AC%AC%E4%B8%80%E6%AC%A1%E4%BD%BF%E7%94%A8%EF%BC%8C%E5%A6%82%E4%BD%95%E8%BF%9B%E8%A1%8C%E9%85%8D%E7%BD%AE%EF%BC%9F)

# redis-full-check
---
Redis-full-check is developed and maintained by NoSQL Team in Alibaba-Cloud Database department.<br>
Redis-full-check performs full data verification by comparing the data of the source database and the destination database. The entire check process consists of multiple comparisons, in every comparison, redis-full-check fetches data from two dabatases and then compared, the inconsistent data is put into sqlite3 db for the next comparison. By this iteratively comparing method, the difference continues to converge. The following figure shows the dataflow. In every comparison which is the yellow box, redis-full-check fetches all keys firstly. After that, it runs comparison and stores the difference result(key and field) into the sqlite3 db which is the position that keys and fields can be fetched in next round instead of the source database.<br>
![dataflow.png](resources/dataflow.png)<br>
Redis-full-check fetches keys from source and then checks these keys exist on the target. So if one key exists on the target but lack on the source, redis-full-check can't find it. If you want to know whether the data in the source and destination databases are exactly the same, you need to set up a bidirectional link: <br>

* source->RedisFullCheck->target
* target->RedisFullCheck->source

# supports
standalone, cluster, proxy(aliyun-cluster, tencent-cluster). Redis version from 2.x to 7.x, and Valkey (tested with 9.0) (Don't support Redis Modules).<br>
Plaintext or TLS (incl. mTLS) on each side independently. Tested with TLS on ElastiCache Redis OSS 7.0 and Valkey 9.0, standalone and cluster mode.

# Code branch rules
Version rules: a.b.c.<br>

*  a: major version
*  b: minor version. even number means stable version.
*  c: bugfix version

| branch name | rules |
| - | :- |
| master | master branch, do not allowed push code. store the latest stable version. develop branch will merge into this branch once new version created. |
| **develop**(main branch) | develop branch. all the bellowing branches fork from this. |
| feature-\* | new feature branch. forked from develop branch and then merge back after finish developing, testing, and code review. |
| bugfix-\* | bugfix branch. forked from develop branch and then merge back after finish developing, testing, and code review. |
| improve-\* | improvement branch. forked from develop branch and then merge back after finish developing, testing, and code review.  |

Tag rules:<br>
Add tag when releasing: "release-v{version}-{date}". for example: "release-v1.0.2-20180628"

# Paramters
```
Usage:
  redis-full-check [OPTIONS]

Application Options:
  -s, --source=SOURCE               Set host:port of source redis.
  -p, --sourcepassword=Password     Set source redis password (format: password or username:password)
      --sourceauthtype=AUTH-TYPE    useless for opensource redis, valid value:auth/adminauth (default: auth)
  -t, --target=TARGET               Set host:port of target redis.
  -a, --targetpassword=Password     Set target redis password (format: password or username:password)
      --targetauthtype=AUTH-TYPE    useless for opensource redis, valid value:auth/adminauth (default: auth)
  -d, --db=Sqlite3-DB-FILE          sqlite3 db file for store result. If exist, it will be removed and a new file is created. (default: result.db)
      --comparetimes=COUNT          Total compare count, at least 1. In the first round, all keys will be compared. The subsequent rounds of the comparison
                                    will be done on the previous results. (default: 3)
  -m, --comparemode=                compare mode, 1: compare full value, 2: only compare value length, 3: only compare keys outline, 4: compare full value,
                                    but only compare value length when meets big key (default: 2)
      --id=                         used in metric, run id (default: unknown)
      --jobid=                      used in metric, job id (default: unknown)
      --taskid=                     used in metric, task id (default: unknown)
  -q, --qps=                        max qps limit (default: 15000)
      --interval=Second             The time interval for each round of comparison(Second) (default: 5)
      --batchcount=COUNT            the count of key/field per batch compare, valid value [1, 10000] (default: 256)
      --parallel=COUNT              concurrent goroutine number for comparison, valid value [1, 100] (default: 5)
      --log=FILE                    log file, if not specified, log is put to console
      --result=FILE                 store all diff result, format is 'db	diff-type	key	field'
      --metric=FILE                 metrics file
      --bigkeythreshold=COUNT
  -f, --filterlist=FILTER           if the filter list isn't empty, all elements in list will be synced. The input should be split by '|'. The end of the
                                    string is followed by a * to indicate a prefix match, otherwise it is a full match. e.g.: 'abc*|efg|m*' matches 'abc',
                                    'abc1', 'efg', 'm', 'mxyz', but 'efgh', 'p' aren't'
      --sourcetls                   connect to source redis with TLS
      --sourcetlsinsecure           skip server certificate verification for source (not recommended)
      --sourcetlscacert=FILE        PEM CA bundle for verifying source server cert; default is system roots
      --sourcetlscert=FILE          PEM client certificate for source (mTLS)
      --sourcetlskey=FILE           PEM client key for source (mTLS)
      --sourcetlsservername=NAME    override TLS server name (SNI/verification) for source
      --targettls / --targettlsinsecure / --targettlscacert / --targettlscert / --targettlskey / --targettlsservername
                                    same as above, for target
  -v, --version

Help Options:
  -h, --help                        Show this help message
```

# Usage
---
Prebuilt binaries of this fork (when published) are on the [releases page](https://github.com/RadiumGu/RedisFullCheck/releases). Build them on the target platform because sqlite3 needs cgo: `linux/amd64` (x86 EC2) and `linux/arm64` (Graviton EC2) are both supported.<br>
Build from source (Go >= 1.17 and gcc):<br>
*  git clone https://github.com/RadiumGu/RedisFullCheck.git
*  cd RedisFullCheck/
*  ./build.sh
*  ./bin/redis-full-check -s $(source_redis_ip_port) -p $(source_password) -t $(target_redis_ip_port) -a $(target_password) # these parameters should be given by users

On Amazon Linux 2023: `sudo dnf install -y golang gcc git && ./build.sh` (same on x86_64 and aarch64).

# TLS
---
Enable TLS per side with `--sourcetls` / `--targettls`. The server certificate is verified against the system CA bundle by default, which works for Amazon ElastiCache / MemoryDB. Use `--*tlscacert` for a private CA, `--*tlscert` + `--*tlskey` for mTLS, and `--*tlsinsecure` only for troubleshooting.<br>

```
# ElastiCache (TLS + AUTH) standalone -> ElastiCache cluster mode
./bin/redis-full-check \
  -s master.src.xxxx.apne1.cache.amazonaws.com:6379 -p '<src-token>' --sourcetls \
  -t master@clustercfg.dst.xxxx.apne1.cache.amazonaws.com:6379 -a '<dst-token>' --targetdbtype 1 --targettls \
  -m 1 --comparetimes 3

# self-managed redis with private CA and client cert (mTLS) as source
./bin/redis-full-check -s 10.0.0.10:6380 --sourcetls --sourcetlscacert ca.crt --sourcetlscert client.crt --sourcetlskey client.key \
  -t master.dst.xxxx.apne1.cache.amazonaws.com:6379 --targettls
```

Notes:
* For cluster mode, pass the configuration endpoint as `master@<endpoint>:6379` with `--targetdbtype 1` (or `--sourcedbtype 1`). Nodes are discovered by `CLUSTER NODES` and every node connection uses the same TLS settings.
* Certificate verification uses the node address returned by the cluster. With ElastiCache (TLS enabled) verification passes with default settings (tested on Redis OSS 7.0 / Valkey 9.0). If your cluster returns IPs and the certificate has no IP SAN, use `--*tlsservername` (e.g. a wildcard name in the cert) or `--*tlsinsecure`.
* If you forget `--*tls` against a TLS-only endpoint, the connection hangs instead of failing quickly. Run with a timeout in automation.
* Validation scripts: [test/tokyo](test/tokyo).

Here comes the sqlite3 example to display the conflict result:<br>
```
$ sqlite3 result.db.3  # result.db.x shows the x-round comparison conflict result. len == -1 means inconsistent key type.

sqlite> select * from key;
id          key              type        conflict_type  db          source_len  target_len
----------  ---------------  ----------  -------------  ----------  ----------  ----------
1           keydiff1_string  string      value          1           6           6
2           keydiff_hash     hash        value          0           2           1
3           keydiff_string   string      value          0           6           6
4           key_string_diff  string      value          0           6           6
5           keylack_string   string      lack_target    0           6           0
sqlite>

sqlite> select * from field;
id          field       conflict_type  key_id
----------  ----------  -------------  ----------
1           k1          lack_source    2
2           k2          value          2
3           k3          lack_target    2
```

# Shake series tool
---
We also provide some tools for synchronization in Shake series.<br>

* [MongoShake](https://github.com/alibaba/MongoShake): mongodb data synchronization tool.
* [RedisShake](https://github.com/tair-opensource/RedisShake): redis data synchronization tool.
* [RedisFullCheck](https://github.com/tair-opensource/RedisFullCheck): redis data synchronization verification tool (upstream of this fork).

# License
- On `20230427` and later, we distribute this library under the new [Apache2.0](https://www.apache.org/licenses/LICENSE-2.0) protocol, `1.4.10` is the first version to support the Apache2.0 protocol.
- Prior to 20230427, it was distributed under the [GPLV3.0](https://www.gnu.org/licenses/gpl-3.0.html) protocol.