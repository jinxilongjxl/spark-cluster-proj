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

# 3. 安装Spark 3.5.7（显示进度条，禁用安静模式）
echo "步骤3：安装Spark 3.5.7"
SPARK_HOME="/home/spark/spark"
SPARK_TAR="spark-3.5.7-bin-hadoop3.tgz"
SPARK_URL="https://dlcdn.apache.org/spark/spark-3.5.7/$SPARK_TAR"
# 备用源（国内加速）
BACKUP_URL="https://mirrors.aliyun.com/apache/spark/spark-3.5.7/$SPARK_TAR"

if [ ! -d "$SPARK_HOME" ]; then
  su - spark -c "
    cd /home/spark
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
    rm -f $SPARK_TAR  # 清理安装包
    echo '✅ Spark安装成功'
  "
else
  echo "✅ Spark已安装，跳过此步骤"
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