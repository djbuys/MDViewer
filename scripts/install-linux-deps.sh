#!/usr/bin/env bash
# Installs the packages needed to build MDViewer for Linux (GTK + WPE WebKit
# for flutter_inappwebview_linux). Tested on Ubuntu 24.04.
set -euo pipefail
sudo apt-get update
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev libepoxy-dev libwpe-1.0-dev libwpebackend-fdo-1.0-dev
# Newer distributions ship the 2.0 API; Ubuntu 24.04 ships 1.1.
sudo apt-get install -y libwpewebkit-2.0-dev || sudo apt-get install -y libwpewebkit-1.1-dev
