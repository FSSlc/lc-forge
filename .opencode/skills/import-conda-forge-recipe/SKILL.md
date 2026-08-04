---
name: import-conda-forge-recipe
description: Import a package from conda-forge, convert to rattler-build recipe, build in Docker, fix errors, and land it in recipes/
license: MIT
compatibility: opencode
metadata:
  workflow: import-build-land
---

Import a package from conda-forge, convert to rattler-build format, build inside the pixi Docker container, fix errors, and land it.

## Workflow

```
prep.sh (outside) → start_img.sh → inside container: build (cbuild/rbuild) → fix → exit → commit
```

### 1. Import (outside container)

```bash
./scripts/prep.sh <pkg>
```

- Clones `conda-forge/<pkg>-feedstock` into `todo/<pkg>`
- Converts `meta.yaml` → `recipe.yaml` if possible
- If conversion fails, appends `<pkg>` to `only-meta.txt` (fallback to `conda build`)

### 2. Start Docker container

```bash
./scripts/start_img.sh
```

This starts `ghcr.io/fsslc/pixi:latest` with the repo mounted at the same path and `HOST_UID`/`HOST_GID` set so output files have the correct owner.

### 3. Build (inside container)

Once inside the container shell, determine which tool to use:

- `todo/<pkg>/recipe.yaml` exists → **rattler-build** (`./scripts/rbuild.sh`)
- Only `meta.yaml` exists → **conda build** (`./scripts/cbuild.sh`)

```bash
# Rattler-build (primary, recipe.yaml)
./scripts/rbuild.sh -r todo/<pkg>

# Conda build (fallback, meta.yaml only)  
./scripts/cbuild.sh -r todo/<pkg>

# Force rebuild
./scripts/rbuild.sh -r todo/<pkg> -f

# With extra channels
./scripts/rbuild.sh -r todo/<pkg> -c conda-forge
EXTRA_CHANNELS="conda-forge,bioconda" ./scripts/rbuild.sh -r todo/<pkg>
```

### 4. Fix errors

If the build fails, exit the container, edit the recipe files in `todo/<pkg>` (outside container), then re-enter the container and build again:

```bash
exit                                            # exit container
# edit todo/<pkg>/recipe.yaml or meta.yaml
./scripts/start_img.sh                          # re-enter container
./scripts/rbuild.sh -r todo/<pkg> -f            # force rebuild
```

Common issues and fixes:

| Symptom | Likely cause | Fix |
|---|---|---|
| `recipe.yaml` conversion failed | `crm` couldn't handle the `meta.yaml` | Manually fix `recipe.yaml` or keep `meta.yaml` (append to `only-meta.txt`, use `cbuild.sh`) |
| Missing build deps | Recipe needs channels beyond `scns` | Add `-c conda-forge` or set `EXTRA_CHANNELS` |
| Source download fails | URL changed, git tag missing | Update source URL/hash in recipe |
| Pinning mismatch | Version pinned differently in `conda_build_config.yaml` | Align versions or add override in recipe's `conda_build_config.yaml` |
| Compiler/linker errors | Missing `-DCMAKE_...` flags, missing pkg-config deps | Add missing `build` dependencies to recipe |
| Test failures | Test commands wrong, missing test deps | Fix test section or add missing `test` dependencies |
| `run_exports` missing | Downstream packages need pinning | Add `run_exports` section |

### 5. Land the recipe

After successful build (`.conda` files appear in `output/`):

```bash
mkdir -p recipes
git mv todo/<pkg> recipes/<pkg>
git add recipes/<pkg>
git commit -m "add recipe <pkg>"
```

## CI details

- Workflows: `.github/workflows/build.yml` (auto) and `import-recipe.yml` (manual dispatch)
- On push/PR to `main` changing `todo/**`, CI builds all packages in `todo/`
- Two targets: `linux-64` and `linux-aarch64`, gcc 11, CentOS 7 (glibc 2.17)
- Default channel: `https://prefix.dev/scns`
- Builds with `rattler-build` by default; packages in `only-meta.txt` use `conda build`
- Output uploaded to `https://prefix.dev/scns`

## Quick reference

| Command | Purpose |
|---|---|
| `./scripts/prep.sh <pkg>` | Import from conda-forge |
| `./scripts/rbuild.sh -r todo/<pkg>` | Build with rattler-build |
| `./scripts/cbuild.sh -r todo/<pkg>` | Build with conda build |
| `./scripts/rrender.sh -r todo/<pkg>` | Render-only (check recipe) |
| `./scripts/crender.sh -r todo/<pkg>` | Render-only with conda |
| `./scripts/crm.sh -r todo/<pkg>` | Convert meta.yaml → recipe.yaml |
| `./scripts/start_img.sh` | Start pixi Docker container |
| `for f in scripts/*.sh scripts/lib/*.sh; do bash -n "$f" \|\| exit 1; done` | Syntax-check scripts |

---

## 中文版

从 conda-forge 导入包，转换为 rattler-build 格式，在 pixi Docker 容器内构建，修复错误，最终合入代码。

### 工作流

```
prep.sh（容器外）→ start_img.sh → 容器内：构建（cbuild/rbuild）→ 修复 → exit → 提交
```

### 1. 导入（容器外）

```bash
./scripts/prep.sh <pkg>
```

- 克隆 `conda-forge/<pkg>-feedstock` 到 `todo/<pkg>`
- 尝试将 `meta.yaml` 转换为 `recipe.yaml`
- 如果转换失败，将 `<pkg>` 追加到 `only-meta.txt`（降级使用 `conda build`）

### 2. 启动 Docker 容器

```bash
./scripts/start_img.sh
```

启动 `ghcr.io/fsslc/pixi:latest`，仓库挂载到相同路径，自动设置 `HOST_UID`/`HOST_GID` 确保输出文件属主正确。

### 3. 构建（容器内）

进入容器 shell 后，根据 recipe 格式选择工具：

- `todo/<pkg>/recipe.yaml` 存在 → **rattler-build**（`./scripts/rbuild.sh`）
- 只有 `meta.yaml` → **conda build**（`./scripts/cbuild.sh`）

```bash
# rattler-build（首选，有 recipe.yaml）
./scripts/rbuild.sh -r todo/<pkg>

# conda build（降级，仅有 meta.yaml）
./scripts/cbuild.sh -r todo/<pkg>

# 强制重建
./scripts/rbuild.sh -r todo/<pkg> -f

# 使用额外 channel
./scripts/rbuild.sh -r todo/<pkg> -c conda-forge
EXTRA_CHANNELS="conda-forge,bioconda" ./scripts/rbuild.sh -r todo/<pkg>
```

### 4. 修复错误

构建失败时，退出容器，在容器外修改 `todo/<pkg>` 中的 recipe 文件，然后重新进入容器构建：

```bash
exit                                            # 退出容器
# 编辑 todo/<pkg>/recipe.yaml 或 meta.yaml
./scripts/start_img.sh                          # 重新进入容器
./scripts/rbuild.sh -r todo/<pkg> -f            # 强制重建
```

常见问题及修复：

| 现象 | 可能原因 | 修复方法 |
|---|---|---|
| `recipe.yaml` 转换失败 | `crm` 无法处理 `meta.yaml` | 手动修复 `recipe.yaml`，或保留 `meta.yaml`（追加到 `only-meta.txt`，使用 `cbuild.sh`） |
| 缺少构建依赖 | 需要 `scns` 之外的 channel | 添加 `-c conda-forge` 或设置 `EXTRA_CHANNELS` |
| 源码下载失败 | URL 已变更、git tag 不存在 | 更新 recipe 中的 source URL/hash |
| 版本锁定不匹配 | `conda_build_config.yaml` 中版本不一致 | 对齐版本，或在 recipe 的 `conda_build_config.yaml` 中覆盖 |
| 编译/链接错误 | 缺少编译标志或 pkg-config 依赖 | 在 recipe 的 `build` 依赖中添加缺失的包 |
| 测试失败 | 测试命令错误、缺少测试依赖 | 修复 test 段或添加缺失的 `test` 依赖 |
| 缺少 `run_exports` | 下游包需要版本锁定 | 添加 `run_exports` 段 |

### 5. 合入代码

构建成功后（`output/` 中出现 `.conda` 文件）：

```bash
mkdir -p recipes
git mv todo/<pkg> recipes/<pkg>
git add recipes/<pkg>
git commit -m "add recipe <pkg>"
```
