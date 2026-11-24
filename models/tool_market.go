package models

import (
	"database/sql"
	"encoding/json"
	"errors"
)

// DefaultToolMarketURL is used until a workspace chooses its marketplace source.
const DefaultToolMarketURL = "https://books.vs2010wy.top/market"

var ErrBlogUsedByTool = errors.New("blog_in_tool_market")

func toolSourceInUse(tx *sql.Tx, id int64) (bool, error) {
	var used bool
	err := tx.QueryRow(`SELECT EXISTS(SELECT 1 FROM md_tool_releases p JOIN md_tools s USING(tool_id) WHERE s.blog_id=?) OR EXISTS(SELECT 1 FROM md_tool_versions v JOIN md_tools s USING(tool_id) WHERE s.blog_id=? AND v.status='pending')`, id, id).Scan(&used)
	return used, err
}

type ToolPermissions struct {
	SocketTCP        bool `json:"socket_tcp,omitempty"`
	Modals           bool `json:"modals,omitempty"`
	Gamepad          bool `json:"gamepad,omitempty"`
	Schema           int  `json:"schema,omitempty"`
	ReadFiles        bool `json:"read_files"`
	SaveFiles        bool `json:"save_files"`
	Network          bool `json:"network"`
	ClipboardRead    bool `json:"clipboard_read,omitempty"`
	ClipboardWrite   bool `json:"clipboard_write,omitempty"`
	Camera           bool `json:"camera,omitempty"`
	Microphone       bool `json:"microphone,omitempty"`
	DisplayCapture   bool `json:"display_capture,omitempty"`
	Geolocation      bool `json:"geolocation,omitempty"`
	Fullscreen       bool `json:"fullscreen,omitempty"`
	Autoplay         bool `json:"autoplay,omitempty"`
	PictureInPicture bool `json:"picture_in_picture,omitempty"`
	Downloads        bool `json:"downloads,omitempty"`
	Popups           bool `json:"popups,omitempty"`
	Forms            bool `json:"forms,omitempty"`
	PointerLock      bool `json:"pointer_lock,omitempty"`
	OrientationLock  bool `json:"orientation_lock,omitempty"`
	WakeLock         bool `json:"screen_wake_lock,omitempty"`
	WebShare         bool `json:"web_share,omitempty"`
	Presentation     bool `json:"presentation,omitempty"`
	SpeakerSelection bool `json:"speaker_selection,omitempty"`
	Bluetooth        bool `json:"bluetooth,omitempty"`
	USB              bool `json:"usb,omitempty"`
	Serial           bool `json:"serial,omitempty"`
	HID              bool `json:"hid,omitempty"`
	MIDI             bool `json:"midi,omitempty"`
	XR               bool `json:"xr_spatial_tracking,omitempty"`
	EncryptedMedia   bool `json:"encrypted_media,omitempty"`
	Accelerometer    bool `json:"accelerometer,omitempty"`
	Gyroscope        bool `json:"gyroscope,omitempty"`
	Magnetometer     bool `json:"magnetometer,omitempty"`
	AmbientLight     bool `json:"ambient_light_sensor,omitempty"`
	LocalFonts       bool `json:"local_fonts,omitempty"`
	WindowManagement bool `json:"window_management,omitempty"`
	IdleDetection    bool `json:"idle_detection,omitempty"`
	KeyboardMap      bool `json:"keyboard_map,omitempty"`
	Payment          bool `json:"payment,omitempty"`
	PublicKeyGet     bool `json:"publickey_credentials_get,omitempty"`
	PublicKeyCreate  bool `json:"publickey_credentials_create,omitempty"`
}
type ToolMetadata struct {
	SourceKind   string          `json:"source_kind,omitempty"`
	Entry        string          `json:"entry,omitempty"`
	Package      string          `json:"package,omitempty"`
	Updated      int64           `json:"updated"`
	Distribution string          `json:"distribution,omitempty"`
	Title        string          `json:"title,omitempty"`
	Description  string          `json:"description,omitempty"`
	Version      string          `json:"version"`
	Category     string          `json:"category"`
	Icon         string          `json:"icon,omitempty"`
	IconStyle    string          `json:"icon_style,omitempty"`
	IconColor    string          `json:"icon_color,omitempty"`
	Size         int64           `json:"size"`
	AssetCount   int             `json:"asset_count"`
	Offline      bool            `json:"offline"`
	Access       string          `json:"access"`
	Members      []int64         `json:"members,omitempty"`
	Permissions  ToolPermissions `json:"permissions"`
	Notes        string          `json:"notes"`
	Status       string          `json:"status"`
	Hash         string          `json:"hash"`
	DataRoot     string          `json:"data_root,omitempty"`
}

func initToolMarketTables() error {
	for _, q := range []string{
		`CREATE TABLE IF NOT EXISTS md_tool_packages(token TEXT PRIMARY KEY,member_id INTEGER NOT NULL REFERENCES md_members(member_id) ON DELETE CASCADE,metadata TEXT NOT NULL,created INTEGER NOT NULL)`,
		`CREATE TABLE IF NOT EXISTS md_tool_retained(member_id INTEGER NOT NULL REFERENCES md_members(member_id) ON DELETE CASCADE,tool_id INTEGER NOT NULL,root TEXT NOT NULL,values_json TEXT NOT NULL,PRIMARY KEY(member_id,tool_id))`,
		`CREATE TABLE IF NOT EXISTS md_tool_install_metadata(member_id INTEGER NOT NULL,tool_id INTEGER NOT NULL,metadata TEXT NOT NULL,PRIMARY KEY(member_id,tool_id))`,
		`CREATE TABLE IF NOT EXISTS md_tool_market_clients(member_id INTEGER PRIMARY KEY REFERENCES md_members(member_id) ON DELETE CASCADE,url TEXT NOT NULL DEFAULT '',check_updates INTEGER NOT NULL DEFAULT 1,auto_update INTEGER NOT NULL DEFAULT 0)`,
		`CREATE TABLE IF NOT EXISTS md_tool_market_credentials(member_id INTEGER NOT NULL REFERENCES md_members(member_id) ON DELETE CASCADE,url TEXT NOT NULL,account TEXT NOT NULL,token TEXT NOT NULL,PRIMARY KEY(member_id,url))`,
		`CREATE TABLE IF NOT EXISTS md_tool_market_sessions(token_hash TEXT PRIMARY KEY,member_id INTEGER NOT NULL REFERENCES md_members(member_id) ON DELETE CASCADE,expires INTEGER NOT NULL,auth_version INTEGER NOT NULL DEFAULT 0)`,
	} {
		if _, err := DB.Exec(q); err != nil {
			return err
		}
	}
	_, err := DB.Exec(`CREATE TRIGGER IF NOT EXISTS md_tool_source_delete_guard
	BEFORE DELETE ON md_blogs
	WHEN EXISTS(SELECT 1 FROM md_tool_releases p JOIN md_tools s USING(tool_id) WHERE s.blog_id=OLD.blog_id)
	  OR EXISTS(SELECT 1 FROM md_tool_versions v JOIN md_tools s USING(tool_id) WHERE s.blog_id=OLD.blog_id AND v.status='pending')
	BEGIN SELECT RAISE(ABORT, 'blog_in_tool_market'); END`)
	return err
}
func ReadToolMetadata(member, id int64) ToolMetadata {
	var raw string
	var m ToolMetadata
	if DB.QueryRow("SELECT metadata FROM md_tool_install_metadata WHERE member_id=? AND tool_id=?", member, id).Scan(&raw) == nil {
		json.Unmarshal([]byte(raw), &m)
	}
	return m
}
func SaveToolMetadata(tx *sql.Tx, member, id int64, m ToolMetadata) error {
	raw, err := json.Marshal(m)
	if err != nil {
		return err
	}
	_, err = tx.Exec(`INSERT INTO md_tool_install_metadata(member_id,tool_id,metadata) VALUES(?,?,?) ON CONFLICT(member_id,tool_id) DO UPDATE SET metadata=excluded.metadata`, member, id, string(raw))
	return err
}
