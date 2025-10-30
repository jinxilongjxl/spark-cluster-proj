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

# 3. 安装Spark 3.5.7（硬编码路径，确保下载和解压）
echo "步骤3：安装Spark 3.5.7"
SPARK_INSTALL_DIR="/home/spark"
SPARK_HOME="$SPARK_INSTALL_DIR/spark"
SPARK_TAR="spark-3.5.7-bin-hadoop3.tgz"
SPARK_URL="https://dlcdn.apache.org/spark/spark-3.5.7/$SPARK_TAR"
BACKUP_URL="https://mirrors.aliyun.com/apache/spark/spark-3.5.7/$SPARK_TAR"

if [ ! -d "$SPARK_HOME" ]; then
  su - spark -c "
    cd $SPARK_INSTALL_DIR
    echo '📥 从主源下载Spark（显示进度）...'
    if ! wget --show-progress --retry-connrefused --waitretry=3 --read-timeout=30 --timeout=15 -t 5 $SPARK_URL; then
      echo '❌ 主源下载失败，切换到备用源...'
      if ! wget --show-progress --retry-connrefused --waitretry=3 --read-timeout=30 --timeout=15 -t 5 $BACKUP_URL; then
        echo '❌ 备用源下载也失败，请检查网络连接'
        exit 1
      fi
    fi
    echo '�解压Spark安装包...'
    if ! tar -xzf $SPARK_TAR; then
      echo '❌ 解压失败，安装包可能损坏'
      exit 1
    fi
    mv spark-3.5.7-bin-hadoop3 spark
    rm -f $SPARK_TAR
    echo '✅ Spark安装成功'
  "
else
  echo "✅ Spark已安装，跳过此步骤"
fi
chown -R spark:spark $SPARK_INSTALL_DIR/spark

# 4. 配置**永久生效**的全量环境变量（写入.bashrc，并强制加载）
echo "步骤4：配置永久环境变量"
su - spark -c "
  cat >> ~/.bashrc << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export SPARK_HOME=/home/spark/spark
export SPARK_MASTER_HOST=spark-master
export SPARK_MASTER_PORT=7077
export SPARK_WORKER_MEMORY=2g
export SPARK_WORKER_CORES=1
export PATH=\$PATH:\$SPARK_HOME/bin:\$SPARK_HOME/sbin
EOF
  # 强制加载环境变量（确保当前会话和后续SSH登录自动生效）
  source ~/.bashrc
"

# 步骤5：添加Master节点Hosts映射
echo "步骤5：添加Master节点Hosts映射"
# 尝试通过内部DNS解析Master IP
MASTER_IP=$(nslookup spark-master | grep 'Address: ' | tail -n 1 | awk '{print $2}')
if [ -z "$MASTER_IP" ]; then
  echo "❌ 内部DNS解析失败，手动指定Master IP（从Terraform输出或GCP控制台获取）"
  MASTER_IP="你的Master节点公网IP"  # 替换为实际IP
fi
echo "$MASTER_IP  spark-master" | sudo tee -a /etc/hosts
echo "✅ Master节点Hosts映射添加完成：$MASTER_IP  spark-master"

# 6. 验证环境变量加载
echo "步骤6：验证环境变量"
su - spark -c "
  echo 'JAVA_HOME: ' \$JAVA_HOME
  echo 'SPARK_HOME: ' \$SPARK_HOME
  echo 'SPARK_MASTER_HOST: ' \$SPARK_MASTER_HOST
  echo 'SPARK_MASTER_PORT: ' \$SPARK_MASTER_PORT
"

# 7. 准备SSH目录（等待Master公钥）
echo "步骤7：初始化SSH目录"
su - spark -c "
  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
  touch ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
"

# 8. 启动Spark Worker（硬编码路径+强制加载环境变量）
echo "步骤8：启动Spark Worker"
su - spark -c "
  # 强制加载最新环境变量
  source ~/.bashrc
  echo '🔗 连接到Master节点：\$SPARK_MASTER_HOST:\$SPARK_MASTER_PORT'
  # 硬编码完整启动脚本路径
  /home/spark/spark/sbin/start-worker.sh spark://\$SPARK_MASTER_HOST:\$SPARK_MASTER_PORT
  echo '✅ Spark Worker启动命令已执行，进程状态可通过jps或日志检查'
"

echo "===== Spark Worker安装及启动完成 ====="