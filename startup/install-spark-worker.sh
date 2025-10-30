#!/bin/bash
set -e
exec > /var/log/spark-worker-install.log 2>&1

echo "===== 开始安装Spark Worker ====="

# 1. 安装依赖
echo "步骤1：安装Java和SSH"
apt update -y
apt install -y openjdk-11-jdk openssh-server
systemctl enable --now ssh
echo "Java版本：$(java -version 2>&1 | head -1)"

# 2. 创建spark用户
echo "步骤2：创建spark用户"
id spark &>/dev/null || useradd -m -s /bin/bash spark
echo "spark用户ID：$(id -u spark)"

# 3. 安装Spark
echo "步骤3：安装Spark 3.4.1"
SPARK_HOME="/home/spark/spark"
if [ ! -d "$SPARK_HOME" ]; then
  su - spark -c "
    wget -q https://dlcdn.apache.org/spark/spark-3.4.1/spark-3.4.1-bin-hadoop3.tgz
    tar -xzf spark-3.4.1-bin-hadoop3.tgz
    mv spark-3.4.1-bin-hadoop3 spark
    rm spark-3.4.1-bin-hadoop3.tgz
  "
fi
chown -R spark:spark /home/spark/spark

# 4. 配置环境变量
echo "步骤4：配置环境变量"
su - spark -c "
  cat >> ~/.bashrc << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export SPARK_HOME=/home/spark/spark
export PATH=\$PATH:\$SPARK_HOME/bin:\$SPARK_HOME/sbin
EOF
"

# 5. 配置Spark
echo "步骤5：配置spark-env.sh"
su - spark -c "
  cp \$SPARK_HOME/conf/spark-env.sh.template \$SPARK_HOME/conf/spark-env.sh
  cat >> \$SPARK_HOME/conf/spark-env.sh << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export SPARK_MASTER_HOST=spark-master
export SPARK_MASTER_PORT=7077
export SPARK_WORKER_MEMORY=2g
export SPARK_WORKER_CORES=1
EOF
"

# 6. 准备SSH目录（等待Master公钥）
echo "步骤6：初始化SSH目录"
su - spark -c "
  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
  touch ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
"

echo "===== Spark Worker安装完成 ====="