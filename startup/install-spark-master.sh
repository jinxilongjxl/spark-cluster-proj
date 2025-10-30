#!/bin/bash
set -e  
exec > /var/log/spark-master-install.log 2>&1

echo "=============================="
echo "🚀 Starting Spark Master Installation"
echo "=============================="

# 步骤1：更新系统包
echo "🔧 Step 1: Updating system packages..."
apt update -y
apt upgrade -y
echo "✅ System packages updated"

# 步骤2：安装 Java + 依赖
echo "🔧 Step 2: Installing OpenJDK 11..."
apt install -y openjdk-11-jdk
echo "✅ Java installed: $(java -version 2>&1 | head -1)"

# 步骤3：创建 spark 用户
echo "👤 Step 3: Creating spark user..."
id spark &>/dev/null || useradd -m -s /bin/bash spark
echo "✅ spark user created"

# 步骤4：安装 Spark
echo "📦 Step 4: Installing Spark 3.4.1..."
SPARK_HOME="/home/spark/spark"
if [ ! -d "$SPARK_HOME" ]; then
  su - spark -c "
    cd /home/spark
    echo '📥 Downloading Spark...'
    wget -q https://dlcdn.apache.org/spark/spark-3.4.1/spark-3.4.1-bin-hadoop3.tgz || exit 1
    echo '🔍 Extracting Spark...'
    tar -xzf spark-3.4.1-bin-hadoop3.tgz || exit 1
    mv spark-3.4.1-bin-hadoop3 spark
    echo '✅ Spark installed successfully.'
  "
else
  echo "✅ Spark already installed"
fi

# 步骤5：配置环境变量（并修复权限）
echo "⚙️ Step 5: Configuring environment variables..."
cat > /home/spark/.bashrc << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export SPARK_HOME=/home/spark/spark
export PATH=$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin
EOF
chown spark:spark /home/spark/.bashrc  # 修复所有者
echo "✅ .bashrc configured"

# 步骤6：配置 spark-env.sh（并修复权限）
echo "⚙️ Step 6: Configuring spark-env.sh..."
cat >> $SPARK_HOME/conf/spark-env.sh << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export SPARK_MASTER_HOST=$(hostname -i)
export SPARK_MASTER_PORT=7077
export SPARK_WORKER_MEMORY=2g
export SPARK_WORKER_CORES=1
EOF
chown spark:spark $SPARK_HOME/conf/spark-env.sh  # 修复权限
echo "✅ spark-env.sh updated"

# 步骤7：生成 spark 用户的 SSH 密钥（用于免密登录）
echo "🔑 Step 7: Generating SSH key for spark user..."
su - spark -c "
  echo 'Generating SSH key pair...'
  ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa -q  # 无密码生成密钥
  # 检查公钥是否生成成功
  if [ ! -f ~/.ssh/id_rsa.pub ]; then
    echo '❌ Failed to generate SSH public key'
    exit 1  # 生成失败则脚本退出
  fi
  chmod 700 ~/.ssh
  cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
  echo '✅ SSH key generated for localhost'
"

# 步骤8：启动 Spark Master（以 spark 用户运行）
echo "🚀 Step 8: Starting Spark Master..."
su - spark -c "$SPARK_HOME/sbin/start-master.sh"
echo "✅ Spark Master started"

echo "=============================="
echo "🎉 Spark Master Installation Completed!"
echo "=============================="