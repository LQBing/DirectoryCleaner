# DirectoryCleaner

a tool image for clean folder

## versions

- `lqbing/directorycleaner:1.0.1`: original release. Cleaning only (`CLEANPATH`, `KEEP`, `KEEPPATH`, `CLEANEMPTYFOLDER`, `CRON`).
- `lqbing/directorycleaner:1.0.2`: adds log rotation (`ROTATE`, `ROTATEPATH`, `ROTATESIZE`, `ROTATECOUNT`, `ROTATEMODE`, `ROTATECOMPRESS`, `ROTATEINTERVAL`, `ROTATESTATE`) and a separate rotation schedule (`ROTATECRON`, defaults to `CRON`). The default `ROTATEMODE` is `copytruncate`. Also fixes `CLEANEMPTYFOLDER` so `true` enables and `false` disables empty-folder cleanup, and allows `CLEANPATH` to point to a single file.
- `lqbing/directorycleaner:latest`: currently points to `1.0.2`.

Use the pinned tag `1.0.2` in production. The `ROTATE*` parameters below are only available in `1.0.2` and later.

## parameters

CLEANPATH: Directories or files need to clean, split with ";", can not be none.

CRON: Run cleaning as scheduled, example as `* * * * *`. Or you wanna run once, keep it empty.

ROTATECRON: Run rotation as scheduled when `ROTATE=true`. Defaults to `CRON` when empty. Set it more frequently than `CRON` for fast-growing files. For time-based rotation, this schedule must run at least as often as `ROTATEINTERVAL`; for example, `ROTATEINTERVAL=hourly` needs `ROTATECRON="0 * * * *"`.

KEEP: How many days ago before files need to clean. Default value 30

CLEANEMPTYFOLDER: Delete empty directories older than `KEEP`. Default `true`. The value is case-insensitive: `false`, `0`, `no`, and `off` keep empty directories; any other value deletes them. This only applies when `CLEANPATH` is a directory.

ROTATE: Enable log rotation for collected files. Accepted values are case-insensitive: `true`, `false`, `1`, `0`, `yes`, `no`, `on`, `off`. Default `false`.

ROTATEPATH: Paths need to rotate, split with ";". Defaults to `CLEANPATH` when empty.

ROTATESIZE: Size threshold for rotation. Must be a non-empty integer, optionally followed by `k`, `K`, `M`, or `G`, for example `50M`, `512k`, `1G`. Decimal values such as `1.5M` are rejected. Default `50M`.

ROTATEINTERVAL: Time-based rotation interval. Accepted values are case-insensitive: `off`, `hourly`, `daily`, `weekly`, `monthly`, `yearly`; the singular aliases `hour`, `day`, `week`, `month`, and `year` are also accepted. Default `off`. When an interval is set, `ROTATESIZE` becomes a `maxsize` early trigger; when `off`, `ROTATESIZE` is the only rotation trigger.

ROTATECOUNT: How many rotated files to keep. Default `5`.

ROTATESTATE: logrotate state file used by time-based rotation. Default `/var/lib/directorycleaner/logrotate.status`. Mount a persistent volume at the parent directory and point `ROTATESTATE` there when using `ROTATEINTERVAL`; a container restart otherwise resets the rotation clock.

LOCKWAIT: Seconds a clean or rotate run waits for the shared lock before giving up. Default `120`.

ROTATEMODE: `create` (rename and create a new file) or `copytruncate` (copy then truncate the same file). Accepted values are case-insensitive. Default `copytruncate`.

ROTATECREATE: Optional attributes for `ROTATEMODE=create`, for example `0640 root root`. When empty, logrotate preserves the original file owner, group, and mode.

ROTATECOMPRESS: Compress rotated files. Accepted values are case-insensitive. Default `true`.

`CRON` runs cleaning and `ROTATECRON` runs rotation. `ROTATECRON` defaults to `CRON`, so rotation and cleaning run on the same schedule unless you override it. When `CRON` is empty, rotation and cleaning run once and the container exits; `ROTATECRON` is ignored in that mode.

Rotate scheduling is skipped entirely when `ROTATE` is not `true`; the container only registers the cleaner cron.

The entrypoint rewrites its own `/usr/bin/cleaner` and `/usr/bin/rotate` cron lines on container start. If `ROTATE` is disabled or schedules change, the entrypoint removes or updates its previous cron lines.

Every regular file under `ROTATEPATH` is considered for rotation, including files in subdirectories. A file is actually rotated only when it is non-empty and either the size threshold is exceeded or the configured time interval has elapsed. Existing rotated files (`.1`, `.2`, `.gz`, and other compressed archives) are skipped so they are not rotated twice.

## ROTATEMODE: create vs copytruncate

`ROTATEMODE` controls how the active log file is replaced.

### create

```text
app.log.json  ->  app.log.json.1
app.log.json  ->  new empty file, new inode
```

logrotate renames the active file and creates a new file with the original name. The application must reopen the log path on its next write.

This is the recommended mode for applications that can detect an inode change and reopen, especially:

- Python `logging.handlers.WatchedFileHandler`
- services with multiple workers or child processes that write the same log file
- log files collected by fluent-bit via `*.log.json`
- any application with an explicit reopen-on-rotation mechanism

Advantages:

- no copy-then-truncate window, so no log lines are lost between copy and truncate
- the new file has a new inode, so fluent-bit does not apply the old file offset to the new file
- safe for multi-process writers when every process uses `WatchedFileHandler`
- clean file replacement and predictable `.1`, `.2`, ... history

Requirements and risks:

- the application must reopen the file; if it keeps writing to the old descriptor, logs continue going to `.1`
- do not combine with an in-process `RotatingFileHandler`; that causes double rotation
- the application user must be able to write the newly created file. Use `ROTATECREATE` when the default owner/group/mode is not suitable, for example:

```yaml
ROTATEMODE: "create"
ROTATECREATE: "0640 root root"
```

When `ROTATECREATE` is empty, logrotate preserves the original owner, group, and mode.

### copytruncate

```text
app.log.json  ->  copy contents to app.log.json.1
app.log.json  ->  truncate the same file to 0 bytes, same inode
```

The original path is truncated in place. It does become 0 bytes; the old contents are in `.1`. The application does not need to reopen because it keeps writing to the same inode.

Use this mode only when:

- the application cannot be changed to reopen its log file
- the application holds the file descriptor open indefinitely
- a very small chance of losing recent lines is acceptable
- the collector is not sensitive to inode reuse and file-size resets

Advantages:

- no application reopen required
- works with simple or legacy writers that keep a permanent file descriptor
- the original path remains valid

Risks:

- logrotate copies first and truncates second; writes between those two operations can be lost
- the operation is not atomic
- a large file needs temporary disk space and extra I/O for the copy
- for fluent-bit and other inode + offset tailers, the same inode suddenly shrinking to 0 can cause duplicate delivery or lost lines depending on the tail implementation
- a writer that is not using append mode can keep a stale file offset, producing a sparse file or unexpected gaps

`copytruncate` is the generic default because it works with the widest range of applications, but it is not the best choice for the beop JSON log pipeline.

### Which one to use

| Writer behavior | Recommended mode |
|---|---|
| Python `WatchedFileHandler` | `create` |
| Application explicitly reopens after rotation | `create` |
| Multi-worker process writing one file | `create`, with all workers using `WatchedFileHandler` |
| Application holds the file descriptor and cannot reopen | `copytruncate` |
| Application already uses its own `RotatingFileHandler` | Do not rotate externally; disable one of the two mechanisms |

For beop-util services such as evo-mcp, engine-gateway, memory-engine, and knowledge-lake, use:

```yaml
ROTATEMODE: "create"
```

The default remains `copytruncate` for compatibility with generic workloads, but the beoplog deployment explicitly sets `create`.

After either mode, verify that:

- `.1` was created
- the active file exists and is writable
- the application writes new lines
- no `Logging error` appears
- ES does not show duplicated lines

When `ROTATECOMPRESS=true`, the most recent rotated file may remain uncompressed until the next rotation cycle because `delaycompress` is enabled. This avoids compressing a file that may still be held open by a writer.

Cleaning and rotation use a shared local lock. If a previous clean or rotate run is still active, the new cron run waits up to `LOCKWAIT` seconds instead of racing with it. If the lock cannot be acquired within that window, the run logs a timeout and exits without doing work.

Cron expressions must contain exactly five fields; invalid `CRON` or `ROTATECRON` values are rejected at startup. For C's `WatchedFileHandler` logs, set `ROTATEMODE=create` and optionally `ROTATECREATE="0640 root root"`.

## run once

```shell
docker run --rm -it --name dc -v /clean/path:/workspace -e CLEANPATH="/var/log/test*" -e KEEPPATH="/var/log/test1;/var/log/test2" -e ROTATE=true -e ROTATESIZE=50M -e ROTATECOUNT=5 lqbing/directorycleaner:1.0.2
```

## run as scheduled

```shell
docker run -d --name dc -v /clean/path:/workspace -e CRON="* * * * *" -e CLEANPATH="/var/log/test*" -e KEEPPATH="/var/log/test1;/var/log/test2" -e ROTATE=true -e ROTATECRON="* * * * *" -e ROTATESIZE=50M -e ROTATECOUNT=5 lqbing/directorycleaner:1.0.2
```

## rotate faster than cleaning

```shell
docker run -d --name dc -v /clean/path:/workspace \
  -e CLEANPATH="/var/log/test*" \
  -e CRON="0 3 * * *" \
  -e ROTATE=true \
  -e ROTATECRON="*/5 * * * *" \
  -e ROTATESIZE=50M \
  -e ROTATECOUNT=5 \
  lqbing/directorycleaner:1.0.2
```

## time-based rotation with persistent state

```shell
docker run -d --name dc -v /clean/path:/workspace \
  -v /var/lib/directorycleaner:/var/lib/directorycleaner \
  -e CLEANPATH="/var/log/test*" \
  -e CRON="0 3 * * *" \
  -e ROTATE=true \
  -e ROTATECRON="0 * * * *" \
  -e ROTATEINTERVAL="daily" \
  -e ROTATESIZE=50M \
  -e ROTATECOUNT=5 \
  lqbing/directorycleaner:1.0.2
```

## run in kubernetes as DaemonSet

```yaml
kind: DaemonSet
apiVersion: apps/v1
metadata:
  name: directorycleaner
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: directorycleaner
  template:
    spec:
      volumes:
        - name: hostlog
          hostPath:
            path: /var/logs
            type: ''
        - name: state
          hostPath:
            path: /var/lib/directorycleaner
            type: DirectoryOrCreate
      containers:
        - name: directorycleaner
          image: lqbing/directorycleaner:1.0.2
          env:
            - name: CLEANPATH
              value: "/hostlog;/var/log"
            - name: KEEPPATH
              value: "/var/log/test1;/var/log/test2"
            - name: CRON
              value: "0 3 * * *"
            - name: ROTATECRON
              value: "*/5 * * * *"
            - name: KEEP
              value: '7'
            - name: CLEANEMPTYFOLDER
              value: "true"
            - name: ROTATE
              value: "true"
            - name: ROTATESIZE
              value: "50M"
            - name: ROTATECOUNT
              value: "5"
            - name: ROTATEMODE
              value: "copytruncate"
            - name: ROTATECOMPRESS
              value: "true"
            - name: ROTATESTATE
              value: "/var/lib/directorycleaner/logrotate.status"
          volumeMounts:
            - name: hostlog
              mountPath: /hostlog/
            - name: state
              mountPath: /var/lib/directorycleaner
```
