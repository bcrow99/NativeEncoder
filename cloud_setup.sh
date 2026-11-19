#!/bin/bash
# cloud_setup.sh -- runs run_scale on a rented Linux machine by itself: paste
# this whole file as the machine's startup script ("user data" on AWS,
# "cloud-init" elsewhere) when you launch it, from an Ubuntu image. It
# installs a JDK, gcc and make, downloads NativeEncoder.zip from GitHub
# (bcrow99/NativeEncoder) and scrubjay.jpg (bcrow99/TestImages), and runs
# native/run_scale.sh on it. When it's done, the results are in
#   /home/ubuntu/NativeEncoder/native/scale_results_<machine>.txt
# (and everything it printed in /home/ubuntu/run_scale.log), and the file
# /home/ubuntu/DONE appears. Copy the results back, e.g.
#   scp -i key.pem ubuntu@<address>:NativeEncoder/native/scale_results_*.txt .
# then terminate the machine (stopping it still bills for its disk).
#
# It takes a few minutes to set up, then 10 to 20 for run_scale on 96 cores.
# While it runs: ssh in and  tail -f /home/ubuntu/run_scale.log
set -e
HOME_DIR=/home/ubuntu
LOG=$HOME_DIR/run_scale.log
exec > >(tee -a "$LOG") 2>&1
echo "Started $(date)"

# The tools: a JDK (headless is enough: run_scale opens no windows), gcc,
# make, unzip.
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q openjdk-21-jdk-headless build-essential unzip curl

# The code and the image, as the ubuntu user (so the files are its own).
sudo -u ubuntu bash -s <<'AS_UBUNTU'
set -e
cd /home/ubuntu
curl -fsSL -o NativeEncoder.zip https://raw.githubusercontent.com/bcrow99/NativeEncoder/main/NativeEncoder.zip \
	|| curl -fsSL -o NativeEncoder.zip https://raw.githubusercontent.com/bcrow99/NativeEncoder/master/NativeEncoder.zip
unzip -q -o NativeEncoder.zip
curl -fsSL -o scrubjay.jpg https://raw.githubusercontent.com/bcrow99/TestImages/main/scrubjay.jpg \
	|| curl -fsSL -o scrubjay.jpg https://raw.githubusercontent.com/bcrow99/TestImages/master/scrubjay.jpg
chmod +x NativeEncoder/native/run_scale.sh
# A 16 GB heap: plenty for the frame (it needs about 3), where half of a big
# machine's memory, all touched at the start, would only make each run slow
# to start. (The later -Xms and -Xmx are the ones Java uses.)
JAVA_OPTS="-Xms16g -Xmx16g" NativeEncoder/native/run_scale.sh /home/ubuntu/scrubjay.jpg
AS_UBUNTU

echo "Finished $(date)"
touch $HOME_DIR/DONE
