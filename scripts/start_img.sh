#!/bin/bash

# 存储脚本所在目录的父目录（仓库根目录）并切换到该目录
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

force=0
img_tag=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force)
            force=1
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [-f|--force] [tag]"
            echo "  -f, --force   如果存在 pixi 容器则先强制删除"
            exit 0
            ;;
        *)
            if [ -z "$img_tag" ]; then
                img_tag="$1"
            else
                echo "Unknown argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [ -z "$img_tag" ]; then
    img_tag="slim"
fi

docker pull ghcr.io/fsslc/pixi:${img_tag}

if [ "$force" -eq 1 ]; then
    docker rm -f pixi 2>/dev/null || true
else
    if docker ps -a --format '{{.Names}}' | grep -xq 'pixi'; then
        echo "pixi 容器已经存在，请使用 -f|--force 来强制删除后启动。" >&2
        exit 1
    fi
fi

docker run -ti --name pixi -v "$REPO_ROOT":"$REPO_ROOT" -w "$REPO_ROOT" \
    ghcr.io/fsslc/pixi:${img_tag}
