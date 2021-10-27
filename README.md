# DirectoryCleaner

a tool image for clean folder

## parameters

CLEANPATH: Directories need to clean, split with ";", can not be none.

CRON: Run as scheduled, example as '* * * * *'. Or you wanna run once, keep it empty.

KEEP: How many days ago before files need to clean. Default value 30

## run once

docker run --rm -it --name dc -v /clean/path:/workspace -e CLEANPATH="/var/logs;/var/log" lqbing/directorycleaner

## run as scheduled

docker run -d --name directorycleaner -v /clean/path:/workspace -e CRON="* * * * *" -e CLEANPATH="/var/logs;/var/log" lqbing/directorycleaner

## run in kubernetes

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
            - name: CRON
              value: "* * * * *"
            - name: KEEP
              value: '7'
          volumeMounts:
            - name: hostlog
              mountPath: /hostlog/
```