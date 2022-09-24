# ansible 部署 kubernetes

使用 ansible 部署 kebernetes 版本集群

- [ansible 部署 kubernetes](#ansible-部署-kubernetes)
  - [机器规划](#机器规划)
  - [支持系统](#支持系统)
  - [环境准备](#环境准备)
    - [配置静态 IP](#配置静态-ip)
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
  - [kubernetes 测试](#kubernetes-测试)
    - [测试域名解析](#测试域名解析)
      - [dig 测试](#dig-测试)
      - [pod 测试](#pod-测试)
    - [测试应用部署](#测试应用部署)
      - [创建 namespace](#创建-namespace)
      - [创建 deployment](#创建-deployment)
  - [附录](#附录)
    - [关闭 swap](#关闭-swap)
    - [合并 /home 分区到 / 分区](#合并-home-分区到--分区)
    - [systemd 资源控制](#systemd-资源控制)
  - [References](#references)

## 机器规划

示例：

| Role                  |   Host   |       IP       |    K8S |
| :-------------------- | :------: | :------------: | -----: |
| ansible_client        | client00 | 10.128.170.230 |        |
| k8s_master            | master01 | 10.128.170.231 | 1.23.6 |
| k8s_master            | master02 | 10.128.170.232 | 1.23.6 |
| k8s_master            | master03 | 10.128.170.233 | 1.23.6 |
| k8s_worker            | worker01 | 10.128.170.21  | 1.23.6 |
| k8s_worker            | worker02 | 10.128.170.22  | 1.23.6 |
| k8s_worker            | worker03 | 10.128.170.23  | 1.23.6 |
| local_registry_server | registry | 10.128.170.235 |        |

ansible_client 是 ansible 的控制节点，用于部署 k8s 集群，它不是必需的，你可以在 ansible_client 节点执行部署命令，也可以在任意一个 k8s_master 节点上执行部署命令。

**注意：在 k8s_master 节点上执行部署命令时，需要将 hosts.ini 文件中的 ansible_client 节点注释掉。**

local_registry_server 是本地镜像仓库节点，如果想要使用已有的本地镜像仓库，可以在清单文件中指定。

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

```shell
chmod +x setup_ansible.sh && ./setup_ansible.sh --ssh-password "root password"
```

该脚本将会安装 ansible，同时设置节点间免密登录。

### 一键部署

```shell
ansible-playbook -i hosts.ini playbooks/90.setup.yml
```

### 分步部署

#### 设置基础环境

```shell
ansible-playbook -i hosts.ini playbooks/01.prepare.yml
```

**注意：命令执行完后会自动重启系统使配置生效，需等待系统重启完成后才能继续后续步骤。**

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
  ansible-playbook -i hosts.ini playbooks/05.network.yml
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

## kubernetes 测试

### 测试域名解析

#### dig 测试

```shell
➜ dnf/yum install bind-utils -y

➜ dig -t A www.baidu.com @10.96.0.10 +short

www.a.shifen.com.
182.61.200.6
182.61.200.7
```

#### pod 测试

```shell
➜ kubectl run -it --rm --image=busybox:1.28.3 -- sh

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
➜ kubectl create namespace dev

namespace/dev created

➜ kubectl get namespace

NAME              STATUS   AGE
default           Active   15h
dev               Active   15s
kube-node-lease   Active   15h
kube-public       Active   15h
kube-system       Active   15h
```

#### 创建 deployment

```shell
➜ cat > ~/nginx-deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-pod
  template:
    metadata:
      labels:
        app: nginx-pod
    spec:
      containers:
      - name: nginx
        image: nginx:latest
EOF

➜ kubectl apply -f ~/nginx-deployment.yaml

deployment.apps/nginx-deployment created

➜ kubectl get pod -n dev

NAME                                READY   STATUS    RESTARTS   AGE
nginx-deployment-7d4578b56c-cndrb   1/1     Running   0          48s
```

创建 service

```shell
➜ cat > ~/nginx-service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: dev
spec:
  selector:
    app: nginx-pod
  type: NodePort
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30001
EOF

➜ kubectl apply -f ~/nginx-service.yaml

service/nginx-service created

➜ kubectl get svc -n dev

NAME            TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
nginx-service   NodePort   10.108.42.72    <none>        80:30001/TCP   17s
```

测试服务访问

```shell
➜ curl 10.128.170.20:30001 -I

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
  [root@dev235 ansible-k8s]# systemctl status top.service
  ● top.service - top
     Loaded: loaded (/usr/lib/systemd/system/top.service; disabled; vendor preset: disabled)
     Active: active (running) since Thu 2022-09-08 00:27:48 CST; 11s ago
   Main PID: 20056 (top)
     CGroup: /kubernetes.slice/top.service
             └─20056 /usr/bin/top -b

  ...
  [root@dev235 ansible-k8s]# systemctl status kubernetes.slice
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

## References

[https://github.com/ralish/bash-script-template](https://github.com/ralish/bash-script-template)
