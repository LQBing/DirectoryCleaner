# DirectoryCleaner

a tool image for clean folder

## parameters

CLEANPATH: Directories need to clean, split with ";", can not be none.

CRON: Run as scheduled, example as `* * * * *`. Or you wanna run once, keep it empty.

KEEP: How many days ago before files need to clean. Default value 30

## run once

```shell
docker run --rm -it --name dc -v /clean/path:/workspace -e CLEANPATH="/var/log/test*" -e KEEPPATH="/var/log/test1;/var/log/test2" lqbing/directorycleaner
```

## run as scheduled

```shell
docker run -d --name dc -v /clean/path:/workspace -e CRON="* * * * *" -e CLEANPATH="/var/log/test*" -e KEEPPATH="/var/log/test1;/var/log/test2" lqbing/directorycleaner
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
          image: lqbing/directorycleaner
          env:
            - name: CLEANPATH
              value: "/hostlog;/var/log"
            - name: KEEPPATH
              value: "/var/log/test1;/var/log/test2"
            - name: CRON
              value: "* * * * *"
            - name: KEEP
              value: '7'
            - name: CLEANEMPTYFOLDER
              value: "true"
          volumeMounts:
            - name: hostlog
              mountPath: /hostlog/
```
