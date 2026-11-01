<prompt>
  <meta>
    <title>Advanced Card Customization: Local Image Picker, Background Library & Persistent Date Header</title>
    <version>3.0</version>
    <targetPlatform>Flutter (Mobile & Web Compatible)</targetPlatform>
  </meta>

  <goal>
    Nâng cấp ứng dụng Task & Habit Tracker với các tính năng nâng cao: 
    1. Cho phép người dùng chọn ảnh từ thiết bị cục bộ (hoặc tải lên) làm background động cho card.
    2. Quản lý một kho thư viện background có sẵn, cho phép người dùng tự thêm hoặc chọn dùng.
    3. Cho phép người dùng tự tạo mới nhãn dán (tags) tùy chỉnh cho hoạt động.
    4. Giữ cố định phần hiển thị ngày tháng, nút chọn lịch và nút "Hôm nay" ở đầu màn hình, không bị ẩn đi khi chuyển sang tab "Đã hoàn thành".
  </goal>

  <frsReference>
    Yêu cầu chức năng:
    - Tích hợp package `image_picker` để lấy ảnh từ thiết bị điện thoại/máy tính.
    - Xây dựng danh sách Background Library (kho hình nền động/tĩnh) lưu trữ trong local storage.
    - Cải tiến giao diện: Di chuyển phần Banner ngày tháng và bộ lọc nhãn lên trên cùng, đảm bảo trạng thái luôn hiển thị ở cả 2 tab ("Cần làm" và "Đã hoàn thành").
    - Cho phép lọc công việc đã hoàn thành theo ngày tháng tương tự tab cần làm nếu cần thiết.
  </frsReference>

  <planReference>
    Kiến trúc Flutter offline-first, lưu trữ dữ liệu bằng `SharedPreferences`, kết hợp thư viện `image_picker` để xử lý tệp tin hình ảnh cục bộ.
  </planReference>

  <taskUnit>
    Cập nhật tệp cấu hình `pubspec.yaml`, mở rộng model dữ liệu, chỉnh sửa bố cục layout (`Scaffold` / `ListView`) trong `main.dart` để cố định header ngày tháng, và xây dựng logic chọn/tải ảnh nền cục bộ.
  </taskUnit>

  <context>
    Ứng dụng Task & Habit Tracker cá nhân hóa. Giao diện đang gồm các thẻ hoạt động chủ đề, tính năng chỉnh sửa, nhãn dán dropdown, và hệ thống tab chuyển đổi.
  </context>

  <scope>
    - TRONG PHẠM VI: Thêm thư viện `image_picker`, cập nhật layout cố định header ngày tháng, bổ sung quản lý kho ảnh nền (Background Library) và tính năng tạo nhãn dán linh hoạt.
    - NGOÀI PHẠM VI: Không triển khai lưu trữ đám mây (Cloud Storage) phức tạp, chỉ xử lý trên bộ nhớ local của thiết bị.
  </scope>

  <hardRules>
    - Thanh hiển thị ngày tháng, nút chọn lịch (Calendar Picker) và nút "Hôm nay" PHẢI LUÔN HIỂN THỊ ở phần đầu màn hình, không được ẩn đi khi người dùng bấm chuyển sang tab "Đã hoàn thành".
    - Hỗ trợ chọn ảnh từ thư viện thiết bị bằng `image_picker` một cách mượt mà, tránh lỗi crash app trên các nền tảng khác nhau.
    - Đảm bảo lớp phủ mờ (overlay) luôn xuất hiện trên mọi background tùy chỉnh để văn bản luôn dễ đọc.
  </hardRules>

  <tasks>
    1. Thêm gói `image_picker: ^1.0.7` vào file `pubspec.yaml`.
    2. Điều chỉnh cấu trúc `ListView` / `Column` trong `main.dart` để đưa Banner ngày tháng lên trên cùng, tách biệt độc lập với trạng thái tab.
    3. Xây dựng giao diện chọn ảnh background: Chọn từ kho có sẵn (Background Library) hoặc bấm nút tải lên từ thiết bị (`ImagePicker`).
    4. Cập nhật cơ chế tạo nhãn dán (Tags) để người dùng tự do định nghĩa tên và màu sắc bất kỳ.
    5. Cập nhật bộ lọc hiển thị ở tab "Đã hoàn thành" để đồng bộ hoạt động với ngày được chọn trên header (hoặc hiển thị danh sách toàn cục tùy theo thiết kế).
  </tasks>

  <constraints>
    - Xử lý tương thích khi chạy trên Web (`kIsWeb`) đối với việc chọn ảnh (dùng `ImagePicker` với `XFile` bytes nếu cần).
  </constraints>

  <acceptanceCriteria>
    - Người dùng có thể bấm vào mục chọn background để tải ảnh từ máy lên hoặc chọn từ kho có sẵn cho Card nhiệm vụ.
    - Khi chuyển qua lại giữa tab "Cần làm" và "Đã hoàn thành", phần hiển thị ngày tháng và chọn lịch ở trên cùng vẫn giữ nguyên vị trí, không bị mất đi.
    - Người dùng có thể tạo thêm nhãn dán mới dễ dàng ngay trong dialog tạo/sửa task.
  </acceptanceCriteria>

  <testPlan>
    - Chạy ứng dụng, thêm mới một task và chọn tải ảnh nền từ thiết bị cục bộ.
    - Kiểm tra xem card hiển thị ảnh nền đúng không.
    - Chuyển sang tab "Đã hoàn thành" và xác nhận banner ngày tháng ở đầu trang vẫn hiển thị bình thường.
  </testPlan>

  <outputRequired>
    Cung cấp mã nguồn cập nhật cho file `pubspec.yaml` và file `main.dart` hoàn chỉnh đáp ứng toàn bộ các yêu cầu trên.
  </outputRequired>
</prompt>