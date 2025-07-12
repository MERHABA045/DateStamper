#!/bin/zsh
set -euo pipefail

# 処理フォルダの取得＆UNDOスクリプトの作成
target_dir="$1"
undo_script="$target_dir/undo_rename_$(date +%Y%m%d%H%M%S).sh"

echo '#!/bin/zsh' > "$undo_script"
echo '' >> "$undo_script"
echo 'SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"' >> "$undo_script"
echo 'cd "$SCRIPT_DIR" || {' >> "$undo_script"
echo '	echo "ディレクトリ移動に失敗：$SCRIPT_DIR" >&2' >> "$undo_script"
echo '	exit 1' >> "$undo_script"
echo '}' >> "$undo_script"
echo '' >> "$undo_script"
chmod +x "$undo_script"

# 同一ファイルチェック（サイズ→ハッシュ）
echo "\n🔍️同一ファイルチェック開始……"

typeset -A size_groups
typeset -A duplicate_groups

# --2階層までチェック（全階層を確認する場合は「-maxdepth 2」を削除
# --ステップ1：サイズ単位でグループ化
find "$target_dir" -maxdepth 2 \
		\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.heic' -o -iname '*.mov' -o -iname '*.mp4' \) \
		-type f | while read -r file; do
	size=$(stat -f%z "$file")
	size_groups[$size]="${size_groups[$size]:-} $file"
done

# --ステップ2：サイズが同じファイルグループをハッシュ比較
for size in ${(k)size_groups}; do
	files=(${(z)${size_groups[$size]}})
	if (( ${#files[@]} > 1 )); then
		for file in "${files[@]}"; do
			hash=$(shasum -a 256 "$file" | awk '{print $1}')
				duplicate_groups[$hash]="${duplicate_groups[$hash]:-} $file"
		done
	fi
done

# Exif情報一括取得
echo "📷️Exif情報取得……"
# --2階層までチェック（全階層を確認する場合は「-maxdepth 2」を削除
exif_json=$(find "$target_dir" -maxdepth 2 \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.heic' -o -iname '*.mov' -o -iname '*.mp4' \) -type f -exec exiftool -j -CreateDate -MediaCreateDate {} + 2>/dev/null | jq -c '.[]')

# リネーム処理
echo "🔁リネーム処理開始……"
# --2階層までチェック（全階層を確認する場合は「-maxdepth 2」を削除
find "$target_dir" -maxdepth 2 \
		\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.heic' -o -iname '*.mov' -o -iname '*.mp4' -o -iname '*.aae' \) \
		-type f | while read -r file; do

	filename=$(basename "$file")
	dir=$(dirname "$file")
	
	# YYMMDD_hhmmss-で始まるファイルはスキップ
	if [[ "$filename" =~ ^[0-9]{6}_[0-9]{6}- ]]; then
		echo "🚫リネーム不要（日付時刻付き）：$file"
		continue
	fi

	# JSONから対応するCreateDateを取得
	json=$(echo "$exif_json" | jq -r "select(.SourceFile==\"$file\")")
	datetime=$(echo "$json" | jq -r '.CreateDate // .MediaCreateDate // empty')

	# statフォールバック
	if [[ -z "$datetime" ]]; then
		datetime=$(stat -f "%Sm" -t "%y%m%d_%H%M%S" "$file")
	else
		datetime=$(echo "$datetime" | sed -E 's/^..//; s/://g; s/ /_/')
	fi

	if [[ -z "$datetime" ]]; then
		echo "⚠️ 日付取得不可：$file"
		continue
	fi

	new_filename="${datetime}-${filename}"
	mv "$file" "$dir/$new_filename"
	echo "mv \"$dir/$new_filename\" \"$file\"" >> "$undo_script"
done

# 同一ファイルのリネーム後のパスを取得＆表示
for hash in ${(k)duplicate_groups}; do
	files=(${(z)${duplicate_groups[$hash]}})
	if (( ${#files[@]} > 1 )); then
		echo "📸 同一ファイル：(${#files})"
		echo "旧："
		for file in "${files[@]}"; do
			echo "$file"
		done
		echo "新："
		for file in "${files[@]}"; do
			# undo_scriptから新ファイル名を取得
			new_name=$(awk -v f="\"$file\"" '$3 == f {gsub(/"/,"",$2); print $2}' "$undo_script")
			if [[ -n "$new_name" ]]; then
				echo "$new_name"
			else
				echo "$file（リネームなし）"
			fi
		done
	fi
done


# 終了処理
echo "📝リネーム完了　UNDOスクリプト：$undo_script \n"
