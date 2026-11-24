package models

import (
	"database/sql"
	"errors"
)

// ToolSource gives a tool its own identity; an article is only one possible source.
type ToolSource struct {
	ID       int64         `json:"id"`
	MemberID int64         `json:"-"`
	Kind     string        `json:"kind"`
	Package  string        `json:"package,omitempty"`
	BlogID   sql.NullInt64 `json:"-"`
}

const toolReleaseSchema = `CREATE TABLE IF NOT EXISTS md_tool_releases(tool_id INTEGER PRIMARY KEY REFERENCES md_tools(tool_id) ON DELETE CASCADE,title TEXT NOT NULL,description TEXT NOT NULL,content TEXT NOT NULL,revision TEXT NOT NULL)`
const toolVersionSchema = `CREATE TABLE IF NOT EXISTS md_tool_versions(tool_id INTEGER NOT NULL REFERENCES md_tools(tool_id) ON DELETE CASCADE,version TEXT NOT NULL,revision TEXT NOT NULL UNIQUE,metadata TEXT NOT NULL,content TEXT NOT NULL,resource_base TEXT NOT NULL,status TEXT NOT NULL,created INTEGER NOT NULL,PRIMARY KEY(tool_id,version))`

func initToolSourceTables() error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err = tx.Exec(`CREATE TABLE IF NOT EXISTS md_tools(tool_id INTEGER PRIMARY KEY AUTOINCREMENT,member_id INTEGER NOT NULL REFERENCES md_members(member_id) ON DELETE CASCADE,kind TEXT NOT NULL CHECK(kind IN ('article','package')),blog_id INTEGER UNIQUE REFERENCES md_blogs(blog_id) ON DELETE CASCADE,package_token TEXT NOT NULL DEFAULT '')`); err != nil {
		return err
	}
	var packageColumn int
	if err = tx.QueryRow(`SELECT COUNT(*) FROM pragma_table_info('md_tools') WHERE name='package_token'`).Scan(&packageColumn); err != nil {
		return err
	}
	if packageColumn == 0 {
		if _, err = tx.Exec(`ALTER TABLE md_tools ADD COLUMN package_token TEXT NOT NULL DEFAULT ''`); err != nil {
			return err
		}
	}
	var legacy int
	if err = tx.QueryRow(`SELECT COUNT(*) FROM pragma_table_info('md_tool_releases') WHERE name='blog_id'`).Scan(&legacy); err != nil {
		return err
	}
	if legacy > 0 {
		if _, err = tx.Exec(`DROP TRIGGER IF EXISTS md_tool_source_delete_guard`); err != nil {
			return err
		}
		if _, err = tx.Exec(`INSERT OR IGNORE INTO md_tools(tool_id,member_id,kind,blog_id) SELECT b.blog_id,b.member_id,'article',b.blog_id FROM md_blogs b WHERE b.blog_id IN (SELECT blog_id FROM md_tool_releases UNION SELECT blog_id FROM md_tool_versions)`); err != nil {
			return err
		}
		for _, name := range []string{"md_tool_releases", "md_tool_versions"} {
			var schema string
			if name == "md_tool_releases" {
				schema = toolReleaseSchema
			} else {
				schema = toolVersionSchema
			}
			if _, err = tx.Exec(`ALTER TABLE ` + name + ` RENAME TO ` + name + `_legacy`); err != nil {
				return err
			}
			if _, err = tx.Exec(schema); err != nil {
				return err
			}
			if _, err = tx.Exec(`INSERT INTO ` + name + ` SELECT * FROM ` + name + `_legacy`); err != nil {
				return err
			}
			if _, err = tx.Exec(`DROP TABLE ` + name + `_legacy`); err != nil {
				return err
			}
		}
	}
	for _, q := range []string{toolReleaseSchema, toolVersionSchema, `CREATE INDEX IF NOT EXISTS md_tools_owner ON md_tools(member_id,kind)`} {
		if _, err = tx.Exec(q); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func GetToolSource(id int64) (ToolSource, error) {
	var s ToolSource
	err := DB.QueryRow(`SELECT tool_id,member_id,kind,blog_id,package_token FROM md_tools WHERE tool_id=?`, id).Scan(&s.ID, &s.MemberID, &s.Kind, &s.BlogID, &s.Package)
	return s, err
}
func ArticleToolID(blog int64) (int64, error) {
	var id int64
	err := DB.QueryRow(`SELECT tool_id FROM md_tools WHERE blog_id=?`, blog).Scan(&id)
	return id, err
}
func EnsureArticleTool(blog, member int64) (int64, error) {
	if id, err := ArticleToolID(blog); err == nil {
		return id, nil
	} else if !errors.Is(err, sql.ErrNoRows) {
		return 0, err
	}
	// Retain article IDs when free, including installations from older clients.
	tx, err := DB.Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	if _, err = tx.Exec(`INSERT OR IGNORE INTO md_tools(tool_id,member_id,kind,blog_id) VALUES(?,?,'article',?)`, blog, member, blog); err != nil {
		return 0, err
	}
	if _, err = tx.Exec(`INSERT OR IGNORE INTO md_tools(member_id,kind,blog_id) VALUES(?,'article',?)`, member, blog); err != nil {
		return 0, err
	}
	var id int64
	if err = tx.QueryRow(`SELECT tool_id FROM md_tools WHERE blog_id=?`, blog).Scan(&id); err != nil {
		return 0, err
	}
	return id, tx.Commit()
}
