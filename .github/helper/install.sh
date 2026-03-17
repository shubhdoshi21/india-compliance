#!/bin/bash

set -e

# Check for merge conflicts before proceeding
python -m compileall -f "${GITHUB_WORKSPACE}"
if grep -lr --exclude-dir=node_modules "^<<<<<<< " "${GITHUB_WORKSPACE}"
    then echo "Found merge conflicts"
    exit 1
fi

cd ~ || exit

echo "Setting Up System Dependencies..."

sudo apt update

sudo apt remove mysql-server mysql-client
sudo apt install libcups2-dev redis-server mariadb-client

install_whktml() {
    wget -O /tmp/wkhtmltox.deb https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
    sudo apt install /tmp/wkhtmltox.deb
}
install_whktml &
wkpid=$!

pip install frappe-bench

githubbranch=${GITHUB_BASE_REF:-${GITHUB_REF##*/}}
frappeuser=${FRAPPE_USER:-"frappe"}
frappecommitish=${FRAPPE_BRANCH:-${BRANCH_TO_CLONE:-$githubbranch}}

mkdir frappe
pushd frappe
git init
git remote add origin "https://github.com/${frappeuser}/frappe"
git fetch origin "${frappecommitish}" --depth 1
git checkout FETCH_HEAD
popd

bench init --skip-assets --frappe-path ~/frappe --python "$(which python)" frappe-bench

mkdir ~/frappe-bench/sites/test_site

cp -r "${GITHUB_WORKSPACE}/.github/helper/site_config.json" ~/frappe-bench/sites/test_site/


mariadb --host 127.0.0.1 --port 3306 -u root -ptravis -e "
SET GLOBAL character_set_server = 'utf8mb4';
SET GLOBAL collation_server = 'utf8mb4_unicode_ci';

CREATE USER 'test_resilient'@'localhost' IDENTIFIED BY 'test_resilient';
CREATE DATABASE test_resilient;
GRANT ALL PRIVILEGES ON \`test_resilient\`.* TO 'test_resilient'@'localhost';

FLUSH PRIVILEGES;
"

cd ~/frappe-bench || exit

sed -i 's/watch:/# watch:/g' Procfile
sed -i 's/schedule:/# schedule:/g' Procfile
sed -i 's/socketio:/# socketio:/g' Procfile
sed -i 's/redis_socketio:/# redis_socketio:/g' Procfile

erpnextuser=${ERPNEXT_USER:-"frappe"}
erpnextcommitish=${ERPNEXT_BRANCH:-${BRANCH_TO_CLONE:-$githubbranch}}

mkdir erpnext
pushd erpnext
git init
git remote add origin "https://github.com/${erpnextuser}/erpnext"
git fetch origin "${erpnextcommitish}" --depth 1
git checkout FETCH_HEAD
popd

bench get-app erpnext ~/frappe-bench/erpnext --resolve-deps
bench get-app india_compliance "${GITHUB_WORKSPACE}"
bench setup requirements --dev

wait $wkpid

bench use test_site
bench start &
bench reinstall --yes

bench --verbose install-app india_compliance
bench --site test_site add-to-hosts

