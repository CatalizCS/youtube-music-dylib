# YouTube Music Discord RPC for iOS 🎵📱

Tweak iOS giúp hiển thị trạng thái phát nhạc (Rich Presence) của **YouTube Music** lên tài khoản **Discord** cá nhân của bạn theo thời gian thực. 

Dự án được thiết kế độc lập, không phụ thuộc vào `CydiaSubstrate` (Substrate-less Category Swizzling), giúp tương thích hoàn hảo 100% với các thiết bị chưa Jailbreak thông qua việc sideload/nhúng dylib bằng các công cụ như **LiveContainer**, **TrollStore**, **Sideloadly**, **AltStore**, hoặc **TrollFools**.

---

## ✨ Tính Năng Nổi Bật

1. **Hiển Thị Trạng Thái Thời Gian Thực**: Hiển thị tên bài hát, nghệ sĩ, tên album và thanh tiến trình phát nhạc (thời gian đã trôi qua / tổng thời gian) trên Discord.
2. **Ảnh Bìa Động**: Tự động ánh xạ `videoId` của YouTube để tải và hiển thị ảnh bìa chất lượng cao trên trạng thái Discord.
3. **Cài Đặt Trực Tiếp Trong App**: Nút cài đặt được nhúng gọn gàng trong phần menu tài khoản (Avatar góc trên bên phải) của YouTube Music.
4. **Chọn Nhanh Hoạt Động (Activity Status)**:
   - Cho phép đính kèm trạng thái hoạt động bên cạnh thông tin bài hát (Ví dụ: `Nghệ Sĩ | 🚗 Đang đi đường` hoặc `Nghệ Sĩ | 🏃 Đang chạy bộ`).
   - Có menu bật/tắt **Hỏi hoạt động khi mở app** (Tự động hiển thị Action Sheet để bạn chọn nhanh hoạt động mỗi khi mở ứng dụng).
5. **Xem Log Trực Tiếp (In-App Log Viewer)**:
   - Cho phép theo dõi kết nối WebSocket với Discord Gateway và debug lỗi kết nối trực tiếp trong app mà không cần kết nối máy tính.
   - Hỗ trợ làm mới (Refresh) và xóa log (Clear) trực quan.
6. **Tối Ưu Hóa Băng Thông & Tỷ Lệ Gửi**: Tự động chống nghẽn (debouncing) để tránh bị Discord khóa tài khoản khi bạn chuyển bài hát quá nhanh.
7. **Hỗ Trợ Payload Lớn**: Tự động mở rộng giới hạn bộ đệm nhận tin nhắn WebSocket lên 10MB để tránh lỗi đóng kết nối khi nhận danh sách bạn bè/server khổng lồ từ Discord lúc khởi động.

---

## 🛠️ Hướng Dẫn Biên Dịch (Build)

### Cách 1: Sử Dụng GitHub Actions (Khuyên dùng)
Dự án đã được cấu hình sẵn GitHub Actions trong thư mục `.github/workflows/build.yml`.
1. Fork repository này về tài khoản GitHub cá nhân.
2. Đẩy (Push) các thay đổi lên nhánh chính (`main`).
3. Đi tới mục **Actions** trên GitHub và tải về tệp `.dylib` đã được biên dịch tự động.

### Cách 2: Biên Dịch Thủ Công (Với Theos)
Bạn cần một môi trường cài đặt sẵn [Theos](https://theos.dev/) (macOS, Linux/WSL, hoặc trên chính thiết bị iOS).

1. Clone dự án về máy:
   ```bash
   git clone https://github.com/username/youtube-music-dylib.git
   cd youtube-music-dylib
   ```
2. Thực hiện lệnh build:
   ```bash
   make package
   ```
   *Nếu biên dịch để nhúng vào IPA (Sideloading):*
   ```bash
   make package SIDELOADING=1
   ```
3. File `.dylib` biên dịch thành công sẽ nằm trong thư mục `.theos/obj/debug/` hoặc `.theos/obj/`.

---

## 🚀 Hướng Dẫn Nhúng & Cài Đặt (Sideload)

Để sử dụng tweak này, bạn cần có tệp `.ipa` của YouTube Music đã được decrypt (giải mã).

### 1. Nhúng dylib vào IPA
* **Sideloadly (Đơn giản nhất)**: 
  Kéo thả file `.ipa` vào Sideloadly -> Mở mục **Advanced options** -> Tại phần **Inject dylibs**, chọn file `YTMusicDiscordRPC.dylib` -> Tiến hành ký và cài đặt.
* **optool (Dành cho máy Mac)**:
  ```bash
  optool install -c load -p "@executable_path/YTMusicDiscordRPC.dylib" -t YouTubeMusic.app/YouTubeMusic
  ```

### 2. Cài đặt lên thiết bị
Sau khi đã nhúng `.dylib` thành công, bạn ký ứng dụng bằng tài khoản nhà phát triển (hoặc dùng các chứng chỉ cá nhân) thông qua TrollStore, AltStore, Sideloadly hoặc TrollFools để cài vào điện thoại.

---

## 📖 Hướng Dẫn Sử Dụng

1. Mở ứng dụng **YouTube Music** vừa cài đặt.
2. Nếu Discord RPC đã được kích hoạt, một thông báo chọn nhanh hoạt động sẽ hiện ra để bạn chọn trạng thái hiện tại (Normal, Đi đường, Chạy bộ, Học bài...).
3. Nhấp vào ảnh **Avatar tài khoản** của bạn ở góc trên bên phải màn hình -> Chọn mục **Discord RPC**.
4. Cấu hình các thông tin:
   - **Enable Discord RPC**: Bật/Tắt tính năng.
   - **Current Activity**: Chọn thủ công hoạt động của bạn.
   - **Quick Select on Startup**: Bật/Tắt hiển thị bảng chọn nhanh hoạt động mỗi khi mở app.
   - **Token**: Nhập mã token tài khoản Discord của bạn (để kết nối tới Discord Gateway).
   - **App ID**: Nhập Client ID ứng dụng Discord của bạn (hoặc bỏ trống để sử dụng ứng dụng YouTube Music mặc định của tweak).
5. Bấm **Save** ở góc trên bên phải để lưu cấu hình. 
6. Thưởng thức âm nhạc! Trạng thái của bạn trên Discord sẽ lập tức đồng bộ hóa.

---

## ⚠️ Lưu Ý Bảo Mật & Điều Khoản (TOS)

> [!WARNING]
> **Mã Token Discord:**
> Tệp token cá nhân của bạn được lưu trữ cục bộ một cách an toàn trong sandbox của ứng dụng thông qua hệ thống `NSUserDefaults` của thiết bị. **Tuyệt đối không chia sẻ mã Token này cho bất cứ ai**, vì nó cấp toàn quyền truy cập tài khoản Discord của bạn.

> [!CAUTION]
> **Điều khoản sử dụng của Discord (Self-Botting):**
> Việc tự động hóa tài khoản người dùng gửi trạng thái lên hệ thống Gateway vi phạm điều khoản dịch vụ (TOS) của Discord về hành vi "self-bot". Mặc dù tweak chỉ gửi các gói tin cập nhật trạng thái đơn thuần (khó bị quét), bạn vẫn nên cân nhắc rủi ro bị khóa tài khoản trước khi sử dụng.
