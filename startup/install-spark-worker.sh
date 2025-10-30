#!/bin/bash
set -e
exec > /var/log/spark-worker-install.log 2>&1

echo "===== 开始安装Spark Worker ====="

# 关键：从 Terraform 注入的 metadata 中获取 Master IP（无需手动输入）
echo "步骤0：获取Master节点IP"
MASTER_IP=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/master_ip" -H "Metadata-Flavor: Google")
if [ -z "$MASTER_IP" ]; then
  echo "❌ 无法从metadata获取Master IP，安装失败"
  exit 1
fi
echo "✅ 从metadata获取Master IP：$MASTER_IP"

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

# 3. 安装Spark 3.5.7
echo "步骤3：安装Spark 3.5.7"
SPARK_HOME="/home/spark/spark"
SPARK_TAR="spark-3.5.7-bin-hadoop3.tgz"
SPARK_URL="https://dlcdn.apache.org/spark/spark-3.5.7/$SPARK_TAR"
BACKUP_URL="https://mirrors.aliyun.com/apache/spark/spark-3.5.7/$SPARK_TAR"

if [ ! -d "$SPARK_HOME" ]; then
  su - spark -c "
    cd /home/spark
    echo '📥 从主源下载Spark...'
    if ! wget --show-progress --retry-connrefused --waitretry=3 --read-timeout=30 --timeout=15 -t 5 $SPARK_URL; then
      echo '❌ 主源失败，切换备用源...'
      if ! wget --show-progress --retry-connrefused --waitretry=3 --read-timeout=30 --timeout=15 -t 5 $BACKUP_URL; then
        echo '❌ 备用源也失败'
        exit 1
      fi
    fi
    echo '�解压Spark...'
    if ! tar -xzf $SPARK_TAR; then
      echo '❌ 解压失败'
      exit 1
    fi
    mv spark-3.5.7-bin-hadoop3 spark
    rm -f $SPARK_TAR
    echo '✅ Spark安装成功'
  "
else
  echo "✅ Spark已安装"
fi
chown -R spark:spark $SPARK_HOME

# 4. 配置永久环境变量（自动注入Master IP）
echo "步骤4：配置环境变量"
su - spark -c "
  cat >> ~/.bashrc << EOF
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export SPARK_HOME=/home/spark/spark
export SPARK_MASTER_HOST=$MASTER_IP  # 动态注入Master IP
export SPARK_MASTER_PORT=7077
export SPARK_WORKER_MEMORY=2g
export SPARK_WORKER_CORES=1
export PATH=\$PATH:\$SPARK_HOME/bin:\$SPARK_HOME/sbin
EOF
  source ~/.bashrc  # 强制加载
"

# 5. 配置spark-env.sh（自动注入Master IP）
echo "步骤5：配置spark-env.sh"
su - spark -c "
  export SPARK_HOME=/home/spark/spark
  cp \$SPARK_HOME/conf/spark-env.sh.template \$SPARK_HOME/conf/spark-env.sh
  cat >> \$SPARK_HOME/conf/spark-env.sh << EOF
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export SPARK_MASTER_HOST=$MASTER_IP  # 动态注入Master IP
export SPARK_MASTER_PORT=7077
export SPARK_WORKER_MEMORY=2g
export SPARK_WORKER_CORES=1
EOF
"

# 6. 配置hosts（确保spark-master域名映射到正确IP）
echo "步骤6：配置hosts映射"
echo "$MASTER_IP  spark-master" | sudo tee -a /etc/hosts
echo "✅ hosts配置完成：$MASTER_IP spark-master"

# 7. 初始化SSH目录
echo "步骤7：初始化SSH目录"
su - spark -c "
  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
  touch ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
"

# 8. 启动Worker（使用动态获取的Master IP）
echo "步骤8：启动Spark Worker"
su - spark -c "
  source ~/.bashrc  # 再次加载环境变量确保生效
  echo '🔗 连接Master：$MASTER_IP:7077'
  /home/spark/spark/sbin/start-worker.sh spark://$MASTER_IP:7077
  # 验证进程是否启动
  if jps | grep -q Worker; then
    echo '✅ Worker进程启动成功'
  else
    echo '❌ Worker进程启动失败，查看日志：\$SPARK_HOME/logs'
    exit 1
  fi
"

echo "===== Spark Worker安装及启动完成 ====="