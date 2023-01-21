# Gaia Cluster

Some scripts and configuration for developing, building, running, testing, and observing the [Cosmos `gaiad` daemon](https://github.com/cosmos/gaia) inside a [Kind kubernetes cluster](https://kind.sigs.k8s.io/) on your local machine. Please note this is not production-ready configuration.

## Quickstart
> Pull this repo and build the container. Tag it `gaiad`, if you please:
```
$ git clone https://github.com/grggls/gaia-cluster
$ cd gaia-cluster
$ docker build -t gaiad .
```

> Jump into the anchore directory and bring up that service. You'll need to wait 10+ for all the feeds to finish downoading:
```
$ cd anchore
$ docker-compose up -d
$ docker-compose ps
NAME                      COMMAND                  SERVICE             STATUS              PORTS
anchore-analyzer-1        "/docker-entrypoint.…"   analyzer            running (healthy)   8228/tcp
anchore-api-1             "/docker-entrypoint.…"   api                 running (healthy)   0.0.0.0:8228->8228/tcp
anchore-catalog-1         "/docker-entrypoint.…"   catalog             running (healthy)   8228/tcp
anchore-db-1              "docker-entrypoint.s…"   db                  running (healthy)   5432/tcp
anchore-policy-engine-1   "/docker-entrypoint.…"   policy-engine       running (healthy)   8228/tcp
anchore-queue-1           "/docker-entrypoint.…"   queue               running (healthy)   8228/tcp
...
...
```

> In the meantime, push your `gaiad` image to a registry:
```
$ docker tag gaiad grggls/gaiad:latest
$ docker push grggls/gaiad:latest
The push refers to repository [docker.io/grggls/gaiad]
caf120581354: Pushed
5a2d59dfed5a: Pushed
8849ba573d59: Pushed
...
...
latest: digest: sha256:593e91096f70543c9d5f3c164277f9516a78f016ac607c6519814ecc743bbf20 size: 2425
```

> Run your `gaiad` image through Anchore:
```
$ cd ..
$ docker-compose exec api anchore-cli evaluate check grggls/gaiad:latest
Image Digest: sha256:128b029a000d29351020c9ef54f3d59fce377bd6d42db1e69d3751d8b8589c8c
Full Tag: docker.io/grggls/gaiad:latest
Status: pass
Last Eval: 2023-01-15T12:30:20Z
Policy ID: 2c53a13c-1765-11e8-82ef-23527761d060
```

> Build a kind cluster with a local filesystem mount inside, then apply the k8s config for a volume and StatefulSet.
```
$ kind create cluster --config kind.yaml
Creating cluster "gaia" ...
 ✓ Ensuring node image (kindest/node:v1.25.3) 🖼
 ✓ Preparing nodes 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
Set kubectl context to "kind-gaia"
You can now use your cluster with:

kubectl cluster-info --context kind-gaia
 
$ kubectl apply -f ./statefulset.yaml
namespace/gaiad created
service/gaiad created
persistentvolume/pv-gaia unchanged
persistentvolumeclaim/pvc-gaia created
statefulset.apps/gaiad created

$ kubectl get pods -n gaiad
NAME      READY   STATUS    RESTARTS   AGE
gaiad-0   1/1     Running   0          15m
gaiad-1   1/1     Running   0          15m

$ kubectl get pvc -n gaiad
NAME               STATUS    VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pvc-gaia           Pending                                                                        standard       36s
pvc-gaia-gaiad-0   Bound     pvc-835d9388-81b9-4993-9f97-f953977f5d76   1Gi        RWO            standard       36s
pvc-gaia-gaiad-1   Bound     pvc-dd5135d8-9239-447f-a9cc-2e73b0fb0c76   1Gi        RWO            standard       28s

$ kubectl describe statefulset/gaiad -n gaiad
Name:               gaiad
Namespace:          gaiad
CreationTimestamp:  Mon, 16 Jan 2023 10:15:37 +1100
Selector:           app=gaiad
Labels:             <none>
Annotations:        <none>
Replicas:           2 desired | 2 total
Update Strategy:    RollingUpdate
  Partition:        0
Pods Status:        2 Running / 0 Waiting / 0 Succeeded / 0 Failed
Pod Template:
  Labels:  app=gaiad
  Containers:
   gaiad:
    Image:        grggls/gaiad:latest
    Port:         <none>
    Host Port:    <none>
    Environment:  <none>
    Mounts:       <none>
  Volumes:        <none>
Volume Claims:
  Name:          pvc-gaia
  StorageClass:
  Labels:        <none>
  Annotations:   <none>
  Capacity:      1Gi
  Access Modes:  [ReadWriteOnce]
Events:
  Type    Reason            Age   From                    Message
  ----    ------            ----  ----                    -------
  Normal  SuccessfulCreate  11m   statefulset-controller  create Claim pvc-gaia-gaiad-0 Pod gaiad-0 in StatefulSet gaiad success
  Normal  SuccessfulCreate  11m   statefulset-controller  create Pod gaiad-0 in StatefulSet gaiad successful
  Normal  SuccessfulCreate  11m   statefulset-controller  create Claim pvc-gaia-gaiad-1 Pod gaiad-1 in StatefulSet gaiad success
  Normal  SuccessfulCreate  11m   statefulset-controller  create Pod gaiad-1 in StatefulSet gaiad successful
```

## Observability

> Confirm that prometheus metrics are being exported from your pods:
```
$ kubectl get service -n gaiad
NAME    TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                                  AGE
gaiad   ClusterIP   None         <none>        26656/TCP,26657/TCP,1317/TCP,26660/TCP   7h4m

$ kubectl port-forward svc/gaiad -n gaiad 26660:26660
Forwarding from 127.0.0.1:26660 -> 26660
Forwarding from [::1]:26660 -> 26660
Handling connection for 26660
Handling connection for 26660

$ curl -s localhost:26660 | head
# HELP go_gc_duration_seconds A summary of the pause duration of garbage collection cycles.
# TYPE go_gc_duration_seconds summary
go_gc_duration_seconds{quantile="0"} 2.5441e-05
go_gc_duration_seconds{quantile="0.25"} 7.0512e-05
go_gc_duration_seconds{quantile="0.5"} 0.000125282
go_gc_duration_seconds{quantile="0.75"} 0.000200371
go_gc_duration_seconds{quantile="1"} 0.000487721
go_gc_duration_seconds_sum 0.003618512
go_gc_duration_seconds_count 24
```

> Install the Prometheus Operator into the Kind cluster using the procedure in https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/user-guides/getting-started.md. Chose the Operator over the Helm chart for `kube-prometheus-stack` to reduce the number of moving parts to configure.
```
$ LATEST=$(curl -s https://api.github.com/repos/prometheus-operator/prometheus-operator/releases/latest | jq -cr .tag_name)
$ curl -sL https://github.com/prometheus-operator/prometheus-operator/releases/download/$LATEST/bundle.yaml | kubectl create -f -
customresourcedefinition.apiextensions.k8s.io/alertmanagerconfigs.monitoring.coreos.com created
customresourcedefinition.apiextensions.k8s.io/alertmanagers.monitoring.coreos.com created
customresourcedefinition.apiextensions.k8s.io/podmonitors.monitoring.coreos.com created
...
...

$  kubectl get all
NAME                                       READY   STATUS    RESTARTS   AGE
pod/prometheus-operator-57df45d67c-x2h4t   1/1     Running   0          3m18s

NAME                          TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)    AGE
service/kubernetes            ClusterIP   10.96.0.1    <none>        443/TCP    5h15m
service/prometheus-operator   ClusterIP   None         <none>        8080/TCP   3m18s

NAME                                  READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prometheus-operator   1/1     1            1           3m18s

NAME                                             DESIRED   CURRENT   READY   AGE
replicaset.apps/prometheus-operator-57df45d67c   1         1         1       3m18s
```

> Do the further configuration of Prometheus service accounts, cluster role, prometheus instance, etc. found here https://blog.container-solutions.com/prometheus-operator-beginners-guide. Most importantly, create the service monitor for the gaiad service:
```
$ kubectl apply -f prometheus.yaml
serviceaccount/prometheus created
clusterrole.rbac.authorization.k8s.io/prometheus created
clusterrolebinding.rbac.authorization.k8s.io/prometheus created
prometheus.monitoring.coreos.com/prometheus created
servicemonitor.monitoring.coreos.com/prometheus unchanged

$ kubectl get prometheus
kubectl get prometheus
NAME         VERSION   DESIRED   READY   RECONCILED   AVAILABLE   AGE
prometheus                       1       True         True        52s

$ kubectl get prometheus
NAME         VERSION   DESIRED   READY   RECONCILED   AVAILABLE   AGE
prometheus                       1       True         True        71s

$ kubectl get pods
NAME                                   READY   STATUS    RESTARTS   AGE
prometheus-operator-57df45d67c-x2h4t   1/1     Running   0          130m
prometheus-prometheus-0                2/2     Running   0
```

> Pull up the Prometheus instance and confirm that it's scraping the gaiad endpoints you recently configured
```
$ kubectl get service
NAME                  TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)    AGE
kubernetes            ClusterIP   10.96.0.1    <none>        443/TCP    7h24m
prometheus-operated   ClusterIP   None         <none>        9090/TCP   2m42s
prometheus-operator   ClusterIP   None         <none>        8080/TCP   132m

$ kubectl port-forward svc/prometheus-operated 9090:9090
Forwarding from 127.0.0.1:9090 -> 9090
Forwarding from [::1]:9090 -> 9090
Handling connection for 9090
```

And bring up http://localhost:9090/ in your browser.
