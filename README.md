# ansible 部署 kubernetes

使用 ansible 部署 kebernetes 集群

- [ansible 部署 kubernetes](#ansible-部署-kubernetes)
  - [机器规划](#机器规划)
  - [支持系统](#支持系统)
  - [环境准备](#环境准备)
    - [配置静态 IP](#配置静态-ip)
  - [配置文件](#配置文件)
    - [hosts.ini](#hostsini)
    - [playbooks/group_vars/all.yaml](#playbooksgroup_varsallyaml)
  - [部署步骤](#部署步骤)
    - [修改 hosts.ini 配置](#修改-hostsini-配置)
      - [高可用模式](#高可用模式)
      - [非高可用模式](#非高可用模式)
    - [安装 ansible](#安装-ansible)
    - [一键部署](#一键部署)
    - [分步部署](#分步部署)
      - [设置基础环境](#设置基础环境)
      - [安装容器运行时](#安装容器运行时)
      - [安装 kubernetes](#安装-kubernetes)
  - [节点管理](#节点管理)
    - [添加 worker](#添加-worker)
    - [移除 worker](#移除-worker)
    - [重置节点](#重置节点)
  - [kubernetes 扩展](#kubernetes-扩展)
    - [helm](#helm)
    - [nodelocaldns](#nodelocaldns)
    - [metrics-server](#metrics-server)
    - [nfs-provisioner](#nfs-provisioner)
    - [prometheus](#prometheus)
    - [dashboard](#dashboard)
  - [第三方应用](#第三方应用)
    - [harbor](#harbor)
  - [kubernetes 测试](#kubernetes-测试)
    - [测试域名解析](#测试域名解析)
      - [dig 测试](#dig-测试)
      - [pod 测试](#pod-测试)
    - [测试应用部署](#测试应用部署)
      - [创建 namespace](#创建-namespace)
      - [创建 deployment](#创建-deployment)
    - [测试 nodelocaldns](#测试-nodelocaldns)
    - [测试动态 pv](#测试动态-pv)
    - [测试 harbor](#测试-harbor)
      - [推送镜像到 harbor 仓库](#推送镜像到-harbor-仓库)
      - [测试集群使用 harbor 仓库](#测试集群使用-harbor-仓库)
      - [管理维护 harbor 服务](#管理维护-harbor-服务)
  - [附录](#附录)
    - [关闭 swap](#关闭-swap)
    - [合并 /home 分区到 / 分区](#合并-home-分区到--分区)
    - [systemd 资源控制](#systemd-资源控制)

## 机器规划

示例：

| Role            |   Host   |       IP       |    K8S |
| :-------------- | :------: | :------------: | -----: |
| k8s_master      | master01 | 10.128.170.231 | 1.23.6 |
| k8s_master      | master02 | 10.128.170.232 | 1.23.6 |
| k8s_master      | master03 | 10.128.170.233 | 1.23.6 |
| k8s_worker      | worker01 | 10.128.170.21  | 1.23.6 |
| k8s_worker      | worker02 | 10.128.170.22  | 1.23.6 |
| k8s_worker      | worker03 | 10.128.170.23  | 1.23.6 |
| ansible_client  | client00 | 10.128.170.230 |        |
| registry_server | registry | 10.128.170.235 |        |
| harbor_server   |  harbor  | 10.128.170.235 |        |
| nfs_server      |   nfs    | 10.128.170.235 |        |

- k8s_master 是集群的控制节点
- k8s_worker 是集群的工作节点
- 非高可用模式下，最少只需要两个机器就可以部署一个 k8s 集群
- ansible_client 是 ansible 的控制节点，用于部署 k8s 集群，它不是必需的，你可以在 ansible_client 节点执行部署命令，也可以在任意一个 k8s_master 节点上执行部署命令
- registry_server 是本地镜像仓库节点，用于加速集群部署镜像下载，它不是必需的，如果想要使用已有的本地镜像仓库，可以在清单文件中指定
- harbor_server 是 harbor 镜像仓库节点，用于提供企业级容器镜像管理服务，它不是必需的，如果想要安装和使用 harbor，需要在清单文件中提供配置然后执行安装命令
- nfs 是网络文件系统，允许系统将其目录和文件共享给网络上的其他系统，它不是必需的，启用 k8s 集群扩展 nfs-provisioner 时需要指定 nfs 服务器地址

## 支持系统

- [x] CentOS Linux 7.9
- [x] Rocky Linux 8.6

系统镜像地址：

- [CentOS-7-x86_64-Minimal-2009.iso](https://mirror.tuna.tsinghua.edu.cn/centos/7.9.2009/isos/x86_64/CentOS-7-x86_64-Minimal-2009.iso)
- [Rocky-8.6-x86_64-minimal.iso](https://download.rockylinux.org/pub/rocky/8/isos/x86_64/Rocky-8.6-x86_64-minimal.iso)

## 环境准备

**全部机器均需要执行以下配置，具体配置内容需根据实际情况而定。**

### 配置静态 IP

编辑以下配置文件

```shell
vi /etc/sysconfig/network-scripts/ifcfg-ens18
```

文件配置修改如下

```text
TYPE=Ethernet
PROXY_METHOD=none
BROWSER_ONLY=no
BOOTPROTO=static
DEFROUTE=yes
IPV4_FAILURE_FATAL=no
IPV6INIT=yes
IPV6_AUTOCONF=yes
IPV6_DEFROUTE=yes
IPV6_FAILURE_FATAL=no
NAME=ens18
UUID=65cccf47-7fbb-4263-bedb-ec07ffe462d7
DEVICE=ens18
ONBOOT=yes
IPADDR=10.128.170.231
NETMASK=255.255.255.0
GATEWAY=10.128.170.254
DNS1=114.114.114.114
DNS2=8.8.8.8
```

重启网络服务

```shell
systemctl restart NetworkManager
```

查看 IP 地址

```shell
[root@localhost ~]# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
2: ens18: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether fe:fc:fe:5d:3f:0e brd ff:ff:ff:ff:ff:ff
    inet 10.128.170.231/24 brd 10.128.170.255 scope global noprefixroute ens18
       valid_lft forever preferred_lft forever
    inet6 fe80::fcfc:feff:fe5d:3f0e/64 scope link noprefixroute
       valid_lft forever preferred_lft forever
```

## 配置文件

一般情况下，只需要通过以下两个配置文件就可以控制集群部署行为。

- hosts.ini
- playbooks/group_vars/all.yaml

### hosts.ini

- 主机清单文件
- 包含常用全局配置

### playbooks/group_vars/all.yaml

- 集群配置文件
- 包含集群扩展配置

## 部署步骤

### 修改 hosts.ini 配置

根据规划，在清单文件中配置需要部署 k8s 的主机 IP

- k8s_master 高可用必须 3 个节点，非高可用必须 1 个节点
- k8s_worker 至少 1 个节点
- k8s_master 和 k8s_worker 节点不能重复

#### 高可用模式

- 高可用模式必须设置 `HA_ENABLE="yes"`
- `APISERVER_VIP`, `APISERVER_VMASK`, `APISERVER_VPORT` 需要根据实际情况配置

#### 非高可用模式

- 非高可用模式必须设置 `HA_ENABLE="no"`
- `APISERVER_VIP`, `APISERVER_VMASK`, `APISERVER_VPORT` 不需要配置

### 安装 ansible

只需在只执行剧本的节点执行即可，这里在 ansible_client 节点或任意 k8s_master 节点执行。

**注意：在 k8s_master 节点上执行部署命令时，需要将 hosts.ini 文件中的 ansible_client 节点注释掉。**

```shell
chmod +x setup_ansible.sh && ./setup_ansible.sh --ssh-password "root password"
```

- 该脚本将会安装 ansible，同时设置节点间免密登录。
- 该脚本默认读取当前目录的 hosts.ini 清单文件，你可以使用 `-i` 参数指定其它清单文件，例如：`-i examples/hosts.multiple-master.ini`。
- 查看详细帮助文档：`./setup_ansible.sh -h`

### 一键部署

```shell
ansible-playbook -i hosts.ini playbooks/90.setup.yml
```

### 分步部署

#### 设置基础环境

```shell
ansible-playbook -i hosts.ini playbooks/01.prepare.yml
```

**注意：命令执行完后，如果设置了 `REBOOT: "yes"`，系统将会自动重启，此时需等待系统重启完成后才能继续后续步骤。**

#### 安装容器运行时

```shell
ansible-playbook -i hosts.ini playbooks/02.runtime.yml
```

#### 安装 kubernetes

- 安装 k8s master

  ```shell
  ansible-playbook -i hosts.ini playbooks/03.k8s_master.yml
  ```

- 安装 k8s worker

  ```shell
  ansible-playbook -i hosts.ini playbooks/04.k8s_worker.yml
  ```

- 安装 k8s network

  ```shell
  ansible-playbook -i hosts.ini playbooks/05.k8s_network.yml
  ```

- 安装 k8s addon

  ```shell
  ansible-playbook -i hosts.ini playbooks/06.k8s_addon.yml
  ```

> 或者一键安装 k8s 相关组件：
>
> ```shell
> ansible-playbook -i hosts.ini playbooks/80.setup_k8s.yml
> ```

## 节点管理

### 添加 worker

**添加新的 worker 节点前，要在 host.ini 文件中添加节点配置到 `[k8s_worker]` 下，然后再执行添加命令。**

```shell
ansible-playbook -i host.ini playbooks/91.add_worker.yml -e nodes=worker03 -e ansible_ssh_pass="password"
```

参数：

- `-e nodes`: 指定要添加的 worker 节点，对应清单中的 hostname，支持指定多个 worker 节点，指定多个节点时使用英文逗号 `,` 隔开，如：`-e nodes=worker04,worker05`
- `-e ansible_ssh_pass`: 该参数是可选的，你可以在清单文件对应节点配置中加上 `ansible_ssh_pass="password"`，或者在执行命令时指定该参数。

### 移除 worker

```shell
ansible-playbook -i host.ini playbooks/92.remove_worker.yml -e nodes=worker03
```

参数：

- `-e nodes`: 指定要移除的 worker 节点，对应清单中的 hostname，支持指定多个 worker 节点，指定多个节点时使用英文逗号 `,` 隔开，如：`-e nodes=worker04,worker05`

**注意：将节点从集群中移除后，你可以根据需要选择是否重置节点，但无论有没有重置节点，你都可以随时再次添加该节点。**

### 重置节点

**注意：重置节点前，需要先将节点从集群中移除。**

```shell
ansible-playbook -i host.ini playbooks/93.reset_node.yml -e nodes=worker03
```

参数：

- `-e nodes`: 指定要重置的节点，对应清单中的 hostname，支持指定多个节点，指定多个节点时使用英文逗号 `,` 隔开，如：`-e nodes=worker04,worker05`

## kubernetes 扩展

### helm

- 默认不启用 helm 扩展
- 若要启用 helm 扩展需要设置 `HELM_ENABLE: "yes"`

### nodelocaldns

- 默认不启用 nodelocaldns 扩展
- 若要启用 nodelocaldns 扩展需要设置 `NODELOCALDNS_ENABLE: "yes"`

### metrics-server

- 默认不启用 metrics-server 扩展
- 若要启用 metrics-server 扩展需要设置 `METRICES_SERVER_ENABLE: "yes"`

启用 metrics-server 扩展后可以使用 `kubectl top` 查看 node 和 pod 的 CPU/MEMORY 使用情况：

```shell
[root@master01 ~]# kubectl top node
NAME       CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
master01   210m         5%     2201Mi          31%
worker01   159m         2%     2341Mi          15%
```

```shell
[root@master01 ~]# kubectl -n kube-system top pod
NAME                                    CPU(cores)   MEMORY(bytes)
calico-kube-controllers-fdd9b97-ggkgz   2m           31Mi
calico-node-n7qx2                       29m          180Mi
calico-node-rx8wb                       21m          169Mi
coredns-6d8c4cb4d-5wvfx                 2m           34Mi
coredns-6d8c4cb4d-ccjnc                 2m           28Mi
etcd-master01                           12m          111Mi
kube-apiserver-master01                 47m          639Mi
kube-controller-manager-master01        11m          85Mi
kube-proxy-jk9nl                        7m           28Mi
kube-proxy-t84d6                        9m           28Mi
kube-scheduler-master01                 4m           38Mi
metrics-server-6bb4988d74-s95c7         4m           21Mi
```

### nfs-provisioner

- 默认不启用 nfs-provisioner 扩展
- 若要启用 nfs-provisioner 扩展需要设置 `NFS_PROVISIONER_ENABLE: "yes"`，同时还需要设置 host.ini 中的 `NFS_SERVER` 和 `NFS_PATH`

**启用 nfs-provisioner 扩展至少需要一个 nfs 服务器，用于提供底层存储，其中 `NFS_SERVER` 是 nfs 服务器地址，`NFS_PATH` 是共享目录。**

你可以通过 host.ini 配置文件为某一主机设置 `nfs_server=yes`，这将会在对应主机自动创建一个 nfs 服务器，此时 `NFS_SERVER` 应为该主机地址。

或者你也可以根据文档 [nfs-server](https://github.com/easzlab/kubeasz/blob/master/docs/guide/nfs-server.md)，自行创建一个 nfs 服务器。

### prometheus

- 默认不启用 prometheus 扩展
- 若要启用 prometheus 扩展需要设置 `PROMETHEUS_ENABLE: "yes"`，同时还需要启用 helm 扩展，因为 prometheus 需要使用 helm 进行安装

访问 web 界面：

- prometheus: <http://MasterNodeIP:30901/>
- alertmanager: <http://MasterNodeIP:30902/>
- grafana: <http://MasterNodeIP:30903/> （默认账号/密码 admin/prom-operator）

**其中 MasterNodeIP 为任意 master 节点 IP，在高可用模式下，MasterNodeIP 还可以是 `APISERVER_VIP` 配置的 IP。**

### dashboard

- 默认启用 dashboard 扩展
- 若要关闭 dashboard 扩展需要设置 `DASHBOARD_ENABLE: "no"`

访问 web 界面：

- dashboard: <https://MasterNodeIP:30443/>
- 在任意 master 节点执行以下命令获取 token

  ```shell
  kubectl -n kubernetes-dashboard describe secret admin-user
  ```

**其中 MasterNodeIP 为任意 master 节点 IP，在高可用模式下，MasterNodeIP 还可以是 `APISERVER_VIP` 配置的 IP。**

## 第三方应用

### harbor

**注意：安装 harbor 前要先完成 k8s 集群的安装。**

- 默认不安装 harbor
- 若要安装 harbor，则需要在 hosts.ini 中配置 harbor_server，然后执行以下安装命令

  ```shell
  ansible-playbook -i hosts.ini playbooks/81.harbor.yml
  ```

**harbor 安装后，ansible 会自动配置 k8s 集群，使其能够使用 harbor 相关服务。**

访问 web 界面：

- harbor: <https://HarborServerIP:8443/> （默认账号/密码 admin/Harbor12345）

**其中 HarborServerIP 为 harbor 服务器 IP。**

## kubernetes 测试

### 测试域名解析

#### dig 测试

```shell
[root@master01 ~]# yum install bind-utils -y

[root@master01 ~]# dig -t A www.baidu.com @10.96.0.10 +short
www.a.shifen.com.
182.61.200.6
182.61.200.7
```

#### pod 测试

```shell
[root@master01 ~]# kubectl run -it --rm --image=busybox:1.28.3 -- sh
If you don't see a command prompt, try pressing enter.
/ # cat /etc/resolv.conf
nameserver 10.96.0.10
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
/ # nslookup kubernetes.default
Server:    10.96.0.10
Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local

Name:      kubernetes.default
Address 1: 10.96.0.1 kubernetes.default.svc.cluster.local
/ # ping -c 4 www.baidu.com
PING www.baidu.com (182.61.200.6): 56 data bytes
64 bytes from 182.61.200.6: seq=0 ttl=52 time=6.860 ms
64 bytes from 182.61.200.6: seq=1 ttl=52 time=6.592 ms
64 bytes from 182.61.200.6: seq=2 ttl=52 time=6.488 ms
64 bytes from 182.61.200.6: seq=3 ttl=52 time=7.288 ms

--- www.baidu.com ping statistics ---
4 packets transmitted, 4 packets received, 0% packet loss
round-trip min/avg/max = 6.488/6.807/7.288 ms
```

### 测试应用部署

#### 创建 namespace

```shell
[root@master01 ~]# kubectl create namespace dev
namespace/dev created

[root@master01 ~]# kubectl get namespace
NAME              STATUS   AGE
default           Active   15h
dev               Active   15s
kube-node-lease   Active   15h
kube-public       Active   15h
kube-system       Active   15h
```

#### 创建 deployment

```shell
[root@master01 ~]# cat > ~/nginx-deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: dev
  labels:
    app: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
EOF

[root@master01 ~]# kubectl apply -f ~/nginx-deployment.yaml
deployment.apps/nginx-deployment created

[root@master01 ~]# kubectl get pod -n dev
NAME                                READY   STATUS    RESTARTS   AGE
nginx-deployment-7d4578b56c-cndrb   1/1     Running   0          48s
```

创建 service

```shell
[root@master01 ~]# cat > ~/nginx-service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: dev
spec:
  selector:
    app: nginx
  type: NodePort
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30001
EOF

[root@master01 ~]# kubectl apply -f ~/nginx-service.yaml
service/nginx-service created

[root@master01 ~]# kubectl get svc -n dev
NAME            TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
nginx-service   NodePort   10.108.42.72    <none>        80:30001/TCP   17s
```

测试服务访问

```shell
[root@master01 ~]# curl 10.128.170.20:30001 -I
HTTP/1.1 200 OK
Server: nginx/1.21.5
Date: Mon, 12 Sep 2022 05:44:38 GMT
Content-Type: text/html
Content-Length: 615
Last-Modified: Tue, 28 Dec 2021 15:28:38 GMT
Connection: keep-alive
ETag: "61cb2d26-267"
Accept-Ranges: bytes

```

### 测试 nodelocaldns

查看 pod：

```shell
[root@master01 ~]# kubectl -n kube-system get pod -o wide | grep dns
coredns-6d8c4cb4d-plcpv                 1/1     Running   0          25m   10.244.5.2       worker01   <none>           <none>
coredns-6d8c4cb4d-z7sxs                 1/1     Running   0          25m   10.244.5.1       worker01   <none>           <none>
node-local-dns-rtxrw                    1/1     Running   0          18m   10.128.170.21    worker01   <none>           <none>
node-local-dns-vgjh6                    1/1     Running   0          18m   10.128.170.231   master01   <none>           <none>
```

查看 service：

```shell
[root@master01 ~]# kubectl -n kube-system get svc -o wide | grep dns
kube-dns            ClusterIP   10.96.0.10      <none>        53/UDP,53/TCP,9153/TCP   26m   k8s-app=kube-dns
kube-dns-upstream   ClusterIP   10.111.10.191   <none>        53/UDP,53/TCP            19m   k8s-app=kube-dns
node-local-dns      ClusterIP   None            <none>        9253/TCP                 19m   k8s-app=node-local-dns
```

查看 Corefile：

```shell
[root@master01 ~]# kubectl -n kube-system exec -it node-local-dns-rtxrw -- /bin/sh
# cat /etc/Corefile
cluster.local:53 {
    errors
    cache {
            success 9984 30
            denial 9984 5
    }
    reload
    loop
    bind 169.254.20.10 10.96.0.10
    forward . 10.111.10.191 {
            force_tcp
    }
    prometheus :9253
    health 169.254.20.10:8080
    }
in-addr.arpa:53 {
    errors
    cache 30
    reload
    loop
    bind 169.254.20.10 10.96.0.10
    forward . 10.111.10.191 {
            force_tcp
    }
    prometheus :9253
    }
ip6.arpa:53 {
    errors
    cache 30
    reload
    loop
    bind 169.254.20.10 10.96.0.10
    forward . 10.111.10.191 {
            force_tcp
    }
    prometheus :9253
    }
.:53 {
    errors
    cache 30
    reload
    loop
    bind 169.254.20.10 10.96.0.10
    forward . /etc/resolv.conf
    prometheus :9253
    }
#
```

测试域名解析：

```shell
[root@master01 ~]# kubectl run -it --rm --image=busybox:1.28.3 -- sh
If you don't see a command prompt, try pressing enter.
/ # cat /etc/resolv.conf
nameserver 169.254.20.10
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
/ # nslookup kubernetes.default
Server:    169.254.20.10
Address 1: 169.254.20.10

Name:      kubernetes.default
Address 1: 10.96.0.1 kubernetes.default.svc.cluster.local
/ # nslookup www.baidu.com
Server:    169.254.20.10
Address 1: 169.254.20.10

Name:      www.baidu.com
Address 1: 14.215.177.38
Address 2: 14.215.177.39
/ #
```

### 测试动态 pv

在第一个 master 节点 ~/kubernetes/addon/nfs_provisioner/ 有个测试例子 test-pod.yaml。

部署测试 pod：

```shell
[root@master01 ~]# kubectl apply -f ~/kubernetes/addon/nfs_provisioner/test-pod.yaml
persistentvolumeclaim/test-claim created
pod/test-pod created
```

验证测试 pod：

```shell
[root@master01 ~]# kubectl get pod
NAME       READY   STATUS      RESTARTS   AGE
test-pod   0/1     Completed   0          99s
```

验证自动创建的 pv 资源：

```shell
[root@master01 ~]# kubectl get pv
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                STORAGECLASS   REASON   AGE
pvc-1395d76c-ea04-4deb-bcb2-f18eb1a726de   2Mi        RWX            Delete           Bound    default/test-claim   nfs-storage             2m37s
```

验证 PVC 已经绑定成功：（STATUS 字段为 Bound）

```shell
[root@master01 ~]# kubectl get pvc
NAME         STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
test-claim   Bound    pvc-1395d76c-ea04-4deb-bcb2-f18eb1a726de   2Mi        RWX            nfs-storage    4m17s
```

另外，Pod 启动完成后，会在挂载的目录中创建一个 `SUCCESS` 文件。我们可以到 NFS 服务器去看下：

```shell
[root@localhost nfs]# pwd
/opt/data/nfs
[root@localhost nfs]# tree
.
└── default-test-claim-pvc-1395d76c-ea04-4deb-bcb2-f18eb1a726de
    └── SUCCESS

1 directory, 1 file
```

如上，可以发现挂载的时候，nfs-client 根据 PVC 自动创建了一个目录，我们 Pod 中挂载的 `/mnt`，实际引用的就是该目录，而我们在 `/mnt` 下创建的 `SUCCESS` 文件，也自动写入到了这里。

### 测试 harbor

<https://github.com/easzlab/kubeasz/blob/master/docs/guide/harbor.md>

#### 推送镜像到 harbor 仓库

**你可以在任意一个安装了 docker 的机器上进行以下测试，只要它能够连接 harbor 服务器，根据你的实际情况，你可能需要手动配置 /etc/hosts。**

拉取 nginx 镜像：

```shell
[root@loaclhost ~]# docker pull nginx:latest
latest: Pulling from library/nginx
e9995326b091: Pull complete
71689475aec2: Pull complete
f88a23025338: Pull complete
0df440342e26: Pull complete
eef26ceb3309: Pull complete
8e3ed6a9e43a: Pull complete
Digest: sha256:943c25b4b66b332184d5ba6bb18234273551593016c0e0ae906bab111548239f
Status: Downloaded newer image for nginx:latest
docker.io/library/nginx:latest
```

给 nginx 镜像打 tag：

```shell
[root@loaclhost ~]# docker tag nginx:latest harbor.local:8443/library/nginx:latest
[root@loaclhost ~]# docker images
REPOSITORY                        TAG       IMAGE ID       CREATED       SIZE
nginx                             latest    76c69feac34e   2 days ago    142MB
harbor.local:8443/library/nginx   latest    76c69feac34e   2 days ago    142MB
...
```

登录 harbor：

```shell
[root@loaclhost ~]# docker login harbor.local:8443
Username: admin
Password:
WARNING! Your password will be stored unencrypted in /root/.docker/config.json.
Configure a credential helper to remove this warning. See
https://docs.docker.com/engine/reference/commandline/login/#credentials-store

Login Succeeded
```

登录时如果提示如下错误：

```shell
[root@loaclhost ~]# docker login harbor.local:8443
Username: admin
Password:
Error response from daemon: Get "https://harbor.local:8443/v2/": x509: certificate signed by unknown authority
```

则需要设置 docker 信任该 CA 证书机构，具体操作如下：

<https://docs.docker.com/engine/security/certificates/>

- 创建受信任的 CA 证书目录

  ```shell
  mkdir -p /etc/docker/certs.d/harbor.local:8443
  ```

  其中 `harbor.local:8443` 需要根据实际部署 harbor 的配置进行调整。

- 拷贝 harbor 的 CA 证书到上面创建的目录下

  ```shell
  cp /opt/data/harbor/ssl/ca.crt /etc/docker/certs.d/harbor.local\:8443
  ```

  使用本工具安装的 harbor，默认 CA 证书在对应服务器的 /opt/data/harbor/ssl 目录下。
  如果你是在其它机器的 docker 上操作，那么你需要通过 scp 命令或其它手段将 harbor 的 CA 证书拷贝到相应目录。

- 重启 docker

  ```shell
  systemctl restart docker
  ```

推送镜像到 harbor：

```shell
[root@loaclhost ~]# docker push harbor.local:8443/library/nginx:latest
The push refers to repository [harbor.local:8443/library/nginx]
a2e59a79fae0: Pushed
4091cd312f19: Pushed
9e7119c28877: Pushed
2280b348f4d6: Pushed
e74d0d8d2def: Pushed
a12586ed027f: Pushed
latest: digest: sha256:06aa2038b42f1502b59b3a862b1f5980d3478063028d8e968f0810b9b0502380 size: 1570
```

#### 测试集群使用 harbor 仓库

**你可以在任意一个 k8s_master 节点执行以下测试。**

```shell
[root@master01 ~]# cat > ~/nginx-deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: harbor.local:8443/library/nginx:latest
        ports:
        - containerPort: 80
EOF

[root@master01 ~]# kubectl apply -f ~/nginx-deployment.yaml
deployment.apps/nginx-deployment created

[root@master01 ~]# kubectl get pod
NAME                                READY   STATUS    RESTARTS   AGE
nginx-deployment-7c997c9c5d-6h22t   1/1     Running   0          29s

[root@master01 ~]# kubectl get event
LAST SEEN   TYPE     REASON              OBJECT                                   MESSAGE
2m12s       Normal   Scheduled           pod/nginx-deployment-7c997c9c5d-6h22t    Successfully assigned default/nginx-deployment-7c997c9c5d-6h22t to worker03
2m11s       Normal   Pulling             pod/nginx-deployment-7c997c9c5d-6h22t    Pulling image "harbor.local:8443/library/nginx:latest"
2m5s        Normal   Pulled              pod/nginx-deployment-7c997c9c5d-6h22t    Successfully pulled image "harbor.local:8443/library/nginx:latest" in 5.589854087s
2m5s        Normal   Created             pod/nginx-deployment-7c997c9c5d-6h22t    Created container nginx
2m5s        Normal   Started             pod/nginx-deployment-7c997c9c5d-6h22t    Started container nginx
2m12s       Normal   SuccessfulCreate    replicaset/nginx-deployment-7c997c9c5d   Created pod: nginx-deployment-7c997c9c5d-6h22t
2m12s       Normal   ScalingReplicaSet   deployment/nginx-deployment              Scaled up replica set nginx-deployment-7c997c9c5d to 1
```

#### 管理维护 harbor 服务

<https://goharbor.io/docs/2.6.0/install-config/reconfigure-manage-lifecycle/>

暂停与恢复：

- 暂停 harbor（docker 容器 stop，并不删除容器）

  ```shell
  docker-compose -f /opt/data/harbor/harbor/docker-compose.yml stop
  ```

- 恢复 harbor（恢复 docker 容器运行）

  ```shell
  docker-compose -f /opt/data/harbor/harbor/docker-compose.yml start
  ```

**提示：你可以直接进入到 harbor 安装目录 /opt/data/harbor/harbor 执行命令，这样你就不必每次使用 `-f` 参数指定 docker-compose 配置文件了。**

更新 compose 配置：

- 进入 harbor 安装目录

  ```shell
  cd /opt/data/harbor/harbor
  ```

- 停止 harbor（停止并删除 docker 容器）

  ```shell
  docker-compose down -v
  ```

- 更新 harbor.yml 配置文件

- 生成新的 docker-compose.yml 配置文件

  ```shell
  ./prepare
  ```

  或者

  ```shell
  ./prepare --with-notary --with-trivy --with-chartmuseum
  ```

- 启动 harbor（创建并运行 docker 容器）

  ```shell
  docker-compose up -d
  ```

查看详细帮助文档：

- `docker-compose -h`

## 附录

### 关闭 swap

临时关闭

```shell
swapoff -a
```

永久关闭（重启生效）

```shell
sed -i 's/^\/dev\/mapper\/rl-swap/#&/' /etc/fstab
```

### 合并 /home 分区到 / 分区

- 合并前查看分区

  ```shell
  [root@master01 ~]# df -h
  Filesystem           Size  Used Avail Use% Mounted on
  devtmpfs             3.8G     0  3.8G   0% /dev
  tmpfs                3.8G     0  3.8G   0% /dev/shm
  tmpfs                3.8G  8.5M  3.8G   1% /run
  tmpfs                3.8G     0  3.8G   0% /sys/fs/cgroup
  /dev/mapper/rl-root   70G  2.5G   68G   4% /
  /dev/mapper/rl-home   50G  383M   49G   1% /home
  /dev/sda1           1014M  188M  827M  19% /boot
  tmpfs                777M     0  777M   0% /run/user/0
  ```

- 卸载 /home

  ```shell
  [root@master01 ~]# umount /home
  ```

- 取消开机自检 /home

  ```shell
  [root@master01 ~]# sed -i 's/^\/dev\/mapper\/rl-home/#&/' /etc/fstab
  ```

- 删除 /home 所在的 lv

  ```shell
  [root@master01 ~]# lvremove /dev/mapper/rl-home
  Do you really want to remove active logical volume rl/home? [y/n]: y
    Logical volume "home" successfully removed.
  ```

- 扩展 /root 所在的 lv

  ```shell
  [root@master01 ~]# lvextend -l +100%FREE /dev/mapper/rl-root
    Size of logical volume rl/root changed from 70.00 GiB (17920 extents) to 119.10 GiB (30490 extents).
    Logical volume rl/root successfully resized.
  ```

- 扩展 /root 文件系统

  ```shell
  [root@master01 ~]# xfs_growfs /dev/mapper/rl-root
  meta-data=/dev/mapper/rl-root    isize=512    agcount=4, agsize=4587520 blks
           =                       sectsz=512   attr=2, projid32bit=1
           =                       crc=1        finobt=1, sparse=1, rmapbt=0
           =                       reflink=1    bigtime=0 inobtcount=0
  data     =                       bsize=4096   blocks=18350080, imaxpct=25
           =                       sunit=0      swidth=0 blks
  naming   =version 2              bsize=4096   ascii-ci=0, ftype=1
  log      =internal log           bsize=4096   blocks=8960, version=2
           =                       sectsz=512   sunit=0 blks, lazy-count=1
  realtime =none                   extsz=4096   blocks=0, rtextents=0
  data blocks changed from 18350080 to 31221760
  ```

- 合并后查看分区

  ```shell
  [root@master01 ~]# df -h
  Filesystem           Size  Used Avail Use% Mounted on
  devtmpfs             3.8G     0  3.8G   0% /dev
  tmpfs                3.8G     0  3.8G   0% /dev/shm
  tmpfs                3.8G  8.5M  3.8G   1% /run
  tmpfs                3.8G     0  3.8G   0% /sys/fs/cgroup
  /dev/mapper/rl-root  120G  2.8G  117G   3% /
  /dev/sda1           1014M  188M  827M  19% /boot
  tmpfs                777M     0  777M   0% /run/user/0
  ```

### systemd 资源控制

- [systemd.slice](http://www.jinbuguo.com/systemd/systemd.slice.html)
- [systemd.resource-control](http://www.jinbuguo.com/systemd/systemd.resource-control.html)
- [systemd.unit](http://www.jinbuguo.com/systemd/systemd.unit.html)
- [systemd.service](http://www.jinbuguo.com/systemd/systemd.service.html)
- [从 init 系统说起](https://www.cnblogs.com/sparkdev/p/8448237.html)
- [Cgroups 与 Systemd](https://www.cnblogs.com/sparkdev/p/9523194.html)
- [systemd攻略之三：如何利用systemd控制cgroup,实战](https://developer.aliyun.com/article/810635)
- [Systemd and Cgroup](https://www.sobyte.net/post/2022-09/systemd-and-cgroup/)

通过将 cgroup 层级系统与 systemd unit 树绑定，systemd 可以把资源管理的设置从进程级别移至应用程序级别。

- 创建一个 slice

  ```shell
  cat >/usr/lib/systemd/system/kubernetes.slice <<"EOF"
  [Unit]
  Description=kubernetes slice
  DefaultDependencies=no
  Wants=-.slice

  [Slice]
  EOF
  ```

- 启动 slice

  ```shell
  systemctl daemon-reload
  systemctl start kubernetes.slice
  ```

- 查看 slice 状态

  ```shell
  [root@localhost ~]# systemctl status kubernetes.slice
  ● kubernetes.slice - kubernetes slice
     Loaded: loaded (/usr/lib/systemd/system/kubernetes.slice; static; vendor preset: disabled)
     Active: active since Thu 2022-09-08 00:09:12 CST; 7s ago

  Sep 08 00:09:12 localhost systemd[1]: Created slice kubernetes slice.
  ```

- 创建一个 service

  ```shell
  cat >/usr/lib/systemd/system/top.service <<"EOF"
  [Unit]
  Description=top

  [Service]
  ExecStart=/usr/bin/top -b
  Slice=kubernetes.slice

  [Install]
  WantedBy=multi-user.target
  EOF
  ```

- 启动 service

  ```shell
  systemctl daemon-reload
  systemctl start top.slice
  ```

- 查看 service 状态

  ```shell
  [root@localhost ~]# systemctl status top.service
  ● top.service - top
     Loaded: loaded (/usr/lib/systemd/system/top.service; disabled; vendor preset: disabled)
     Active: active (running) since Thu 2022-09-08 00:27:48 CST; 11s ago
   Main PID: 20056 (top)
     CGroup: /kubernetes.slice/top.service
             └─20056 /usr/bin/top -b

  ...
  [root@localhost ~]# systemctl status kubernetes.slice
  ● kubernetes.slice - kubernetes slice
     Loaded: loaded (/usr/lib/systemd/system/kubernetes.slice; static; vendor preset: disabled)
     Active: active since Thu 2022-09-08 00:26:09 CST; 3min 11s ago
     CGroup: /kubernetes.slice
             └─top.service
               └─20056 /usr/bin/top -b

  ...
  ```

- 查看 systemctl status

  ```shell
  [root@localhost ~]# systemctl status
  ● localhost
      State: running
       Jobs: 0 queued
     Failed: 0 units
      Since: Thu 2022-08-18 15:21:06 CST; 2 weeks 6 days ago
     CGroup: /
             ├─1 /usr/lib/systemd/systemd --switched-root --system --deserialize 22
             ├─kubernetes.slice
             │ └─top.service
             │   └─20056 /usr/bin/top -b
             ├─user.slice
             │ └─user-0.slice
             ...
             └─system.slice
               ├─rsyslog.service
               │ └─1745 /usr/sbin/rsyslogd -n
               ...
  ```
