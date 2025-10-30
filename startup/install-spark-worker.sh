#!/bin/bash
set -e  
exec > /var/log/spark-worker-install.log 2>&1

echo "=============================="
echo "🚀 Starting Spark Worker Installation"
echo "=============================="

# 步骤1：更新系统包
echo "🔧 Step 1: Updating system packages..."
apt update -y
apt upgrade -y
echo "✅ System packages updated"

# 步骤2：安装 Java
echo "🔧 Step 2: Installing OpenJDK 11..."
apt install -y openjdk-11-jdk
echo "✅ Java installed"

# 步骤3：创建 spark 用户
echo "👤 Step 3: Creating spark user..."
id spark &>/dev/null || useradd -m -s /bin/bash spark
echo "✅ spark user created"

# 步骤4：安装 Spark
echo "📦 Step 4: Installing Spark..."
SPARK_HOME="/home/spark/spark"
if [ ! -d "$SPARK_HOME" ]; then
  su - spark -c "
    cd /home/spark
    wget -q https://dlcdn.apache.org/spark/spark-3.4.1/spark-3.4.1-bin-hadoop3.tgz
    tar -xzf spark-3.4.1-bin-hadoop3.tgz
    mv spark-3.4.1-bin-hadoop3 spark
  "
fi
echo "✅ Spark installed"

# 步骤5：配置环境变量（并修复权限）
echo "⚙️ Step 5: Configuring environment variables..."
cat > /home/spark/.bashrc << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export SPARK_HOME=/home/spark/spark
export PATH=$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin
EOF
chown spark:spark /home/spark/.bashrc  # 修复所有者
echo "✅ 环境变量配置完成"

# 步骤6：配置 spark-env.sh（并修复权限）
echo "⚙️ Step 6: Configuring spark-env.sh..."
cat >> $SPARK_HOME/conf/spark-env.sh << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export SPARK_MASTER_HOST=spark-master
export SPARK_MASTER_PORT=7077
export SPARK_WORKER_MEMORY=2g
export SPARK_WORKER_CORES=1
EOF
chown spark:spark $SPARK_HOME/conf/spark-env.sh  # 修复权限
echo "✅ spark-env.sh 配置完成"

# 步骤7：准备 SSH 目录（供 Master 免密登录）
echo "🔑 Step 7: Preparing SSH directory..."
su - spark -c "
  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
  touch ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
  echo '✅ authorized_keys file created'  
"
echo "✅ SSH 目录准备完成"

# 步骤8：启动 Spark Worker（以 spark 用户运行）
echo "🚀 Step 8: Starting Spark Worker..."
MASTER_IP=$(nslookup spark-master | grep "Address: " | tail -n 1 | awk '{print $2}')
su - spark -c "$SPARK_HOME/sbin/start-worker.sh spark://$MASTER_IP:7077"
echo "✅ Spark Worker started"

echo "=============================="
echo "🎉 Spark Worker Installation Completed!"
echo "=============================="