#!/bin/bash
set -e

echo "===== 开始安装 Spark Master ====="

# 步骤1：更新系统包
echo "步骤1：更新系统包"
sudo apt-get update -y
sudo apt-get upgrade -y

# 步骤2：安装 Java（Spark 依赖）
echo "步骤2：安装 Java"
sudo apt-get install openjdk-11-jdk -y
echo "Java 版本："
java -version

# 步骤3：下载并解压 Spark
echo "步骤3：下载并解压 Spark"
SPARK_VERSION="3.4.1"
HADOOP_VERSION="3.3"
wget https://dlcdn.apache.org/spark/spark-$SPARK_VERSION/spark-$SPARK_VERSION-bin-hadoop$HADOOP_VERSION.tgz -P /tmp
sudo tar -xzf /tmp/spark-$SPARK_VERSION-bin-hadoop$HADOOP_VERSION.tgz -C /opt
sudo ln -s /opt/spark-$SPARK_VERSION-bin-hadoop$HADOOP_VERSION /opt/spark

# 步骤4：配置环境变量
echo "步骤4：配置环境变量"
cat << EOF | sudo tee -a /etc/profile
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export SPARK_HOME=/opt/spark
export PATH=\$PATH:\$SPARK_HOME/bin:\$SPARK_HOME/sbin
EOF
source /etc/profile
echo "Spark 版本："
spark-submit --version

# 步骤5：配置 Spark Master
echo "步骤5：配置 Spark Master"
sudo mkdir -p /opt/spark/conf
cat << EOF | sudo tee /opt/spark/conf/spark-env.sh
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export SPARK_MASTER_HOST=$(hostname -i)
export SPARK_MASTER_PORT=7077
export SPARK_WORKER_MEMORY=2g
export SPARK_WORKER_CORES=1
EOF

# 步骤6：启动 Spark Master
echo "步骤6：启动 Spark Master"
sudo $SPARK_HOME/sbin/start-master.sh
echo "Spark Master 启动状态："
sudo $SPARK_HOME/sbin/master-status.sh

echo "===== Spark Master 安装完成 ====="