# Justfile Recipes Reference

Key recipes from `ublue-os/image-template`-style Justfiles (used in `huruNagus-ublue`, `huruNagus-hyprland2`, etc.).

## Build recipes

| Recipe | What it does |
|--------|--------------|
| `just build [target_image=image_name] [tag=default_tag]` | podman build with OCI labels ( ArtifactHub + OCI metadata ) |
| `just rebuild-qcow2 [target_image=localhost/name] [tag=default_tag]` | build container image + `_build-bib` for qcow2 |
| `just rebuild-raw [target_image=localhost/name] [tag=default_tag]` | build + raw disk image |
| `just rebuild-iso [target_image=localhost/name] [tag=default_tag]` | build + ISO image |
| `just run-vm-qcow2 [target_image=localhost/name] [tag=default_tag]` | run a VM from the qcow2 image |
| `just run-vm-iso [target_image=localhost/name] [tag=default_tag]` | run a VM from the ISO image |

## Rechunk recipes

| Recipe | What it does |
|--------|--------------|
| `just ostree-rechunk [target_image=image_name] [tag=default_tag]` | use `rpm-ostree chunked-oci` for smaller delta updates (needs root) |
| `just rechunk [target_image=image_name] [tag=default_tag]` | alternative rechunk using `chunkah` (podman) |

## Tagging recipes

| Recipe | What it does |
|--------|--------------|
| `just tag-images [target_image=image_name] [tag=default_tag] [tags="..."]` | create multiple tags from one image |
| `just generate-default-tag [tag=default_tag]` | echo the default tag |
| `just generate-build-tags [target_image=image_name] [tag=default_tag]` | generate tag list (git SHA + date variants) |

## General recipes

| Recipe | What it does |
|--------|--------------|
| `just check` | check Just syntax on all .just files |
| `just fix` | fix Just syntax on all .just files |
| `just clean` | clean build artifacts |
| `just lint` | run shellcheck on all bash scripts |