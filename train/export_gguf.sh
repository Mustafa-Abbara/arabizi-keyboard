#!/usr/bin/env bash
# Convert a merged fine-tuned model to GGUF Q4_K_M on Kaggle (roadmap P4 step 3, ADR 0015).
#   bash train/export_gguf.sh /kaggle/working/out/<run>/merged arabizi-llama3.2-1b-v1 /kaggle/working/out/<run>
# Uses the same llama.cpp commit as the Mac's llama-server (0.6.0, build 11429, d81235049) so the file loads there.
set -euo pipefail
MERGED="$1"; NAME="$2"; OUT="$3"
LLAMA_COMMIT="d81235049"
WORK="${TMPDIR:-/tmp}/llama.cpp"

if [ ! -d "$WORK" ]; then
  git clone --quiet https://github.com/ggml-org/llama.cpp "$WORK"
fi
git -C "$WORK" checkout --quiet "$LLAMA_COMMIT"
pip install --quiet -e "$WORK/gguf-py" sentencepiece

python "$WORK/convert_hf_to_gguf.py" "$MERGED" --outtype f16 --outfile "$OUT/$NAME-f16.gguf"

cmake -S "$WORK" -B "$WORK/build" -DGGML_CUDA=OFF -DLLAMA_CURL=OFF -DLLAMA_BUILD_TESTS=OFF > /dev/null
cmake --build "$WORK/build" --target llama-quantize -j "$(nproc)" > /dev/null
"$WORK/build/bin/llama-quantize" "$OUT/$NAME-f16.gguf" "$OUT/$NAME-Q4_K_M.gguf" Q4_K_M > /dev/null
rm "$OUT/$NAME-f16.gguf"

sha256sum "$OUT/$NAME-Q4_K_M.gguf" | tee "$OUT/$NAME-Q4_K_M.gguf.sha256"
ls -l "$OUT/$NAME-Q4_K_M.gguf"
