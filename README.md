# Flux Service

Our specific goal is to be able to run network latency tests across nodes for different cases. A more general goal that this will enable is using Flux will provide a service to run functions or tasks for Kubernetes. The Python library that will be developed should be possible to do the same for any environment.

## Usage

To install to your cluster, you should create it first! There is an [example](example) provided using kind:

```bash
kind create cluster --config ./example/kind-config.yaml
```

Then install the daemonset. 

```bash
kubectl apply -f ./daemonset-installer.yaml
```

## How does this work?

1. We use a daemonset and nsenter to enter the init process of the node
2. We install flux core and sched from conda forge
3. The rbac / roles and service account given to the daemonset give it permission to list node
4. With the node addresses, we can prepare a broker configuration
5. The daemonset launches a script that installs and configures flux
6. The brokers start on each node!

The scripts are built into the container, so if you need to update or change something, just do it there.
Note that a systemd example install is included in [docker](docker) but we cannot use it yet because the conda installs don't support systemd.


## Debugging

I've added a script that makes it easy to shell in and debug. You can look at the logs to see the first in the host list - this is the lead broker. In the log above, it's `kind-worker`. Get the pod associated with it:

```bash
$ kubectl get pods -o wide
NAME                 READY   STATUS    RESTARTS   AGE     IP           NODE           NOMINATED NODE   READINESS GATES
install-flux-266zk   1/1     Running   0          4m43s   172.18.0.3   kind-worker4   <none>           <none>
install-flux-2sqq6   1/1     Running   0          4m43s   172.18.0.5   kind-worker    <none>           <none>
install-flux-7d5ps   1/1     Running   0          4m43s   172.18.0.4   kind-worker2   <none>           <none>
install-flux-ql9w9   1/1     Running   0          4m43s   172.18.0.6   kind-worker3   <none>           <none>
```

You can either shell into the associated daemonset pods and run nsenter:

```bash
# Enter the lead broker pod
nsenter -t 1 -m bash
./flux-connect.sh
flux run -N 2 -n 2 /osu-micro-benchmarks-5.8/mpi/pt2pt/osu_latency
flux run -N 1 -n 2 netmark -w 10 -t 20 -c 100 -b 0 -s
flux run -N 2 -n 2 netmark -w 10 -t 20 -c 100 -b 0 -s
```

Or use the kubectl node-shell plugin (which does the same)

```bash
kubectl node-shell kind-worker
```

Run the script that the daemonset prepares to connect to the broker:

```bash
 ./flux-connect.sh 
root@kind-worker:/# flux resource list
     STATE NNODES   NCORES    NGPUS NODELIST
      free      4       32        0 kind-worker,kind-worker[2-4]
 allocated      0        0        0 
      down      0        0        0 
```

Boum! Bing badda... boom! 💥

## License

HPCIC DevTools is distributed under the terms of the MIT license.
All new contributions must be made under this license.

See [LICENSE](https://github.com/converged-computing/cloud-select/blob/main/LICENSE),
[COPYRIGHT](https://github.com/converged-computing/cloud-select/blob/main/COPYRIGHT), and
[NOTICE](https://github.com/converged-computing/cloud-select/blob/main/NOTICE) for details.

SPDX-License-Identifier: (MIT)

LLNL-CODE- 842614

