#!/bin/bash
set -e  # 出错即退出，增强健壮性
exec > /var/log/spark-worker-install.log 2>&1

echo "=============================="
echo "🚀 Starting Spark Worker Installation"
echo "=============================="

# 1. 安装依赖（Java、SSH工具）
echo "🔧 Step 1: Installing OpenJDK 11 + SSH 依赖..."
apt update -y
apt install -y openjdk-11-jdk openssh-server pdsh
echo "✅ Java + SSH 依赖安装完成"

# 2. 创建 spark 用户
echo "👤 Step 2: Creating spark user..."
id spark &>/dev/null || useradd -m -s /bin/bash spark
echo "✅ Spark user created"

# 3. 安装 Spark
echo "📦 Step 3: Installing Spark..."
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

# 4. 配置环境变量（并修复权限）
echo "⚙️ Step 4: Configuring environment variables..."
cat > /home/spark/.bashrc << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export SPARK_HOME=/home/spark/spark
export PATH=$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin
EOF
chown spark:spark /home/spark/.bashrc  # 修复所有者
echo "✅ 环境变量配置完成"

# 5. 配置 spark-env.sh（并修复权限）
echo "⚙️ Step 5: Configuring spark-env.sh..."
MASTER_IP=$(nslookup spark-master | grep "Address: " | tail -n 1 | awk '{print $2}')
cat > $SPARK_HOME/conf/spark-env.sh << EOF
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export SPARK_MASTER_HOST=$MASTER_IP
export SPARK_MASTER_PORT=7077
export SPARK_WORKER_MEMORY=2g
export SPARK_WORKER_CORES=1
EOF
chown spark:spark $SPARK_HOME/conf/spark-env.sh  # 修复权限
echo "✅ spark-env.sh 配置完成"

# 6. 准备 SSH 目录（供 Master 免密登录）
echo "🔑 Step 6: Preparing SSH directory..."
su - spark -c "
  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
  touch ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
  echo '✅ authorized_keys file created'  
"
echo "✅ SSH 目录准备完成"

echo "=============================="
echo "🎉 Spark Worker 安装完成！"
echo "=============================="
echo "✅ Spark Worker installation completed! Ready for remote start."