package models

import (
	"encoding/json"
	"fmt"
)

// ToolPermissionSpec describes a supported declaration, not a browser grant.
// Keep this list shared by publishing, installation review and runtime policy.
type ToolPermissionSpec struct {
	Key           string `json:"key"`
	Group         string `json:"group"`
	Policy        string `json:"policy,omitempty"`
	Sandbox       string `json:"sandbox,omitempty"`
	Zh            string `json:"zh"`
	En            string `json:"en"`
	DescriptionZh string `json:"description_zh"`
	DescriptionEn string `json:"description_en"`
}

var ToolPermissionCatalog = []ToolPermissionSpec{
	{"socket_tcp", "files", "", "", "TCP 连接（后端代理）", "TCP connections (backend proxy)", "通过后端连接 TCP 服务，可访问后端所在网络，独立于网页网络权限。", "Connect to TCP services from the backend’s network, separately from browser network access."},
	{"modals", "interaction", "", "allow-modals", "浏览器对话框与打印", "Browser dialogs and printing", "允许请求浏览器对话框与打印；跨来源弹框仍受浏览器限制。", "Allow browser dialogs and printing; cross-origin dialogs remain browser-dependent."},
	{"gamepad", "advanced", "gamepad", "", "游戏手柄", "Game controllers", "读取用户连接的游戏手柄，依赖浏览器与用户操作。", "Read connected game controllers where supported and user-activated."},
	{"read_files", "files", "", "", "读取工具文件", "Read tool files", "读取、列目录、查询文件信息，仅限当前工具文件。", "Read, list and inspect files in this tool’s own storage."},
	{"save_files", "files", "", "", "保存工具文件", "Save tool files", "写入、创建目录、删除、重命名和移动；复制需同时开启读取。", "Write, create directories, remove and move files; copying also requires read access."},
	{"network", "files", "", "", "访问网络", "Network access", "允许网页请求外部服务；仍受浏览器跨域规则限制。", "Allow external requests, subject to browser cross-origin rules."},
	{"clipboard_read", "devices", "clipboard-read", "", "读取剪贴板", "Read clipboard", "读取剪贴板内容，需要浏览器许可或用户操作。", "Read clipboard contents with browser consent or user activation."},
	{"clipboard_write", "devices", "clipboard-write", "", "写入剪贴板", "Write clipboard", "将内容复制到剪贴板，需要用户操作。", "Copy content to the clipboard with user activation."},
	{"camera", "devices", "camera", "", "摄像头", "Camera", "请求摄像头，由浏览器确认设备和授权。", "Request a camera; the browser controls device selection and consent."},
	{"microphone", "devices", "microphone", "", "麦克风", "Microphone", "请求麦克风，由浏览器确认设备和授权。", "Request a microphone; the browser controls device selection and consent."},
	{"display_capture", "devices", "display-capture", "", "屏幕共享", "Screen capture", "用户每次选择屏幕或窗口，不能静默开启。", "The user selects a screen or window for each capture."},
	{"geolocation", "devices", "geolocation", "", "位置信息", "Location", "请求设备位置，需要浏览器授权。", "Request device location with browser consent."},
	{"fullscreen", "interaction", "fullscreen", "", "网页全屏", "Fullscreen", "允许工具内容请求全屏，与顶部页面全屏按钮独立。", "Allow tool content to request fullscreen, separately from the host toolbar."},
	{"autoplay", "interaction", "autoplay", "", "媒体自动播放", "Media autoplay", "允许尝试自动播放，浏览器仍可能要求用户操作。", "Allow autoplay attempts; the browser may still require user activation."},
	{"picture_in_picture", "interaction", "picture-in-picture", "", "画中画", "Picture in picture", "允许视频进入画中画窗口。", "Allow video to enter picture in picture."},
	{"downloads", "interaction", "", "allow-downloads", "下载文件", "File downloads", "允许工具通过浏览器下载文件到设备。", "Allow browser downloads to the device."},
	{"popups", "interaction", "", "allow-popups", "打开新窗口", "Open windows", "允许用户操作打开窗口；新窗口继续继承沙箱限制。", "Allow user-activated windows, which retain sandbox restrictions."},
	{"forms", "interaction", "", "allow-forms", "提交表单", "Form submissions", "允许提交 HTML 表单；外部提交还需要网络权限。", "Allow HTML forms; external submissions also require network access."},
	{"pointer_lock", "interaction", "", "allow-pointer-lock", "锁定鼠标", "Pointer lock", "游戏等工具可请求捕获鼠标，按 Esc 退出。", "Allow pointer capture for games and similar tools; Escape exits."},
	{"orientation_lock", "interaction", "", "allow-orientation-lock", "锁定屏幕方向", "Orientation lock", "允许请求锁定设备方向，依赖设备支持。", "Request an orientation lock on supported devices."},
	{"screen_wake_lock", "interaction", "screen-wake-lock", "", "保持屏幕唤醒", "Screen wake lock", "工具可见时请求屏幕保持点亮。", "Request that the screen stay awake while the tool is visible."},
	{"web_share", "interaction", "web-share", "", "系统分享", "System sharing", "用户操作时打开系统分享面板。", "Open the system share sheet after user activation."},
	{"presentation", "interaction", "", "allow-presentation", "外接屏幕演示", "Presentation", "允许请求在外接显示设备上演示。", "Request presentation on an external display."},
	{"speaker_selection", "advanced", "speaker-selection", "", "选择音频输出", "Audio output selection", "选择扬声器或耳机，取决于浏览器支持。", "Select speakers or headphones where supported."},
	{"bluetooth", "advanced", "bluetooth", "", "蓝牙设备", "Bluetooth", "由浏览器选择设备并授权，不能任意扫描。", "Select and authorize devices through the browser."},
	{"usb", "advanced", "usb", "", "USB 设备", "USB devices", "由浏览器选择 USB 设备并授权。", "Select and authorize USB devices through the browser."},
	{"serial", "advanced", "serial", "", "串口设备", "Serial ports", "由浏览器选择串口并授权。", "Select and authorize serial ports through the browser."},
	{"hid", "advanced", "hid", "", "HID 设备", "HID devices", "由浏览器选择键盘以外的受支持 HID 设备。", "Select supported HID devices through the browser."},
	{"midi", "advanced", "midi", "", "MIDI 设备", "MIDI devices", "请求 MIDI 设备访问，系统专有消息另受浏览器限制。", "Request MIDI access; system-exclusive messages have additional restrictions."},
	{"xr_spatial_tracking", "advanced", "xr-spatial-tracking", "", "空间追踪 / XR", "Spatial tracking / XR", "请求沉浸式设备与空间追踪。", "Request immersive devices and spatial tracking."},
	{"encrypted_media", "advanced", "encrypted-media", "", "受保护媒体", "Protected media", "允许使用浏览器的受保护媒体解码接口。", "Allow the browser’s encrypted media interfaces."},
	{"accelerometer", "advanced", "accelerometer", "", "加速度传感器", "Accelerometer", "读取设备加速度，依赖设备和浏览器支持。", "Read acceleration on supported devices and browsers."},
	{"gyroscope", "advanced", "gyroscope", "", "陀螺仪", "Gyroscope", "读取设备旋转信息。", "Read device rotation data."},
	{"magnetometer", "advanced", "magnetometer", "", "磁力传感器", "Magnetometer", "读取磁场方向信息。", "Read magnetic field information."},
	{"ambient_light_sensor", "advanced", "ambient-light-sensor", "", "环境光传感器", "Ambient light sensor", "读取环境光信息，依赖浏览器支持。", "Read ambient light data where supported."},
	{"local_fonts", "advanced", "local-fonts", "", "本地字体", "Local fonts", "用户授权后查询本地字体。", "Query installed fonts after browser consent."},
	{"window_management", "advanced", "window-management", "", "多屏窗口管理", "Window management", "请求多屏信息，移动窗口还需要新窗口权限。", "Request display information; opening windows also requires popup permission."},
	{"idle_detection", "advanced", "idle-detection", "", "空闲状态检测", "Idle detection", "用户授权后读取设备是否空闲。", "Read idle state after browser consent."},
	{"keyboard_map", "advanced", "keyboard-map", "", "键盘布局", "Keyboard layout", "查询物理键盘布局。", "Query physical keyboard layout."},
	{"payment", "advanced", "payment", "", "浏览器支付", "Browser payments", "用户确认后使用浏览器支付界面。", "Use the browser payment interface with user confirmation."},
	{"publickey_credentials_get", "advanced", "publickey-credentials-get", "", "使用通行密钥", "Use passkeys", "为工具自身来源请求通行密钥验证。", "Request passkey authentication for the tool’s own origin."},
	{"publickey_credentials_create", "advanced", "publickey-credentials-create", "", "创建通行密钥", "Create passkeys", "为工具自身来源注册通行密钥。", "Register passkeys for the tool’s own origin."},
}

// Schema zero packages predate explicit sandbox declarations. Preserve only the
// capabilities previously always enabled. Other new capabilities default off.
func (p ToolPermissions) Effective() ToolPermissions {
	if p.Schema == 0 {
		p.Downloads = true
		p.Forms = true
	}
	return p
}
func (p ToolPermissions) Flags() map[string]bool {
	data, _ := json.Marshal(p.Effective())
	var fields map[string]json.RawMessage
	_ = json.Unmarshal(data, &fields)
	result := map[string]bool{}
	for _, spec := range ToolPermissionCatalog {
		result[spec.Key] = string(fields[spec.Key]) == "true"
	}
	return result
}

// Refuse unknown declarations rather than silently granting a different set of
// capabilities than an incoming marketplace package claims to require.
func (p *ToolPermissions) UnmarshalJSON(raw []byte) error {
	type plain ToolPermissions
	var next plain
	if err := json.Unmarshal(raw, &next); err != nil {
		return err
	}
	if next.Schema < 0 || next.Schema > 1 {
		return fmt.Errorf("unsupported tool permission schema")
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(raw, &fields); err != nil {
		return err
	}
	known := map[string]bool{"schema": true}
	for _, spec := range ToolPermissionCatalog {
		known[spec.Key] = true
	}
	for key := range fields {
		if !known[key] {
			return fmt.Errorf("unknown tool permission: %s", key)
		}
	}
	*p = ToolPermissions(next)
	return nil
}
