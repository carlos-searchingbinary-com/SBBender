#!/bin/bash
# Build MLX Metal shaders into metallib for command-line execution
# SwiftPM cannot compile Metal shaders natively — this is required for MLX

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

METAL_DIR="$PROJECT_DIR/.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"
MLX_KERNELS="$PROJECT_DIR/.build/checkouts/mlx-swift/Source/Cmlx/mlx/mlx/backend/metal/kernels"
OUTPUT_DIR="/tmp/mlx_metal_build"
DEBUG_DIR="$PROJECT_DIR/.build/arm64-apple-macosx/debug"

echo "Building MLX Metal shaders..."

if [ ! -d "$METAL_DIR" ]; then
    echo "Error: Metal shader directory not found. Run 'swift build' first."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "Compiling Metal shaders..."
cd "$METAL_DIR"
for f in $(find . -name "*.metal" -type f); do
    name=$(basename "$f" .metal)
    echo "  $name.metal"
    xcrun -sdk macosx metal -c -I. -I"$MLX_KERNELS" -ffast-math "$f" -o "$OUTPUT_DIR/${name}.air" 2>/dev/null
done

echo "Linking metallib..."
cd "$OUTPUT_DIR"
xcrun -sdk macosx metallib *.air -o default.metallib

echo "Created: $OUTPUT_DIR/default.metallib ($(du -h default.metallib | cut -f1))"

if [ -d "$DEBUG_DIR" ]; then
    cp "$OUTPUT_DIR/default.metallib" "$DEBUG_DIR/"
    cp "$OUTPUT_DIR/default.metallib" "$DEBUG_DIR/mlx.metallib"
    echo "Copied metallib to debug directory"
fi

echo "Done! You can now run: swift run SwarmDemo"
