# Docker基础知识

### 容器概述

- 一种虚拟化的方案
- 操作系统级别的虚拟化
- 只能运行相同或相似的内核操作系统
- 依赖于Linux内核特性：Namespace和Cgroups（Control Group）



#### docker概述

Docker是C/S架构的程序：Docker客户端向Docker服务器端，也就是Docker的守护进程发出请求，守护进程处理完所有的请求工作并返回结果。

Docker 客户端对服务器端的访问既可以是本地也可以通过远程来访问。



**镜像（Image）**

镜像是Docker容器的基石，容器基于镜像启动和运行。镜像就好比容器的源代码，保存了用于启动容器的各种条件。

**容器（Container）**

容器通过镜像来启动，Docker的容器是Docker的执行来源，容器中可以运行客户的一个或多个进程，如果说镜像是Docker生命周期中的构建和打包阶段，那么容器则是启动和执行阶段。

**仓库（Repository）**

docker用仓库来保存用户构建的镜像，仓库分为公有和私有两种,Docker公司提供了一个公有的仓库Docker Hub。



## 基本操作

#### 启动docker服务

systemctl restart docker.service



#### 查看docker运行状态

systemctl status docker.service



#### 启动一到多个停止的容器

docker start



#### 使用docker启动一个新的容器

docker run



#### 显示容器的资源使用情况

docker stats



#### 删除一到多个容器

docker rm 



#### 显示镜像列表

docker images



#### 从仓库拉取镜像

docker pull [OPTIONS] NAME[:TAG|@DIGEST]

docker pull centos:centos6



#### 推送镜像到仓库

docker push [OPTIONS] NAME[:TAG]

docker push centos:centos6



#### 给镜像打标签

docker tag SOURCE_IMAGE[:TAG] TARGET_IMAGE[:TAG]



#### 保存centos镜像到centos_images.tar 文件

$ docker save  -o centos_images.tar centos:centos6



#### 从文件载入镜像

docker load --input 文件



#### 查看某个容器运行日志

docker logs -f -t  --tail 10 container_id



#### 停止某个（多个）容器

docker stop container_id/container_name ...(可同时接多个容器)



#### 查看当前docker的所有运行容器

docker ps



#### 查看历史创建过的容器

docker ps -a



#### 查看某个容器的运行配置

docker inspect container_id/container_name



#### 从容器导出镜像

docker export -o test.tar container_id



#### 将从容器导出的镜像重新导入docker

docker import test.tar repository

例如：

```
docker import  my_ubuntu_v3.tar runoob/ubuntu:v4  
```

```
docker images runoob/ubuntu:v4
```

#### 通过镜像的id来删除指定镜像

```
docker rmi <image id>
```

#### 删除所有已经停止的容器

```
docker rm $(docker ps -a -q)
```



参考链接：

<https://blog.51cto.com/13698036/2401544>

<https://www.runoob.com/w3cnote/docker-clear-command.html>

