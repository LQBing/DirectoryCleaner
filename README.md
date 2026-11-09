# DirectoryCleaner

a tool image for clean folder

## versions

- `lqbing/directorycleaner:1.0.1`: original release. Cleaning only (`CLEANPATH`, `KEEP`, `KEEPPATH`, `CLEANEMPTYFOLDER`, `CRON`).
- `lqbing/directorycleaner:1.0.2`: adds log rotation (`ROTATE`, `ROTATEPATH`, `ROTATESIZE`, `ROTATECOUNT`, `ROTATEMODE`, `ROTATECOMPRESS`) and a separate rotation schedule (`ROTATECRON`, defaults to `CRON`). Also fixes `CLEANEMPTYFOLDER` so `true` enables and `false` disables empty-folder cleanup, and allows `CLEANPATH` to point to a single file.
- `lqbing/directorycleaner:latest`: currently points to `1.0.2`.

Use the pinned tag `1.0.2` in production. The `ROTATE*` parameters below are only available in `1.0.2` and later.

## parameters

CLEANPATH: Directories or files need to clean, split with ";", can not be none.

CRON: Run cleaning as scheduled, example as `* * * * *`. Or you wanna run once, keep it empty.

ROTATECRON: Run rotation as scheduled when `ROTATE=true`. Defaults to `CRON` when empty. Set it more frequently than `CRON` for fast-growing files.

KEEP: How many days ago before files need to clean. Default value 30

CLEANEMPTYFOLDER: Delete empty directories older than `KEEP`. Default `true`; set `false` to keep empty directories. This only applies when `CLEANPATH` is a directory.

ROTATE: Enable log rotation for collected files. `true` or `false`, default `false`.

ROTATEPATH: Paths need to rotate, split with ";". Defaults to `CLEANPATH` when empty.

ROTATESIZE: Rotate a file when it grows bigger than this size. Default `50M`.

ROTATECOUNT: How many rotated files to keep. Default `5`.

ROTATEMODE: `create` (rename and create a new file) or `copytruncate`. Default `create`.

ROTATECOMPRESS: Compress rotated files. `true` or `false`, default `true`.

`CRON` runs cleaning and `ROTATECRON` runs rotation. `ROTATECRON` defaults to `CRON`, so rotation and cleaning run on the same schedule unless you override it. When `CRON` is empty, rotation and cleaning run once and the container exits; `ROTATECRON` is ignored in that mode.

Rotate scheduling is skipped entirely when `ROTATE` is not `true`; the container only registers the cleaner cron.

Every regular file under `ROTATEPATH` is rotated, including files in subdirectories. Existing rotated files (`.1`, `.2`, `.gz`, and other compressed archives) are skipped so they are not rotated twice.

`create` mode is suitable for applications that reopen their log file after it is renamed (for example Python `WatchedFileHandler`). Use `ROTATEMODE=copytruncate` when the application keeps the original file descriptor open and does not reopen it.

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
              value: "create"
            - name: ROTATECOMPRESS
              value: "true"
          volumeMounts:
            - name: hostlog
              mountPath: /hostlog/
```
