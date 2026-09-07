# lc-forge

A personally maintained conda/rattler-build recipe repository for collecting, adapting, and building software packages.

Main contents:

- `recipes/`: Recipes that have passed build validation.
- `todo/`: Recipes waiting to be built or fixed; GitHub Actions primarily monitors this directory.
- `scripts/`: Local preparation, conversion, rendering, and build scripts.
- `conda_build_config.yaml`: Global build matrix, pinning, and default configuration.
- `output/`: Local build output, ignored by Git.

The default dependency channel is `https://prefix.dev/scns`. CI currently builds for `linux-64` and `linux-aarch64`, using GCC 11.2.0 and a CentOS 7.9 environment by default to preserve glibc 2.17 compatibility as much as possible.

## Environment Setup

Using pixi to install the build tools is recommended:

```bash
./scripts/setup_pixi.sh
```

To use the prebuilt Docker image:

```bash
./scripts/start_img.sh [--force] [tag]
```

When the container starts, it automatically injects `HOST_UID` / `HOST_GID`. Together with `fix_output_owner` in `cbuild.sh` / `rbuild.sh`, this keeps the owner of the `output/` directory consistent with the host user. The default image and container name can be overridden with the `IMAGE_REPO` and `CONTAINER_NAME` environment variables.

## Recipe Workflow

Prepare a new recipe:

```bash
./scripts/prep.sh <package_name>
```

The script copies the recipe from the conda-forge feedstock to `todo/<package_name>` and, when available, attempts to convert `meta.yaml` to `recipe.yaml`.

After `todo/<package_name>` is committed, GitHub Actions builds it. If the build fails, continue modifying the recipe under `todo/`; after a successful build, archive it under `recipes/`:

```bash
mkdir -p recipes
git mv todo/<package_name> recipes/<package_name>
```

## Common Commands

Convert a legacy-format recipe:

```bash
./scripts/crm.sh -r todo/<package>
```

Render a recipe:

```bash
./scripts/crender.sh -r todo/<package>
./scripts/rrender.sh -r todo/<package>
```

Build a recipe locally:

```bash
./scripts/rbuild.sh -r todo/<package>
./scripts/cbuild.sh -r todo/<package>
```

All recipe scripts use `-r <recipe_dir>` to specify the recipe directory. Append `-f` to force a rebuild, or `-c <channel>` to add an extra channel. You can also use the `EXTRA_CHANNELS` environment variable (space- or comma-separated) to add channels consistently. Arguments after `--` are passed through to the underlying tool. Build output is written to `output/` by default (override with `OUTPUT_DIR`); GitHub Actions remains the authority for official results.

```bash
./scripts/rbuild.sh -r todo/<package> -c conda-forge -- --verbose
EXTRA_CHANNELS="conda-forge,bioconda" ./scripts/rrender.sh -r todo/<package>
```

## Script Reference

| Script | Purpose |
| --- | --- |
| `setup_pixi.sh` | Install pixi and common build tools; safe to run repeatedly. |
| `start_img.sh` | Start the `ghcr.io/fsslc/pixi:<tag>` container. |
| `prep.sh` | Prepare a recipe from a conda-forge feedstock. |
| `crm.sh` | Convert `meta.yaml` to `recipe.yaml`. |
| `crender.sh` | Render a recipe with `conda render`. |
| `rrender.sh` | Render a recipe with `rattler-build --render-only`. |
| `cbuild.sh` | Build a recipe with `conda build`. |
| `rbuild.sh` | Build a recipe with `rattler-build`. |
| `lib/common.sh` | Shared script logic, including path resolution, channels, and CRM conversion. |

## Maintenance Notes

- Before committing, check the source, license, tests, run exports, and pinning.
- `scripts/prep.sh` accesses the network and may overwrite an existing `todo/<package_name>`.
- `scripts/setup_pixi.sh` updates the current user's `~/.bashrc` / `~/.zshrc` (PATH and completion).
- After modifying scripts, run the syntax check:

```bash
for f in scripts/*.sh scripts/lib/*.sh; do bash -n "$f" || exit 1; done
```
