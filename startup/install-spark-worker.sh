#!/bin/bash
set -e

echo "===== 开始安装 Spark Worker ====="

# 步骤1：更新系统包
echo "步骤1：更新系统包"
sudo apt-get update -y
sudo apt-get upgrade -y

# 步骤2：安装 Java
echo "步骤2：安装 Java"
sudo apt-get install openjdk-11-jdk -y
echo "Java 版本："
java -version

# 步骤3：创建 spark 用户
echo "步骤3：创建 spark 用户"
sudo useradd -m -s /bin/bash spark
echo "spark 用户创建完成，ID：$(id -u spark)"

# 步骤4：下载并解压 Spark
echo "步骤4：下载并解压 Spark"
SPARK_VERSION="3.4.1"
HADOOP_VERSION="3.3"
wget https://dlcdn.apache.org/spark/spark-$SPARK_VERSION/spark-$SPARK_VERSION-bin-hadoop$HADOOP_VERSION.tgz -P /tmp
sudo tar -xzf /tmp/spark-$SPARK_VERSION-bin-hadoop$HADOOP_VERSION.tgz -C /opt
sudo ln -s /opt/spark-$SPARK_VERSION-bin-hadoop$HADOOP_VERSION /opt/spark

# 步骤5：修改 Spark 目录权限
echo "步骤5：修改 Spark 目录权限"
sudo chown -R spark:spark /opt/spark-$SPARK_VERSION-bin-hadoop$HADOOP_VERSION
sudo chown -h spark:spark /opt/spark

# 步骤6：配置环境变量
echo "步骤6：配置环境变量"
cat << EOF | sudo tee -a /etc/profile
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export SPARK_HOME=/opt/spark
export PATH=\$PATH:\$SPARK_HOME/bin:\$SPARK_HOME/sbin
EOF
source /etc/profile
echo "Spark 版本："
spark-submit --version

# 步骤7：配置 Spark Worker（关联 Master 节点）
echo "步骤7：配置 Spark Worker"
sudo -u spark mkdir -p /opt/spark/conf
MASTER_IP=$(nslookup spark-master | grep "Address: " | tail -n 1 | awk '{print $2}')
cat << EOF | sudo tee /opt/spark/conf/spark-env.sh
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export SPARK_MASTER_HOST=$MASTER_IP
export SPARK_MASTER_PORT=7077
export SPARK_WORKER_MEMORY=2g
export SPARK_WORKER_CORES=1
EOF
sudo chown spark:spark /opt/spark/conf/spark-env.sh

# 步骤8：以 spark 用户启动 Spark Worker
echo "步骤8：启动 Spark Worker（spark 用户）"
sudo -u spark $SPARK_HOME/sbin/start-worker.sh spark://$MASTER_IP:7077
echo "Spark Worker 启动状态："
ps -ef | grep -i "spark\.worker" | grep -v grep  # 检查进程用户

echo "===== Spark Worker 安装完成 ====="