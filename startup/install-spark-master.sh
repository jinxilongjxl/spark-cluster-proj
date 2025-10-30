#!/bin/bash
set -e  # 出错即退出，增强健壮性
exec > /var/log/spark-master-install.log 2>&1

echo "=============================="
echo "🚀 Starting Spark Master Installation"
echo "=============================="

# 1. 安装依赖（Java、SSH工具）
echo "🔧 Step 1: Installing OpenJDK 11 + SSH 依赖..."
apt update -y
apt install -y openjdk-11-jdk openssh-server pdsh
echo "✅ Java + SSH 依赖安装完成: $(java -version 2>&1 | head -1)"

# 2. 创建 spark 用户
echo "👤 Step 2: Creating spark user..."
id spark &>/dev/null || useradd -m -s /bin/bash spark
echo "✅ Spark user created"

# 3. 安装 Spark
echo "📦 Step 3: Installing Spark 3.4.1..."
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

# 4. 配置环境变量（并修复权限）
echo "⚙️ Step 4: Configuring environment variables..."
cat > /home/spark/.bashrc << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export SPARK_HOME=/home/spark/spark
export PATH=$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin
export PDSH_RCMD_TYPE=ssh
EOF
chown spark:spark /home/spark/.bashrc  # 修复所有者
echo "✅ .bashrc configured"

# 5. 配置 spark-env.sh（并修复权限）
echo "⚙️ Step 5: Configuring spark-env.sh..."
cat > $SPARK_HOME/conf/spark-env.sh << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export SPARK_MASTER_HOST=$(hostname -i)
export SPARK_MASTER_PORT=7077
export SPARK_WORKER_MEMORY=2g
export SPARK_WORKER_CORES=1
EOF
chown spark:spark $SPARK_HOME/conf/spark-env.sh  # 修复权限
echo "✅ spark-env.sh updated"

# 6. 生成 Master 自身的 SSH 密钥（用于 localhost 免密 + 分发到 Worker）
echo "🔑 Step 6: Generating SSH key for cluster communication..."
su - spark -c "
  echo 'Generating SSH key pair...'
  ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa -q  # 无密码生成密钥
  # 检查公钥是否生成成功
  if [ ! -f ~/.ssh/id_rsa.pub ]; then
    echo '❌ Failed to generate SSH public key'
    exit 1  # 生成失败则脚本退出，避免后续步骤无效
  fi
  chmod 700 ~/.ssh
  cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
  echo '✅ SSH key generated for localhost'
"

# 7. 启动 Spark（添加重试和状态检查）
echo "🚀 Step 7: Starting Spark services with restart on failure..."
cat > /tmp/start-spark.sh << 'EOF'
#!/bin/bash
source /home/spark/.bashrc

# 配置参数
WORKERS=("spark-worker-1" "spark-worker-2")  # 需与Terraform中worker名称一致
PORTS=("8081")  # Worker Web UI 端口
MAX_RETRIES=5   # 单次检测最大尝试次数
RETRY_DELAY=10  # 每次尝试间隔10秒
MAX_RESTARTS=1  # 最大重启次数

# 初始启动 Spark Master
echo "Starting initial Spark Master..."
start-master.sh

# 定义端口检测函数（参数：worker, port）
check_port() {
  local worker=$1
  local port=$2
  local retry_count=0
  
  while [ $retry_count -lt $MAX_RETRIES ]; do
    echo "Checking $worker:$port (attempt $((retry_count+1))/$MAX_RETRIES)..."
    if nc -z $worker $port; then
      echo "$worker:$port is ready"
      return 0  # 成功
    fi
    retry_count=$((retry_count+1))
    sleep $RETRY_DELAY
  done
  
  # 达到最大重试次数，返回失败
  echo "Error: $worker:$port failed after $MAX_RETRIES attempts"
  return 1
}

# 主检测逻辑（带重启机制）
restart_count=0
all_ready=0

while [ $restart_count -le $MAX_RESTARTS ]; do
  all_ready=1  # 假设所有端口就绪
  
  # 检测所有 Worker 的端口
  for worker in "${WORKERS[@]}"; do
    for port in "${PORTS[@]}"; do
      if ! check_port $worker $port; then
        all_ready=0  # 标记有端口未就绪
        break  # 跳出当前端口循环
      fi
    done
    if [ $all_ready -eq 0 ]; then
      break  # 跳出当前 Worker 循环
    fi
  done
  
  # 所有端口就绪，退出循环
  if [ $all_ready -eq 1 ]; then
    echo "✅ All ports are ready"
    break
  fi
  
  # 未就绪且未达最大重启次数，重启 Master 并重试
  if [ $restart_count -lt $MAX_RESTARTS ]; then
    restart_count=$((restart_count+1))
    echo "🔄 Restarting Spark Master (restart $restart_count/$MAX_RESTARTS)..."
    stop-master.sh
    start-master.sh
    echo "Restarted Spark Master, rechecking ports..."
  else
    # 达最大重启次数仍失败，退出
    echo "❌ Failed after $MAX_RESTARTS restarts. Aborting."
    exit 1
  fi
done

echo "✅ Spark Master service is fully ready at $(date)"
EOF

chmod +x /tmp/start-spark.sh
su - spark -c "/tmp/start-spark.sh"
echo "✅ Spark services started with restart on failure"