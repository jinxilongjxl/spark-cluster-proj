#!/bin/bash
set -e
exec > /var/log/spark-master-install.log 2>&1  # 日志输出到文件

echo "===== 开始安装Spark Master ====="

# 1. 安装依赖
echo "步骤1：安装Java和SSH"
apt update -y
apt install -y openjdk-11-jdk openssh-server
systemctl enable --now ssh  # 确保SSH服务启动
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
export SPARK_MASTER_HOST=\$(hostname -i)
export SPARK_MASTER_PORT=7077
export SPARK_WORKER_MEMORY=2g
export SPARK_WORKER_CORES=1
EOF
"

# 6. 配置免密登录（本地）
echo "步骤6：生成SSH密钥"
su - spark -c "
  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
  ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa -q  # 无密码密钥
  cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
"

# 7. 启动Master
echo "步骤7：启动Spark Master"
su - spark -c "$SPARK_HOME/sbin/start-master.sh"

echo "===== Spark Master安装完成 ====="