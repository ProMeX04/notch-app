#!/bin/zsh

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

IMG="/Users/promex04/.gemini/antigravity/brain/d8e99079-a824-4385-80e5-c74c44c94a5b/notch_app_icon_cropped.png"

if [ ! -f "$IMG" ]; then
    echo "Lỗi: Không tìm thấy file hình ảnh tại $IMG"
    exit 1
fi

echo "Đang tạo AppIcon.iconset..."
mkdir -p AppIcon.iconset

# Ép định dạng xuất chuẩn .png (do sips cảnh báo đuôi file JPG lúc trước)
sips -s format png -z 16 16 "$IMG" --out "AppIcon.iconset/icon_16x16.png" >/dev/null
sips -s format png -z 32 32 "$IMG" --out "AppIcon.iconset/icon_16x16@2x.png" >/dev/null
sips -s format png -z 32 32 "$IMG" --out "AppIcon.iconset/icon_32x32.png" >/dev/null
sips -s format png -z 64 64 "$IMG" --out "AppIcon.iconset/icon_32x32@2x.png" >/dev/null
sips -s format png -z 128 128 "$IMG" --out "AppIcon.iconset/icon_128x128.png" >/dev/null
sips -s format png -z 256 256 "$IMG" --out "AppIcon.iconset/icon_128x128@2x.png" >/dev/null
sips -s format png -z 256 256 "$IMG" --out "AppIcon.iconset/icon_256x256.png" >/dev/null
sips -s format png -z 512 512 "$IMG" --out "AppIcon.iconset/icon_256x256@2x.png" >/dev/null
sips -s format png -z 512 512 "$IMG" --out "AppIcon.iconset/icon_512x512.png" >/dev/null
sips -s format png -z 1024 1024 "$IMG" --out "AppIcon.iconset/icon_512x512@2x.png" >/dev/null

echo "Đang đóng gói thành AppIcon.icns..."
iconutil -c icns AppIcon.iconset

rm -rf AppIcon.iconset

echo "Hoàn tất tạo Icon! Đang chạy build-app.sh để cập nhật ứng dụng..."
./build-app.sh

# Restart app
pkill -f "dist/Notch.app" 2>/dev/null; sleep 0.5
open "dist/Notch.app"

# Hiển thị lệnh xoá cache để phòng hờ
echo "Hoàn tất! Nếu icon vẫn chưa thay đổi trên thanh Dock hoặc Finder, macOS có thể đang lưu cache. Mở tab mới chạy lệnh sau:"
echo "sudo rm -rf /Library/Caches/com.apple.iconservices.store; killall Dock"
