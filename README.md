# WaveToSilence 1.0.0

Vẫy tay qua **cảm biến tiệm cận** để **tắt chuông** cuộc gọi đến — Phone thường
và mọi app gọi qua **CallKit** (Messenger, Zalo, WhatsApp...). Chỉ tắt tiếng,
**không cúp máy**: cuộc gọi vẫn đổ tiếp trên màn hình, hết cuộc gọi thì âm
lượng chuông tự trả lại như cũ.

Đây là ý tưởng số 8 (WaveToSilence) trong danh sách tweak của Quoc — làm
riêng khâu tắt chuông trước, là khâu chắc nhất trong họ "điều khiển cuộc gọi
không cần chạm" (vỗ tay nghe máy / vuốt để trả lời tính sau).

## Cách dùng

- Có cuộc gọi đến → **vẫy tay ngang qua cảm biến tiệm cận** (cạnh loa thoại,
  phía trên màn hình) → chuông im ngay.
- Tuỳ chọn trong **Cài đặt → WaveToSilence**:
  - Bật/tắt tweak.
  - **Vẫy 2 lần mới tắt** (hai lần trong 1,5 giây) — chống tắt nhầm.
  - Ghi log gỡ lỗi (mặc định bật ở bản đầu để chẩn đoán).
- Chống tắt nhầm sẵn có: nếu cảm biến đã bị che sẵn từ trước khi chuông đổ
  (máy trong túi, úp mặt trên bàn) thì vẫy không kích hoạt.

## Cách hoạt động (kỹ thuật)

- Phát hiện cuộc gọi bằng **CXCallObserver** (CallKit, API công khai) —
  không dùng %hook nào cả.
- Trong lúc đổ chuông, hỏi vòng cảm biến mỗi 100ms qua hai nguồn:
  `UIDevice.proximityState` và `SBProximitySensorManager` (dò selector lúc
  chạy); chỉ nhận "cú vẫy" ở cạnh trống → bị che.
- Tắt chuông bằng cách hạ âm lượng nhóm **Ringtone** về 0 qua
  `AVSystemController`; dự phòng dò các selector tắt chuông trên `TUCall`.
  Mọi khâu đều ghi vào `Documents/WaveToSilence.log` khi bật log.

## Giới hạn đã biết

- Chỉ tắt **tiếng** chuông, chưa tắt **rung**.
- Chỉ áp dụng cuộc gọi qua CallKit (hầu hết app gọi hiện nay đều dùng).
- Bản 1.0.0 mới kiểm tra tĩnh — cần test máy thật (iPhone 12 Pro, iOS 16.3.1)
  để xác nhận cả ba khâu trên máy.
